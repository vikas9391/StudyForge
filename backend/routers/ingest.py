"""
routers/ingest.py
Alternative input sources beyond PDF/DOCX.

POST /ingest/url      — scrape a webpage and extract readable text
POST /ingest/youtube  — fetch YouTube transcript via youtube-transcript-api
POST /ingest/ocr      — extract text from an image using pytesseract (free)

All endpoints return the same shape as POST /upload so the Flutter app
can feed the result straight into POST /process unchanged.
"""

import re
import io
import os
import uuid
import httpx

from fastapi import APIRouter, HTTPException, UploadFile, File, Form
from pydantic import BaseModel

from utils.supabase_helpers import save_result
from utils.supabase_client import get_supabase

router = APIRouter()

MAX_CHARS = 15_000   # ~3k tokens — stays within free HF model limits


# ── Helpers ───────────────────────────────────────────────────────────────────

def _truncate(text: str) -> str:
    return text[:MAX_CHARS] if len(text) > MAX_CHARS else text


def _save_stub(user_id: str, source_url: str, title: str) -> str:
    """Save a pending stub row and return result_id."""
    return save_result(
        user_id=user_id,
        file_url=source_url,
        file_name=title,
        summary="__pending__",
        quiz=[],
        flashcards=[],
    )


# ── URL scraping ──────────────────────────────────────────────────────────────

class UrlRequest(BaseModel):
    url:     str
    user_id: str


@router.post("/url")
async def ingest_url(body: UrlRequest):
    """
    Fetch a webpage and strip it to readable text using BeautifulSoup.

    Requires: pip install beautifulsoup4 httpx
    """
    try:
        from bs4 import BeautifulSoup
    except ImportError:
        raise HTTPException(500, "BeautifulSoup not installed. Run: pip install beautifulsoup4")

    try:
        async with httpx.AsyncClient(timeout=20, follow_redirects=True) as client:
            resp = await client.get(
                body.url,
                headers={"User-Agent": "Mozilla/5.0 (StudyForge/3.0)"},
            )
            resp.raise_for_status()
            html = resp.text
    except httpx.HTTPError as e:
        raise HTTPException(502, f"Could not fetch URL: {e}")

    soup = BeautifulSoup(html, "html.parser")

    # Remove noise
    for tag in soup(["script", "style", "nav", "footer", "header",
                     "aside", "form", "noscript", "iframe"]):
        tag.decompose()

    # Try article/main first, fall back to body
    content = (
        soup.find("article") or
        soup.find("main") or
        soup.find(id=re.compile(r"content|article|post", re.I)) or
        soup.find("body")
    )

    if not content:
        raise HTTPException(422, "Could not extract readable content from this page.")

    text = content.get_text(separator="\n", strip=True)
    text = re.sub(r"\n{3,}", "\n\n", text).strip()

    if len(text) < 100:
        raise HTTPException(422, "Not enough text found on this page.")

    title = soup.title.string.strip() if soup.title else body.url
    extracted = _truncate(text)
    result_id = _save_stub(body.user_id, body.url, title)

    return {
        "result_id":      result_id,
        "file_url":       body.url,
        "file_name":      title,
        "char_count":     len(extracted),
        "extracted_text": extracted,
        "source":         "url",
        "message":        "Webpage extracted! Call POST /process to generate study materials.",
    }


# ── YouTube transcript ────────────────────────────────────────────────────────

class YouTubeRequest(BaseModel):
    url:     str
    user_id: str


def _extract_video_id(url: str) -> str | None:
    patterns = [
        r"(?:v=|youtu\.be/)([A-Za-z0-9_-]{11})",
        r"(?:embed/)([A-Za-z0-9_-]{11})",
        r"(?:shorts/)([A-Za-z0-9_-]{11})",
    ]
    for p in patterns:
        m = re.search(p, url)
        if m:
            return m.group(1)
    return None


