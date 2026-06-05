"""
apps/results/views.py
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Self-contained — no external utils needed.
Inlines:
  • File extraction  (PDF via PyPDF2/pdfplumber/OCR, DOCX via python-docx)
  • AI generation    (summary, quiz, flashcards via HF Inference API)
  • File storage     (local media/ folder, Cloudinary when env vars present)

All original API paths and response shapes are preserved.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
"""

# ─────────────────────────────────────────────────────────────────────────────
# stdlib
# ─────────────────────────────────────────────────────────────────────────────
import io
import os
import re
import json
import uuid
import hashlib
import logging
from pathlib import Path

# ─────────────────────────────────────────────────────────────────────────────
# third-party
# ─────────────────────────────────────────────────────────────────────────────
import httpx
import pytesseract
if os.name == 'nt':  # Windows local dev only — Render uses /usr/bin/tesseract automatically
    pytesseract.pytesseract.tesseract_cmd = r'C:\Program Files\Tesseract-OCR\tesseract.exe'

# ─────────────────────────────────────────────────────────────────────────────
# Django / DRF
# ─────────────────────────────────────────────────────────────────────────────
from django.conf import settings
from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from rest_framework.parsers import MultiPartParser, FormParser

from .models import Result
from .serializers import ResultSerializer, ResultListSerializer

logger = logging.getLogger(__name__)

# ═════════════════════════════════════════════════════════════════════════════
# ① FILE EXTRACTION
# ═════════════════════════════════════════════════════════════════════════════

MAX_FILE_SIZE_MB  = 50    # raised from 10 MB
MAX_PAGES         = 50    # raised from 20 pages
MAX_EXTRACT_CHARS = 15_000  # cap sent to AI

ALLOWED_CONTENT_TYPES = {
    "application/pdf",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "application/msword",
}


def _is_low_quality_text(text: str) -> bool:
    """
    Returns True when the extracted text is likely garbage — e.g. only
    repeated author names / watermarks, not real document content.

    Heuristics used:
      • Fewer than 15 unique words  → almost certainly just header/footer text
      • Top-1 word accounts for >40% of all word tokens → heavily repetitive
      • Fewer than 3 sentences      → not enough content to study from
    """
    if not text or len(text.strip()) < 100:
        return True

    words = [w.lower() for w in text.split() if len(w) > 1]
    if not words:
        return True

    unique_words = set(words)
    if len(unique_words) < 15:
        return True

    from collections import Counter
    most_common_count = Counter(words).most_common(1)[0][1]
    if most_common_count / len(words) > 0.40:
        return True   # one word makes up >40% of the text — repetitive junk

    import re
    sentences = re.split(r'(?<=[.!?])\s+', text.strip())
    real_sentences = [s for s in sentences if len(s.split()) >= 5]
    if len(real_sentences) < 3:
        return True

    return False


