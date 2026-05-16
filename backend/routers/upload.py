"""
routers/upload.py
POST /upload — validate file, upload to Supabase Storage,
               extract text, save stub row in Supabase DB.
"""

from fastapi import APIRouter, File, UploadFile, Form, HTTPException
from utils.file_extractor import extract_text, MAX_FILE_SIZE_MB
from utils.supabase_helpers import upload_file_to_storage, save_result

router = APIRouter()

ALLOWED_CONTENT_TYPES = {
    "application/pdf",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "application/msword",
}


@router.post("/")
async def upload_file(
    file:    UploadFile = File(..., description="PDF or DOCX file"),
    user_id: str        = Form(..., description="Supabase user UID"),
):
    """
    Step 1 of 2 — upload and extract.
    Returns result_id + extracted_text (pass both to POST /process).
    """
    # Validate content type
    if file.content_type not in ALLOWED_CONTENT_TYPES:
        raise HTTPException(
            400,
            f"Unsupported file type '{file.content_type}'. Upload a PDF or DOCX.",
        )

    file_bytes = await file.read()

    # Size check (also enforced in extractor)
    size_mb = len(file_bytes) / (1024 * 1024)
    if size_mb > MAX_FILE_SIZE_MB:
        raise HTTPException(
            413,
            f"File is {size_mb:.1f} MB — maximum is {MAX_FILE_SIZE_MB} MB.",
        )

    # Extract text from the file
    try:
        extracted_text = extract_text(file.filename or "upload", file_bytes)
    except ValueError as e:
        raise HTTPException(422, str(e))

    # Upload raw file to Supabase Storage
    try:
        file_url = upload_file_to_storage(
            file_bytes, file.filename or "upload", user_id
        )
    except Exception as e:
        raise HTTPException(500, f"Storage upload failed: {e}")

    # Save stub record to DB (summary/quiz/flashcards filled by /process)
    try:
        result_id = save_result(
            user_id=user_id,
            file_url=file_url,
            summary="__pending__",
            quiz=[],
            flashcards=[],
        )
    except Exception as e:
        raise HTTPException(500, f"Database save failed: {e}")

    return {
        "result_id":      result_id,
        "file_url":       file_url,
        "char_count":     len(extracted_text),
        "extracted_text": extracted_text,
        "message":        "Uploaded! Call POST /process to generate study materials.",
    }