@router.post("/youtube")
async def ingest_youtube(body: YouTubeRequest):
    """
    Fetch a YouTube video's transcript and use it as study material.

    Requires: pip install youtube-transcript-api
    Works on any public video with captions (auto-generated included).
    """
    try:
        from youtube_transcript_api import YouTubeTranscriptApi, TranscriptsDisabled, NoTranscriptFound
    except ImportError:
        raise HTTPException(500, "youtube-transcript-api not installed. Run: pip install youtube-transcript-api")

    video_id = _extract_video_id(body.url)
    if not video_id:
        raise HTTPException(422, "Could not extract a video ID from that URL.")

    try:
        transcript_list = YouTubeTranscriptApi.get_transcript(
            video_id, languages=["en", "en-US", "en-GB", "a.en"]
        )
    except Exception as exc:
        name = type(exc).__name__
        if "Disabled" in name or "NoTranscript" in name:
            raise HTTPException(422, "This video has no captions available.")
        raise HTTPException(502, f"Transcript fetch failed: {exc}")

    # Join transcript segments into paragraphs (group every ~10 segments)
    chunks = []
    for i in range(0, len(transcript_list), 10):
        group = transcript_list[i:i+10]
        chunks.append(" ".join(s["text"].replace("\n", " ") for s in group))
    text = "\n\n".join(chunks).strip()

    if not text:
        raise HTTPException(422, "Transcript is empty.")

    # Fetch video title from oEmbed (no API key required)
    title = f"YouTube: {video_id}"
    try:
        async with httpx.AsyncClient(timeout=8) as client:
            oembed = await client.get(
                f"https://www.youtube.com/oembed?url=https://youtu.be/{video_id}&format=json"
            )
            if oembed.status_code == 200:
                title = oembed.json().get("title", title)
    except Exception:
        pass

    extracted = _truncate(text)
    result_id = _save_stub(body.user_id, body.url, title)

    return {
        "result_id":      result_id,
        "file_url":       body.url,
        "file_name":      title,
        "char_count":     len(extracted),
        "extracted_text": extracted,
        "source":         "youtube",
        "message":        "Transcript fetched! Call POST /process to generate study materials.",
    }


# ── Image OCR ─────────────────────────────────────────────────────────────────

@router.post("/ocr")
async def ingest_ocr(
    file:    UploadFile = File(..., description="JPEG or PNG image of text"),
    user_id: str        = Form(...),
):
    """
    Extract text from an image using pytesseract (free, local).

    Requires:
      pip install pytesseract Pillow
      sudo apt-get install tesseract-ocr   (or brew install tesseract on Mac)
    """
    try:
        import pytesseract
        from PIL import Image
    except ImportError:
        raise HTTPException(
            500,
            "pytesseract or Pillow not installed. "
            "Run: pip install pytesseract Pillow  "
            "and install Tesseract: https://github.com/tesseract-ocr/tesseract"
        )

    allowed = {"image/jpeg", "image/png", "image/jpg", "image/webp"}
    if file.content_type not in allowed:
        raise HTTPException(422, "Only JPEG or PNG images are supported for OCR.")

    file_bytes = await file.read()
    if len(file_bytes) > 10 * 1024 * 1024:
        raise HTTPException(413, "Image must be under 10 MB.")

    try:
        image = Image.open(io.BytesIO(file_bytes))
        # Upscale small images for better OCR accuracy
        w, h = image.size
        if w < 1000:
            scale = 1000 / w
            image = image.resize((int(w * scale), int(h * scale)), Image.LANCZOS)

        text = pytesseract.image_to_string(image, config="--psm 3")
        text = re.sub(r"\n{3,}", "\n\n", text).strip()
    except Exception as e:
        raise HTTPException(422, f"OCR failed: {e}")

    if len(text) < 50:
        raise HTTPException(
            422,
            "Not enough text detected. Make sure the image is clear and well-lit."
        )

    title = file.filename or "Scanned notes"
    extracted = _truncate(text)
    result_id = _save_stub(user_id, "", title)

    return {
        "result_id":      result_id,
        "file_url":       "",
        "file_name":      title,
        "char_count":     len(extracted),
        "extracted_text": extracted,
        "source":         "ocr",
        "message":        "Text extracted from image! Call POST /process to generate study materials.",
    }