def _extract_pdf(file_bytes: bytes) -> str:
    """
    Extract text from a PDF.

    Strategy (in order):
      1. PyPDF2  — fast, works for most text-layer PDFs
      2. pdfplumber — better for complex layouts / tables
      3. OCR via pdf2image + pytesseract — for image-only / carousel PDFs

    Quality is validated at each step; if the text looks like repetitive
    header/watermark garbage (_is_low_quality_text), we fall through to
    the next strategy instead of returning bad content.
    """

    # ── Attempt 1: PyPDF2 ────────────────────────────────────────────────────
    try:
        import PyPDF2
        reader        = PyPDF2.PdfReader(io.BytesIO(file_bytes))
        total_pages   = len(reader.pages)
        pages_to_read = min(total_pages, MAX_PAGES)
        parts = []
        for i in range(pages_to_read):
            t = reader.pages[i].extract_text()
            if t:
                parts.append(t)
        text = "\n\n".join(parts).strip()
        logger.info(f"PDF (PyPDF2): {pages_to_read}/{total_pages} pages, {len(text)} chars")
        if text and not _is_low_quality_text(text):
            return text
        logger.info("PDF (PyPDF2): text failed quality check, trying pdfplumber")
    except Exception as e:
        logger.warning(f"PyPDF2 failed: {e}")

    # ── Attempt 2: pdfplumber ────────────────────────────────────────────────
    try:
        import pdfplumber
        parts = []
        with pdfplumber.open(io.BytesIO(file_bytes)) as pdf:
            for i, page in enumerate(pdf.pages[:MAX_PAGES]):
                t = page.extract_text()
                if t:
                    parts.append(t)
        text = "\n\n".join(parts).strip()
        logger.info(f"PDF (pdfplumber): {len(text)} chars")
        if text and not _is_low_quality_text(text):
            return text
        logger.info("PDF (pdfplumber): text failed quality check, falling back to OCR")
    except Exception as e:
        logger.warning(f"pdfplumber failed: {e}")

    # ── Attempt 3: OCR (pdf2image + pytesseract) ─────────────────────────────
    # This handles image-only PDFs, carousel/slideshow PDFs, scanned docs, etc.
    logger.info("PDF: attempting OCR fallback via pdf2image + pytesseract")
    try:
        from pdf2image import convert_from_bytes
        from PIL import ImageFilter, ImageOps
        import pytesseract

        # Convert PDF pages to images (150 DPI is enough for OCR, keeps memory low)
        images = convert_from_bytes(
            file_bytes,
            dpi=150,
            first_page=1,
            last_page=min(MAX_PAGES, 20),  # cap at 20 pages for OCR
        )
        logger.info(f"PDF (OCR): converted {len(images)} pages to images")

        ocr_parts = []
        for page_num, image in enumerate(images, start=1):
            # Convert to RGB if needed
            if image.mode not in ("RGB", "L"):
                image = image.convert("RGB")

            # Fix EXIF rotation just in case
            try:
                image = ImageOps.exif_transpose(image)
            except Exception:
                pass

            # Greyscale + sharpen improves OCR accuracy
            grey  = image.convert("L")
            sharp = grey.filter(ImageFilter.SHARPEN)

            # Auto page segmentation mode — works well for mixed slide content
            config    = "--psm 3 --oem 3"
            page_text = pytesseract.image_to_string(sharp, config=config).strip()

            # Fallback per-page: retry with PSM 6 if PSM 3 returned little
            if len(page_text) < 50:
                page_text_fb = pytesseract.image_to_string(
                    sharp, config="--psm 6 --oem 3"
                ).strip()
                if len(page_text_fb) > len(page_text):
                    page_text = page_text_fb

            if page_text:
                ocr_parts.append(f"[Page {page_num}]\n{page_text}")
                logger.debug(f"  Page {page_num}: {len(page_text)} chars")

        ocr_text = "\n\n".join(ocr_parts).strip()
        # Clean up excessive blank lines from OCR output
        import re as _re
        ocr_text = _re.sub(r"\n{3,}", "\n\n", ocr_text)

        if ocr_text and not _is_low_quality_text(ocr_text):
            logger.info(f"PDF (OCR): extracted {len(ocr_text)} chars successfully")
            return ocr_text

        if ocr_text:
            # OCR got something but quality is marginal — return it with a warning prefix
            logger.warning("PDF (OCR): marginal quality, returning with warning")
            return (
                "[Note: This PDF appears to be image-based. "
                "OCR was used and accuracy may vary.]\n\n" + ocr_text
            )

    except ImportError as e:
        missing = str(e).split("'")[1] if "'" in str(e) else str(e)
        logger.warning(
            f"PDF OCR fallback skipped — '{missing}' not installed. "
            "Install pdf2image and pytesseract to enable OCR for image PDFs."
        )
    except Exception as e:
        logger.warning(f"PDF OCR fallback failed: {e}")

    raise ValueError(
        "No readable text could be extracted from this PDF. "
        "It may be a heavily image-based document. "
        "Try using the Scan (OCR) mode and photograph the key pages instead."
    )


def _extract_docx(file_bytes: bytes) -> str:
    """
    Extract from DOCX using python-docx.
    Includes table cells which are often skipped by naive extractors.
    """
    try:
        import docx as python_docx
        doc   = python_docx.Document(io.BytesIO(file_bytes))
        parts = []

        # Body paragraphs
        for para in doc.paragraphs:
            t = para.text.strip()
            if t:
                parts.append(t)

        # Table cells (contain definitions, key facts, etc.)
        for table in doc.tables:
            for row in table.rows:
                row_text = " | ".join(
                    cell.text.strip() for cell in row.cells if cell.text.strip()
                )
                if row_text:
                    parts.append(row_text)

        combined = "\n".join(parts)

        # Approximate page cap (~500 words per page)
        words = combined.split()
        if len(words) > MAX_PAGES * 500:
            combined = " ".join(words[: MAX_PAGES * 500])
            logger.info(f"DOCX: trimmed to ~{MAX_PAGES} pages")

        combined = combined.strip()
        if not combined:
            raise ValueError("No text found in the DOCX file.")
        logger.info(f"DOCX: {len(combined)} chars extracted")
        return combined

    except ValueError:
        raise
    except Exception as e:
        raise ValueError(f"Could not read DOCX: {e}")


