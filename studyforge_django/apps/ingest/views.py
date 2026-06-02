"""
apps/ingest/views.py
Mirrors routers/ingest.py — URL scraping, YouTube transcript, OCR.
All fixes applied:
  - URL format validation before any network call
  - Split httpx timeouts (connect vs read)
  - Distinct HTTP error / timeout exception handling
  - YouTube scheme check + better error matching
  - OCR: 20 MB limit, EXIF rotation, PSM auto-select, fallback retry
  - _save_stub guarded with try/except + title[:255]
"""

import re
import io
import urllib.parse
import os 

from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from rest_framework.parsers import MultiPartParser, FormParser

from apps.results.models import Result
# ADD these 3 lines after "from apps.results.models import Result"
import pytesseract
if os.name == 'nt':  # Windows local dev only
    pytesseract.pytesseract.tesseract_cmd = r'C:\Program Files\Tesseract-OCR\tesseract.exe'


MAX_CHARS = 15_000


def _truncate(text):
    return text[:MAX_CHARS] if len(text) > MAX_CHARS else text


def _save_stub(user, source_url, title):
    try:
        result = Result.objects.create(
            user       = user,
            file_url   = source_url,
            file_name  = title[:255],
            summary    = "__pending__",
            quiz       = [],
            flashcards = [],
        )
        return str(result.id)
    except Exception as e:
        raise ValueError(f"Could not create result record: {e}") from e


