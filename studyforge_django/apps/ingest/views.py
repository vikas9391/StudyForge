"""
apps/ingest/views.py
Mirrors routers/ingest.py — URL scraping, YouTube transcript, OCR.
All logic is identical; only the framework glue changed.
"""

import re
import io

from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from rest_framework.parsers import MultiPartParser, FormParser, JSONParser

from apps.results.models import Result

MAX_CHARS = 15_000


def _truncate(text):
    return text[:MAX_CHARS] if len(text) > MAX_CHARS else text


def _save_stub(user, source_url, title):
    result = Result.objects.create(
        user      = user,
        file_url  = source_url,
        file_name = title,
        summary   = "__pending__",
        quiz      = [],
        flashcards= [],
    )
    return str(result.id)


# ── URL scraping ───────────────────────────────────────────────────────────────

class IngestURLView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        """POST /ingest/url/ — scrape webpage and extract readable text."""
        try:
            from bs4 import BeautifulSoup
        except ImportError:
            return Response({"detail": "BeautifulSoup not installed."}, status=500)

        import httpx
        url = request.data.get("url", "")
        if not url:
            return Response({"detail": "url is required."}, status=400)

        try:
            resp = httpx.get(url, headers={"User-Agent": "Mozilla/5.0 (StudyForge/3.0)"},
                             timeout=20, follow_redirects=True)
            resp.raise_for_status()
            html = resp.text
        except Exception as e:
            return Response({"detail": f"Could not fetch URL: {e}"}, status=502)

        soup = BeautifulSoup(html, "html.parser")
        for tag in soup(["script", "style", "nav", "footer", "header",
                          "aside", "form", "noscript", "iframe"]):
            tag.decompose()

        content = (
            soup.find("article") or
            soup.find("main") or
            soup.find(id=re.compile(r"content|article|post", re.I)) or
            soup.find("body")
        )

        if not content:
            return Response({"detail": "Could not extract readable content."}, status=422)

        text = content.get_text(separator="\n", strip=True)
        text = re.sub(r"\n{3,}", "\n\n", text).strip()

        if len(text) < 100:
            return Response({"detail": "Not enough text found on this page."}, status=422)

        title     = soup.title.string.strip() if soup.title else url
        extracted = _truncate(text)
        result_id = _save_stub(request.user, url, title)

        return Response({
            "result_id":      result_id,
            "file_url":       url,
            "file_name":      title,
            "char_count":     len(extracted),
            "extracted_text": extracted,
            "source":         "url",
            "message":        "Webpage extracted! Call POST /process/ to generate study materials.",
        }, status=201)


# ── YouTube transcript ─────────────────────────────────────────────────────────

def _extract_video_id(url):
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


class IngestYouTubeView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        """POST /ingest/youtube/ — fetch YouTube transcript."""
        try:
            from youtube_transcript_api import YouTubeTranscriptApi
        except ImportError:
            return Response({"detail": "youtube-transcript-api not installed."}, status=500)

        import httpx
        url      = request.data.get("url", "")
        video_id = _extract_video_id(url)
        if not video_id:
            return Response({"detail": "Could not extract a video ID from that URL."}, status=422)

        try:
            transcript_list = YouTubeTranscriptApi.get_transcript(
                video_id, languages=["en", "en-US", "en-GB", "a.en"]
            )
        except Exception as exc:
            name = type(exc).__name__
            if "Disabled" in name or "NoTranscript" in name:
                return Response({"detail": "This video has no captions available."}, status=422)
            return Response({"detail": f"Transcript fetch failed: {exc}"}, status=502)

        chunks = []
        for i in range(0, len(transcript_list), 10):
            group = transcript_list[i:i+10]
            chunks.append(" ".join(s["text"].replace("\n", " ") for s in group))
        text = "\n\n".join(chunks).strip()

        if not text:
            return Response({"detail": "Transcript is empty."}, status=422)

        title = f"YouTube: {video_id}"
        try:
            resp = httpx.get(
                f"https://www.youtube.com/oembed?url=https://youtu.be/{video_id}&format=json",
                timeout=8
            )
            if resp.status_code == 200:
                title = resp.json().get("title", title)
        except Exception:
            pass

        extracted = _truncate(text)
        result_id = _save_stub(request.user, url, title)

        return Response({
            "result_id":      result_id,
            "file_url":       url,
            "file_name":      title,
            "char_count":     len(extracted),
            "extracted_text": extracted,
            "source":         "youtube",
            "message":        "Transcript fetched! Call POST /process/ to generate study materials.",
        }, status=201)


# ── Image OCR ──────────────────────────────────────────────────────────────────

class IngestOCRView(APIView):
    permission_classes = [IsAuthenticated]
    parser_classes     = [MultiPartParser, FormParser]

    def post(self, request):
        """POST /ingest/ocr/ — extract text from image using pytesseract."""
        try:
            import pytesseract
            from PIL import Image
        except ImportError:
            return Response({"detail": "pytesseract or Pillow not installed."}, status=500)

        file = request.FILES.get("file")
        if not file:
            return Response({"detail": "No file provided."}, status=400)

        allowed = {"image/jpeg", "image/png", "image/jpg", "image/webp"}
        if file.content_type not in allowed:
            return Response({"detail": "Only JPEG or PNG images are supported."}, status=422)

        file_bytes = file.read()
        if len(file_bytes) > 10 * 1024 * 1024:
            return Response({"detail": "Image must be under 10 MB."}, status=413)

        try:
            image = Image.open(io.BytesIO(file_bytes))
            w, h  = image.size
            if w < 1000:
                scale = 1000 / w
                image = image.resize((int(w * scale), int(h * scale)), Image.LANCZOS)
            text = pytesseract.image_to_string(image, config="--psm 3")
            text = re.sub(r"\n{3,}", "\n\n", text).strip()
        except Exception as e:
            return Response({"detail": f"OCR failed: {e}"}, status=422)

        if len(text) < 50:
            return Response(
                {"detail": "Not enough text detected. Make sure the image is clear."},
                status=422,
            )

        title     = file.name or "Scanned notes"
        extracted = _truncate(text)
        result_id = _save_stub(request.user, "", title)

        return Response({
            "result_id":      result_id,
            "file_url":       "",
            "file_name":      title,
            "char_count":     len(extracted),
            "extracted_text": extracted,
            "source":         "ocr",
            "message":        "Text extracted from image! Call POST /process/ to generate study materials.",
        }, status=201)