def _extract_text(filename: str, file_bytes: bytes) -> str:
    """
    Dispatch to the correct extractor.
    Raises ValueError with a user-friendly message on any failure.
    """
    size_mb = len(file_bytes) / (1024 * 1024)
    if size_mb > MAX_FILE_SIZE_MB:
        raise ValueError(
            f"File is {size_mb:.1f} MB — maximum allowed is {MAX_FILE_SIZE_MB} MB."
        )

    ext = filename.lower().rsplit(".", 1)[-1]
    if ext == "pdf":
        return _extract_pdf(file_bytes)
    elif ext in ("doc", "docx"):
        return _extract_docx(file_bytes)
    else:
        raise ValueError(
            f"Unsupported file type '.{ext}'. Please upload a PDF or DOCX."
        )


# ═════════════════════════════════════════════════════════════════════════════
# ② FILE STORAGE
# ═════════════════════════════════════════════════════════════════════════════

def _save_file(file_bytes: bytes, filename: str, user_id: str) -> str:
    """
    Save file to Cloudinary (if env vars present) or local media/ folder.
    Returns a URL / relative path string.
    """
    cloud_name = os.getenv("CLOUDINARY_CLOUD_NAME", "")
    api_key    = os.getenv("CLOUDINARY_API_KEY", "")
    api_secret = os.getenv("CLOUDINARY_API_SECRET", "")

    if cloud_name and api_key and api_secret:
        return _save_cloudinary(file_bytes, filename, user_id,
                                cloud_name, api_key, api_secret)
    return _save_local(file_bytes, filename, user_id)


def _save_cloudinary(file_bytes, filename, user_id,
                     cloud_name, api_key, api_secret) -> str:
    try:
        import cloudinary
        import cloudinary.uploader
        cloudinary.config(
            cloud_name=cloud_name,
            api_key=api_key,
            api_secret=api_secret,
        )
        public_id = f"studyforge/{user_id}/{uuid.uuid4().hex}"
        result    = cloudinary.uploader.upload(
            file_bytes,
            public_id=public_id,
            resource_type="raw",
            use_filename=True,
            unique_filename=False,
        )
        return result.get("secure_url", "")
    except Exception as e:
        logger.warning(f"Cloudinary upload failed, falling back to local: {e}")
        return _save_local(file_bytes, filename, user_id)


def _save_local(file_bytes: bytes, filename: str, user_id: str) -> str:
    media_root = Path(getattr(settings, "MEDIA_ROOT", "media"))
    upload_dir = media_root / "uploads" / user_id
    upload_dir.mkdir(parents=True, exist_ok=True)

    # Prefix with a short hash to avoid collisions
    short_hash = hashlib.md5(file_bytes).hexdigest()[:8]
    safe_name  = re.sub(r"[^\w.\-]", "_", filename)
    dest       = upload_dir / f"{short_hash}_{safe_name}"
    dest.write_bytes(file_bytes)

    # Return a relative URL (served by Django's MEDIA_URL in dev)
    media_url = getattr(settings, "MEDIA_URL", "/media/")
    return f"{media_url}uploads/{user_id}/{short_hash}_{safe_name}"


# ═════════════════════════════════════════════════════════════════════════════
# ③ AI GENERATION  (Hugging Face Inference API)
# ═════════════════════════════════════════════════════════════════════════════

HF_API_TOKEN   = os.getenv("HF_API_TOKEN", "")
HF_BASE_URL    = "https://api-inference.huggingface.co/models"
SUMMARY_MODEL  = "facebook/bart-large-cnn"
INSTRUCT_MODEL = "mistralai/Mistral-7B-Instruct-v0.2"
_HF_HEADERS    = {"Authorization": f"Bearer {HF_API_TOKEN}"}
HF_TIMEOUT     = 90   # free tier cold-start can take 30-60 s