def _validate_url(url):
    """
    Returns (True, None) if url is a valid http/https URL.
    Returns (False, error_message) otherwise.
    """
    if not url:
        return False, "url is required."
    try:
        parsed = urllib.parse.urlparse(url)
        if parsed.scheme not in ("http", "https"):
            return False, "Invalid URL. Must start with http:// or https://"
        if not parsed.netloc:
            return False, "Invalid URL. No domain found."
    except Exception:
        return False, "Could not parse the provided URL."
    return True, None


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

        url = request.data.get("url", "").strip()

        # ── Validate URL format before any network call ───────────────────────
        valid, err = _validate_url(url)
        if not valid:
            return Response({"detail": err}, status=422)

        # ── Fetch page ────────────────────────────────────────────────────────
        try:
            resp = httpx.get(
                url,
                headers={"User-Agent": "Mozilla/5.0 (StudyForge/3.0)"},
                timeout=httpx.Timeout(connect=8.0, read=20.0, write=5.0, pool=5.0),
                follow_redirects=True,
            )
            resp.raise_for_status()
            html = resp.text

        except httpx.HTTPStatusError as e:
            return Response(
                {"detail": f"The page returned an error: HTTP {e.response.status_code}"},
                status=502,
            )
        except httpx.TimeoutException:
            return Response(
                {"detail": "The page took too long to respond. Try a different URL."},
                status=504,
            )
        except Exception as e:
            return Response({"detail": f"Could not fetch URL: {e}"}, status=502)

        # ── Parse & extract text ──────────────────────────────────────────────
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
            return Response(
                {"detail": "Could not extract readable content from this page."},
                status=422,
            )

        text = content.get_text(separator="\n", strip=True)
        text = re.sub(r"\n{3,}", "\n\n", text).strip()

        if len(text) < 100:
            return Response(
                {"detail": "Not enough text found on this page. Try a different URL."},
                status=422,
            )
        
        title = (soup.title.string or "").strip() if soup.title else url
        title = title or url 
        extracted = _truncate(text)

        try:
            result_id = _save_stub(request.user, url, title)
        except ValueError as e:
            return Response({"detail": str(e)}, status=500)

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
    """
    Extract 11-char YouTube video ID from any YouTube URL format.
    Returns None if no valid ID found.
    """
    # Must have a scheme to be a real URL
    if not url.startswith(("http://", "https://")):
        return None

    patterns = [
        r"(?:v=)([A-Za-z0-9_-]{11})",          # ?v=XXXXXXXXXXX
        r"(?:youtu\.be/)([A-Za-z0-9_-]{11})",   # youtu.be/XXXXXXXXXXX
        r"(?:embed/)([A-Za-z0-9_-]{11})",        # /embed/XXXXXXXXXXX
        r"(?:shorts/)([A-Za-z0-9_-]{11})",       # /shorts/XXXXXXXXXXX
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
        import httpx

        url = request.data.get("url", "").strip()

        # ── Validate URL format ───────────────────────────────────────────────
        valid, err = _validate_url(url)
        if not valid:
            return Response({"detail": err}, status=422)

        # ── Extract video ID ──────────────────────────────────────────────────
        video_id = _extract_video_id(url)
        if not video_id:
            return Response(
                {
                    "detail": (
                        "No YouTube video ID found. "
                        "Use a full link like https://youtube.com/watch?v=XXXXXXXXXXX "
                        "or https://youtu.be/XXXXXXXXXXX"
                    )
                },
                status=422,
            )

        # ── Fetch transcript (youtube-transcript-api v1.x) ────────────────────
        try:
            from youtube_transcript_api import YouTubeTranscriptApi

            ytt_api    = YouTubeTranscriptApi()
            transcript = ytt_api.fetch(
                video_id,
                languages=["en", "en-US", "en-GB", "a.en"],
            )
            transcript_list = [{"text": snippet.text} for snippet in transcript]

        except ImportError:
            return Response(
                {"detail": "youtube-transcript-api not installed."},
                status=500,
            )
        except Exception as exc:
            msg = str(exc).lower()
            if any(k in msg for k in (
                "disabled", "no transcript", "notranscript",
                "could not retrieve", "no captions", "not available",
                "no element found",
            )):
                return Response(
                    {"detail": "This video has no captions available."},
                    status=422,
                )
            return Response(
                {"detail": f"Transcript fetch failed: {exc}"},
                status=502,
            )

        # ── Build readable text from transcript snippets ───────────────────────
        chunks = []
        for i in range(0, len(transcript_list), 10):
            group = transcript_list[i:i + 10]
            chunks.append(
                " ".join(s["text"].replace("\n", " ") for s in group)
            )
        text = "\n\n".join(chunks).strip()

        if not text:
            return Response({"detail": "Transcript is empty."}, status=422)

        # ── Try to fetch the video title via oEmbed ───────────────────────────
        title = f"YouTube: {video_id}"
        try:
            meta = httpx.get(
                f"https://www.youtube.com/oembed"
                f"?url=https://youtu.be/{video_id}&format=json",
                timeout=httpx.Timeout(connect=5.0, read=8.0, write=3.0, pool=3.0),
            )
            if meta.status_code == 200:
                title = meta.json().get("title", title)
        except Exception:
            pass

        extracted = _truncate(text)

        try:
            result_id = _save_stub(request.user, url, title)
        except ValueError as e:
            return Response({"detail": str(e)}, status=500)

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

    _MAX_BYTES = 20 * 1024 * 1024   # 20 MB — modern phone photos are 8–15 MB

    def post(self, request):
        """POST /ingest/ocr/ — extract text from image using pytesseract."""
        try:
            import pytesseract
            from PIL import Image, ImageFilter, ImageOps
        except ImportError:
            return Response(
                {"detail": "pytesseract or Pillow not installed."},
                status=500,
            )

        file = request.FILES.get("file")
        if not file:
            return Response({"detail": "No file provided."}, status=400)

        # ── MIME type check ───────────────────────────────────────────────────
        allowed = {
            "image/jpeg", "image/jpg", "image/png",
            "image/webp", "image/bmp", "image/tiff",
        }
        ct = (file.content_type or "").lower().split(";")[0].strip()
        if ct not in allowed:
            return Response(
                {
                    "detail": (
                        f"Unsupported image type '{ct}'. "
                        "Use JPEG, PNG, WebP, BMP, or TIFF."
                    )
                },
                status=422,
            )

        # ── Size check ────────────────────────────────────────────────────────
        file_bytes = file.read()
        if len(file_bytes) > self._MAX_BYTES:
            mb = len(file_bytes) / (1024 * 1024)
            return Response(
                {"detail": f"Image is {mb:.1f} MB — max 20 MB."},
                status=413,
            )

        # ── Open & pre-process ────────────────────────────────────────────────
        try:
            image = Image.open(io.BytesIO(file_bytes))

            # Fix EXIF rotation — phone photos are often tagged portrait/landscape
            try:
                image = ImageOps.exif_transpose(image)
            except Exception:
                pass

            # Normalise colour mode (handles RGBA, palette, greyscale, etc.)
            if image.mode not in ("RGB", "L"):
                image = image.convert("RGB")

            w, h = image.size

            # ── Resolution normalisation ──────────────────────────────────────
            # Upscale if short side < 1200 px — too small hurts OCR accuracy.
            # Downscale if long side > 4800 px — protects tesseract from OOM.
            TARGET_SHORT = 1200
            MAX_LONG     = 4800

            short_side = min(w, h)
            long_side  = max(w, h)

            if short_side < TARGET_SHORT:
                scale = TARGET_SHORT / short_side
                image = image.resize(
                    (int(w * scale), int(h * scale)), Image.Resampling.LANCZOS
                )
                w, h = image.size

            if long_side > MAX_LONG:
                scale = MAX_LONG / long_side
                image = image.resize(
                    (int(w * scale), int(h * scale)), Image.Resampling.LANCZOS
                )

            # ── Greyscale + sharpen — improves OCR on photos of handwritten notes
            grey  = image.convert("L")
            sharp = grey.filter(ImageFilter.SHARPEN)

            # ── PSM selection based on aspect ratio ───────────────────────────
            # Portrait (phone photo of a page) → PSM 6 (assume uniform text block)
            # Landscape / square               → PSM 3 (fully automatic)
            aspect = w / h if h else 1
            psm    = "6" if aspect < 0.85 else "3"
            config = f"--psm {psm} --oem 3"

            text = pytesseract.image_to_string(sharp, config=config)
            text = re.sub(r"\n{3,}", "\n\n", text).strip()

            # ── Fallback: retry with PSM 4 if first pass returned little text ─
            if len(text) < 80:
                text_fb = pytesseract.image_to_string(
                    sharp, config="--psm 4 --oem 3"
                ).strip()
                if len(text_fb) > len(text):
                    text = re.sub(r"\n{3,}", "\n\n", text_fb).strip()

        except Exception as e:
            return Response({"detail": f"OCR failed: {e}"}, status=422)

        # ── Minimum text gate ─────────────────────────────────────────────────
        if len(text) < 50:
            return Response(
                {
                    "detail": (
                        "Not enough text detected. Tips: make sure the image is "
                        "in focus, well-lit, and text fills most of the frame."
                    )
                },
                status=422,
            )

        title     = file.name or "Scanned notes"
        extracted = _truncate(text)

        try:
            result_id = _save_stub(request.user, "", title)
        except ValueError as e:
            return Response({"detail": str(e)}, status=500)

        return Response({
            "result_id":      result_id,
            "file_url":       "",
            "file_name":      title,
            "char_count":     len(extracted),
            "extracted_text": extracted,
            "source":         "ocr",
            "message":        "Text extracted from image! Call POST /process/ to generate study materials.",
        }, status=201)