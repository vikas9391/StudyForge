"""
routers/process.py
POST /process — run AI generation, update Supabase DB row.
"""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from utils.ai_generator import generate_summary, generate_quiz, generate_flashcards
from utils.supabase_helpers import update_result

router = APIRouter()


class ProcessRequest(BaseModel):
    result_id:      str   # Returned by POST /upload
    extracted_text: str   # Returned by POST /upload
    user_id:        str   # Supabase user UID
    num_quiz:       int = 5    # 5–10 questions
    num_flashcards: int = 8    # 4–15 flashcards


@router.post("/")
async def process_document(req: ProcessRequest):
    """
    Step 2 of 2 — generate study materials with AI.
    Calls Hugging Face free models, updates the Firestore row,
    and returns the full generated content.
    """
    if not req.extracted_text.strip():
        raise HTTPException(400, "extracted_text cannot be empty.")

    num_quiz  = max(5,  min(10, req.num_quiz))
    num_cards = max(4,  min(15, req.num_flashcards))
    errors    = []

    # Generate all three outputs (continue even if one fails)
    try:
        summary = generate_summary(req.extracted_text)
    except Exception as e:
        summary = "Summary generation failed. Please retry."
        errors.append(f"summary: {e}")

    try:
        quiz = generate_quiz(req.extracted_text, num_questions=num_quiz)
    except Exception as e:
        quiz = []
        errors.append(f"quiz: {e}")

    try:
        flashcards = generate_flashcards(req.extracted_text, num_cards=num_cards)
    except Exception as e:
        flashcards = []
        errors.append(f"flashcards: {e}")

    # Persist results to Supabase
    try:
        update_result(req.result_id, summary, quiz, flashcards)
    except Exception as e:
        raise HTTPException(500, f"Database update failed: {e}")

    response = {
        "result_id":  req.result_id,
        "summary":    summary,
        "quiz":       quiz,
        "flashcards": flashcards,
        "message":    "Processing complete ✅",
    }
    if errors:
        response["warnings"] = errors   # Non-fatal partial failures
    return response