def _hf_post(model: str, payload: dict, retries: int = 2) -> dict:
    """
    POST to HF Inference API with automatic retry on 503 (model loading).
    Raises httpx.HTTPStatusError on non-retryable errors.
    """
    url = f"{HF_BASE_URL}/{model}"
    for attempt in range(retries + 1):
        try:
            resp = httpx.post(
                url,
                headers=_HF_HEADERS,
                json=payload,
                timeout=HF_TIMEOUT,
            )
            if resp.status_code == 503 and attempt < retries:
                # Model is loading — wait and retry
                import time
                wait = 20 * (attempt + 1)
                logger.info(f"HF model loading (503) — retrying in {wait}s")
                time.sleep(wait)
                continue
            resp.raise_for_status()
            return resp.json()
        except httpx.TimeoutException:
            if attempt < retries:
                logger.warning(f"HF timeout on attempt {attempt + 1}, retrying…")
                continue
            raise
    return {}


def _ai_truncate(text: str, max_chars: int = 3000) -> str:
    return text[:max_chars] if len(text) > max_chars else text


def _extract_json_array(raw: str) -> list | None:
    """
    Robustly extract a JSON array from messy LLM output.
    Tries multiple strategies before giving up.
    """
    if not raw:
        return None

    # Strategy 1 — find outermost [...] block
    match = re.search(r'\[.*\]', raw, re.DOTALL)
    if match:
        try:
            return json.loads(match.group())
        except json.JSONDecodeError:
            pass

    # Strategy 2 — fix common LLM JSON mistakes and retry
    cleaned = raw
    cleaned = re.sub(r',\s*([}\]])', r'\1', cleaned)   # trailing commas
    cleaned = re.sub(r'(?<!\\)"(\w+)":', r'"\1":', cleaned)  # unquoted keys
    match2 = re.search(r'\[.*\]', cleaned, re.DOTALL)
    if match2:
        try:
            return json.loads(match2.group())
        except json.JSONDecodeError:
            pass

    # Strategy 3 — extract individual {...} objects and wrap in array
    objects = re.findall(r'\{[^{}]+\}', raw, re.DOTALL)
    if objects:
        try:
            return [json.loads(o) for o in objects]
        except json.JSONDecodeError:
            pass

    return None


# ── Summary ──────────────────────────────────────────────────────────────────

def _generate_summary(text: str) -> str:
    """
    Generate a structured summary using BART-large-CNN.
    Falls back to first 3 sentences if API fails.
    """
    try:
        result = _hf_post(SUMMARY_MODEL, {
            "inputs": _ai_truncate(text, 3000),
            "parameters": {
                "max_length":     250,
                "min_length":     80,
                "do_sample":      False,
                "num_beams":      4,        # beam search → more coherent output
                "length_penalty": 1.2,
            },
        })
        if isinstance(result, list) and result:
            summary = result[0].get("summary_text", "").strip()
            if len(summary) >= 50:
                return summary
    except Exception as e:
        logger.warning(f"Summary API failed: {e}")

    # Fallback: first 3 non-trivial sentences
    sentences = re.split(r'(?<=[.!?])\s+', text.strip())
    useful    = [s for s in sentences if len(s.split()) >= 6]
    return " ".join(useful[:3]) if useful else text[:300]


# ── Quiz ─────────────────────────────────────────────────────────────────────

_QUIZ_PROMPT = """[INST]
You are an expert educator creating a multiple-choice quiz.

Instructions:
- Generate exactly {n} multiple-choice questions based ONLY on the text below.
- Each question must test understanding, not just memory.
- Each question must have exactly 4 options labeled A, B, C, D.
- Only ONE option must be correct.
- The correct answer must vary — don't always make A the answer.
- Distractors must be plausible but clearly wrong.
- Return ONLY a valid JSON array. No markdown, no explanation, no extra text.

Format:
[{{"question":"...","options":["A. ...","B. ...","C. ...","D. ..."],"answer":"B"}}]

TEXT:
{text}
[/INST]"""


