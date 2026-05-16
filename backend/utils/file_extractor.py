"""
utils/file_extractor.py
Extracts plain text from PDF and DOCX files.
Caps extraction at MAX_PAGES pages to stay within free-tier limits.
"""

import io
import PyPDF2
import docx

MAX_PAGES       = 20    # Only read first 20 pages
MAX_FILE_SIZE_MB = 10   # Reject files larger than 10 MB


def extract_text_from_pdf(file_bytes: bytes) -> str:
    """Extract text from a PDF (bytes). Returns joined string."""
    text_parts = []
    try:
        reader = PyPDF2.PdfReader(io.BytesIO(file_bytes))
        pages_to_read = min(len(reader.pages), MAX_PAGES)
        for i in range(pages_to_read):
            page_text = reader.pages[i].extract_text()
            if page_text:
                text_parts.append(page_text)
        print(f"📄 PDF: read {pages_to_read}/{len(reader.pages)} pages")
    except Exception as e:
        raise ValueError(f"Could not read PDF: {e}")

    full = "\n\n".join(text_parts).strip()
    if not full:
        raise ValueError(
            "No text extracted from PDF. "
            "The file may be scanned/image-based — use a text-based PDF."
        )
    return full


def extract_text_from_docx(file_bytes: bytes) -> str:
    """Extract text from a DOCX (bytes). Returns joined string."""
    try:
        doc = docx.Document(io.BytesIO(file_bytes))
        paragraphs = [p.text for p in doc.paragraphs if p.text.strip()]
        combined   = "\n".join(paragraphs)

        # Approximate page limit: ~500 words per page
        words_limit = MAX_PAGES * 500
        words = combined.split()
        if len(words) > words_limit:
            combined = " ".join(words[:words_limit])
            print(f"📄 DOCX: trimmed to ~{MAX_PAGES} pages")
    except Exception as e:
        raise ValueError(f"Could not read DOCX: {e}")

    if not combined.strip():
        raise ValueError("No text extracted from the DOCX file.")
    return combined.strip()


def extract_text(filename: str, file_bytes: bytes) -> str:
    """
    Dispatch to the correct extractor based on file extension.
    Raises ValueError for unsupported types or oversized files.
    """
    size_mb = len(file_bytes) / (1024 * 1024)
    if size_mb > MAX_FILE_SIZE_MB:
        raise ValueError(
            f"File is {size_mb:.1f} MB — maximum allowed is {MAX_FILE_SIZE_MB} MB."
        )

    ext = filename.lower().rsplit(".", 1)[-1]
    if ext == "pdf":
        return extract_text_from_pdf(file_bytes)
    elif ext in ("doc", "docx"):
        return extract_text_from_docx(file_bytes)
    else:
        raise ValueError(
            f"Unsupported file type '.{ext}'. Please upload a PDF or DOCX."
        )