def _generate_quiz(text: str, num_questions: int = 5) -> list[dict]:
    """
    Generate MCQs using Mistral-7B-Instruct.
    Returns list of {{ question, options, answer }}.
    """
    prompt = _QUIZ_PROMPT.format(
        n=num_questions,
        text=_ai_truncate(text, 2800),
    )
    try:
        result = _hf_post(INSTRUCT_MODEL, {
            "inputs": prompt,
            "parameters": {
                "max_new_tokens":     1400,
                "temperature":        0.25,   # lower = more deterministic
                "top_p":              0.9,
                "repetition_penalty": 1.1,
                "return_full_text":   False,
            },
        })
        raw = ""
        if isinstance(result, list) and result:
            raw = result[0].get("generated_text", "")
        elif isinstance(result, dict):
            raw = result.get("generated_text", "")

        parsed = _extract_json_array(raw)
        if parsed:
            validated = []
            for q in parsed[:num_questions]:
                if not all(k in q for k in ("question", "options", "answer")):
                    continue
                # Normalise answer to single uppercase letter
                ans = str(q["answer"]).strip().upper()[:1]
                if ans not in "ABCD":
                    ans = "A"
                # Ensure options list has exactly 4 items
                opts = q["options"]
                if len(opts) == 4:
                    validated.append({
                        "question": q["question"].strip(),
                        "options":  [o.strip() for o in opts],
                        "answer":   ans,
                    })
            if validated:
                logger.info(f"Quiz: generated {len(validated)} questions via AI")
                return validated

    except Exception as e:
        logger.warning(f"Quiz AI failed: {e}")

    logger.info("Quiz: using fallback generator")
    return _fallback_quiz(text, num_questions)


def _fallback_quiz(text: str, n: int) -> list[dict]:
    """
    Simple fallback: create fill-in-the-blank questions from sentences.
    """
    sentences = re.split(r'(?<=[.!?])\s+', text.strip())
    out       = []
    for sent in sentences:
        words = sent.split()
        if len(words) < 6:
            continue
        # Pick the most informative word (skip short words)
        candidates = [w for w in words[3:] if len(w) > 4]
        if not candidates:
            continue
        answer = candidates[0]
        blank  = sent.replace(answer, "___", 1)
        out.append({
            "question": blank,
            "options": [
                f"A. {answer}",
                f"B. {_pick_distractor(words, answer, 0)}",
                f"C. {_pick_distractor(words, answer, 1)}",
                "D. None of the above",
            ],
            "answer": "A",
        })
        if len(out) >= n:
            break

    return out or [{
        "question": "What is the main topic of this document?",
        "options":  ["A. As described", "B. Something else",
                     "C. Not mentioned", "D. None of the above"],
        "answer":   "A",
    }]


def _pick_distractor(words: list[str], exclude: str, idx: int) -> str:
    candidates = [w for w in words if len(w) > 3 and w != exclude]
    if idx < len(candidates):
        return candidates[idx]
    return ["Another option", "Different answer"][idx % 2]


# ── Flashcards ────────────────────────────────────────────────────────────────

_FLASH_PROMPT = """[INST]
You are an expert educator creating study flashcards.

Instructions:
- Generate exactly {n} flashcards based ONLY on the text below.
- Each flashcard must cover ONE key concept, term, or fact.
- Front: a concise term, concept name, or question (max 12 words).
- Back: a clear, complete definition or answer (1-3 sentences).
- Cover the most important concepts spread across the whole text.
- Do NOT repeat similar cards.
- Return ONLY a valid JSON array. No markdown, no explanation, no extra text.

Format:
[{{"front":"Key term or question","back":"Clear definition or answer."}}]

TEXT:
{text}
[/INST]"""


def _generate_flashcards(text: str, num_cards: int = 8) -> list[dict]:
    """
    Generate flashcards using Mistral-7B-Instruct.
    Returns list of {{ front, back }}.
    """
    prompt = _FLASH_PROMPT.format(
        n=num_cards,
        text=_ai_truncate(text, 2800),
    )
    try:
        result = _hf_post(INSTRUCT_MODEL, {
            "inputs": prompt,
            "parameters": {
                "max_new_tokens":     1200,
                "temperature":        0.3,
                "top_p":              0.9,
                "repetition_penalty": 1.1,
                "return_full_text":   False,
            },
        })
        raw = ""
        if isinstance(result, list) and result:
            raw = result[0].get("generated_text", "")
        elif isinstance(result, dict):
            raw = result.get("generated_text", "")

        parsed = _extract_json_array(raw)
        if parsed:
            validated = []
            for c in parsed[:num_cards]:
                if "front" not in c or "back" not in c:
                    continue
                front = str(c["front"]).strip()
                back  = str(c["back"]).strip()
                if front and back and len(back) >= 10:
                    validated.append({"front": front, "back": back})
            if validated:
                logger.info(f"Flashcards: generated {len(validated)} cards via AI")
                return validated

    except Exception as e:
        logger.warning(f"Flashcard AI failed: {e}")

    logger.info("Flashcards: using fallback generator")
    return _fallback_flashcards(text, num_cards)


def _fallback_flashcards(text: str, n: int) -> list[dict]:
    """
    Fallback: create term → definition pairs from sentences.
    """
    sentences = re.split(r'(?<=[.!?])\s+', text.strip())
    cards     = []
    for sent in sentences:
        words = sent.split()
        if len(words) < 6:
            continue
        front = " ".join(words[:5]) + "?"
        back  = sent.strip()
        cards.append({"front": front, "back": back})
        if len(cards) >= n:
            break
    return cards or [{"front": "Key concept", "back": text[:200]}]


# ═════════════════════════════════════════════════════════════════════════════
# ④ VIEWS
# ═════════════════════════════════════════════════════════════════════════════

# ── POST /upload/ ──────────────────────────────────────────────────────────────

class UploadView(APIView):
    permission_classes = [IsAuthenticated]
    parser_classes     = [MultiPartParser, FormParser]

    def post(self, request):
        """
        Step 1 of 2 — upload file, extract text, save pending stub.
        Returns result_id + extracted_text (pass both to POST /process/).
        """
        file = request.FILES.get("file")
        if not file:
            return Response({"detail": "No file provided."}, status=400)

        # ── MIME type check ───────────────────────────────────────────────────
        if file.content_type not in ALLOWED_CONTENT_TYPES:
            return Response(
                {"detail": "Unsupported file type. Upload a PDF or DOCX."},
                status=400,
            )

        # ── Size check (early, before reading full bytes) ─────────────────────
        file_bytes = file.read()
        size_mb    = len(file_bytes) / (1024 * 1024)
        if size_mb > MAX_FILE_SIZE_MB:
            return Response(
                {"detail": f"File is {size_mb:.1f} MB — max is {MAX_FILE_SIZE_MB} MB."},
                status=413,
            )

        # ── Extract text ──────────────────────────────────────────────────────
        try:
            extracted_text = _extract_text(file.name, file_bytes)
        except ValueError as e:
            return Response({"detail": str(e)}, status=422)

        # ── Save file ─────────────────────────────────────────────────────────
        try:
            file_url = _save_file(file_bytes, file.name, str(request.user.id))
        except Exception as e:
            logger.error(f"File save failed: {e}")
            file_url = ""  # non-fatal — processing can still continue

        # ── Save pending result stub ──────────────────────────────────────────
        try:
            result = Result.objects.create(
                user       = request.user,
                file_url   = file_url,
                file_name  = file.name[:255],
                summary    = "__pending__",
                quiz       = [],
                flashcards = [],
            )
        except Exception as e:
            return Response(
                {"detail": f"Could not save result: {e}"},
                status=500,
            )

        return Response({
            "result_id":      str(result.id),
            "file_url":       file_url,
            "char_count":     len(extracted_text),
            "extracted_text": extracted_text,
            "message":        "Uploaded! Call POST /process/ to generate study materials.",
        }, status=status.HTTP_201_CREATED)


# ── POST /process/ ─────────────────────────────────────────────────────────────

class ProcessView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        """
        Step 2 of 2 — generate AI study materials, update the result row.
        Each generator (summary / quiz / flashcards) is isolated so a failure
        in one doesn't block the others.
        """
        result_id      = request.data.get("result_id")
        extracted_text = request.data.get("extracted_text", "").strip()
        num_quiz       = max(5, min(10, int(request.data.get("num_quiz", 5))))
        num_cards      = max(4, min(15, int(request.data.get("num_flashcards", 8))))

        if not extracted_text:
            return Response(
                {"detail": "extracted_text cannot be empty."},
                status=400,
            )

        result = get_object_or_404(Result, id=result_id, user=request.user)

        # ── Truncate text sent to AI ──────────────────────────────────────────
        ai_text = extracted_text[:MAX_EXTRACT_CHARS]

        errors     = []
        summary    = "__pending__"
        quiz       = []
        flashcards = []

        # ── Summary ───────────────────────────────────────────────────────────
        try:
            summary = _generate_summary(ai_text)
        except Exception as e:
            summary = (
                "Summary generation failed. "
                "Here is the beginning of your document:\n\n"
                + ai_text[:500]
            )
            errors.append(f"summary: {e}")
            logger.error(f"Summary generation error for result {result_id}: {e}")

        # ── Quiz ──────────────────────────────────────────────────────────────
        try:
            quiz = _generate_quiz(ai_text, num_questions=num_quiz)
        except Exception as e:
            quiz = _fallback_quiz(ai_text, num_quiz)
            errors.append(f"quiz: {e}")
            logger.error(f"Quiz generation error for result {result_id}: {e}")

        # ── Flashcards ────────────────────────────────────────────────────────
        try:
            flashcards = _generate_flashcards(ai_text, num_cards=num_cards)
        except Exception as e:
            flashcards = _fallback_flashcards(ai_text, num_cards)
            errors.append(f"flashcards: {e}")
            logger.error(f"Flashcard generation error for result {result_id}: {e}")

        # ── Persist ───────────────────────────────────────────────────────────
        result.summary    = summary
        result.quiz       = quiz
        result.flashcards = flashcards
        result.save()

        resp = {
            "result_id":  str(result.id),
            "summary":    summary,
            "quiz":       quiz,
            "flashcards": flashcards,
            "message":    "Processing complete ✅",
        }
        if errors:
            resp["warnings"] = errors

        return Response(resp)


# ── GET/DELETE/PATCH /results/ ─────────────────────────────────────────────────

class ResultListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        """GET /results/?user_id= — last 20 results for authenticated user."""
        results = Result.objects.filter(user=request.user).order_by("-created_at")[:20]
        return Response({
            "user_id": str(request.user.id),
            "count":   results.count(),
            "results": ResultListSerializer(results, many=True).data,
        })


class ResultDetailView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, result_id):
        """GET /results/{id}/ — fetch one result."""
        result = get_object_or_404(Result, id=result_id, user=request.user)
        return Response(ResultSerializer(result).data)

    def delete(self, request, result_id):
        """DELETE /results/{id}/ — delete a session."""
        result = get_object_or_404(Result, id=result_id, user=request.user)
        result.delete()
        return Response({"message": f"Result '{result_id}' deleted."})

    def patch(self, request, result_id):
        """PATCH /results/{id}/ — rename a session."""
        name = (request.data.get("file_name") or "").strip()
        if not name:
            return Response(
                {"detail": "file_name must not be empty."},
                status=422,
            )
        if len(name) > 200:
            return Response(
                {"detail": "file_name must be 200 characters or fewer."},
                status=422,
            )
        result           = get_object_or_404(Result, id=result_id, user=request.user)
        result.file_name = name
        result.save()
        return Response({
            "result_id": str(result.id),
            "file_name": name,
            "message":   "Session renamed successfully.",
        })


# ── POST /retry/{id}/ ──────────────────────────────────────────────────────────

class RetryView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, result_id):
        """
        Re-download the stored file and re-extract text so the client
        can call POST /process/ again without re-uploading.
        """
        result   = get_object_or_404(Result, id=result_id, user=request.user)
        file_url = request.data.get("file_url") or result.file_url

        if not file_url:
            return Response(
                {"detail": "No file_url stored. Please upload the document again."},
                status=422,
            )

        # ── Download stored file ──────────────────────────────────────────────
        try:
            resp = httpx.get(
                file_url,
                timeout=httpx.Timeout(connect=10.0, read=60.0, write=5.0, pool=5.0),
                follow_redirects=True,
            )
            resp.raise_for_status()
            file_bytes = resp.content
        except httpx.HTTPStatusError as e:
            return Response(
                {"detail": f"Stored file returned HTTP {e.response.status_code}."},
                status=502,
            )
        except httpx.TimeoutException:
            return Response(
                {"detail": "Timed out downloading the stored file."},
                status=504,
            )
        except Exception as e:
            return Response(
                {"detail": f"Could not download stored file: {e}"},
                status=502,
            )

        # ── Re-extract text ───────────────────────────────────────────────────
        file_name = result.file_name or file_url.split("/")[-1]
        try:
            extracted_text = _extract_text(file_name, file_bytes)
        except ValueError as e:
            return Response({"detail": str(e)}, status=422)

        # Reset to pending so the client knows to call /process/ again
        result.summary    = "__pending__"
        result.quiz       = []
        result.flashcards = []
        result.save()

        return Response({
            "result_id":      str(result.id),
            "extracted_text": extracted_text,
            "char_count":     len(extracted_text),
            "message":        "Text extracted. Call POST /process/ to regenerate.",
        })