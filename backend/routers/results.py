"""
routers/results.py
GET    /results/{result_id}  — fetch one saved result
GET    /results/?user_id=    — fetch all results for a user (last 20)
DELETE /results/{result_id}  — delete a result by ID
PATCH  /results/{result_id}  — ✅ NEW: rename a session (file_name only)
POST   /retry/{result_id}    — ✅ NEW: re-extract text from stored file for retry
"""

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
from typing import Optional

from utils.supabase_helpers import get_result, get_results_by_user
from utils.supabase_client import get_supabase
from utils.file_extractor import extract_text

import httpx  # for downloading the file from Supabase Storage on retry

router = APIRouter()


# ── Request models ────────────────────────────────────────────────────────────

class RenameRequest(BaseModel):
    file_name: str


class RetryRequest(BaseModel):
    user_id:  str
    file_url: str


# ── Existing endpoints ────────────────────────────────────────────────────────

@router.get("/")
def fetch_user_results(
    user_id: str = Query(..., description="Supabase user UID")
):
    """Return the 20 most recent results for the given user."""
    results = get_results_by_user(user_id)
    return {"user_id": user_id, "count": len(results), "results": results}


@router.get("/{result_id}")
def fetch_result(result_id: str):
    """Retrieve a specific study-material result by its UUID."""
    data = get_result(result_id)
    if data is None:
        raise HTTPException(404, f"No result found with ID '{result_id}'.")
    return {"result_id": result_id, **data}


@router.delete("/{result_id}")
def delete_result(result_id: str):
    """Delete a study session by its UUID."""
    sb = get_supabase()
    sb.table("results").delete().eq("id", result_id).execute()
    return {"message": f"Result '{result_id}' deleted."}


# ── ✅ NEW: Rename endpoint ───────────────────────────────────────────────────

@router.patch("/{result_id}")
def rename_result(result_id: str, body: RenameRequest):
    """
    Update the display name of an existing session.

    Only file_name is updated — no other fields are touched.
    Returns the updated record so the client can sync state.
    """
    name = body.file_name.strip()
    if not name:
        raise HTTPException(422, "file_name must not be empty.")
    if len(name) > 200:
        raise HTTPException(422, "file_name must be 200 characters or fewer.")

    sb = get_supabase()

    # Verify the result exists first
    existing = sb.table("results").select("id").eq("id", result_id).execute()
    if not existing.data:
        raise HTTPException(404, f"No result found with ID '{result_id}'.")

    updated = (
        sb.table("results")
        .update({"file_name": name})
        .eq("id", result_id)
        .execute()
    )

    if not updated.data:
        raise HTTPException(500, "Rename failed — please try again.")

    return {
        "result_id": result_id,
        "file_name": name,
        "message":   "Session renamed successfully.",
    }


# ── ✅ NEW: Retry endpoint ────────────────────────────────────────────────────

@router.post("/retry/{result_id}")
async def retry_result(result_id: str, body: RetryRequest):
    """
    Re-extract text from the already-uploaded file so the client can
    call POST /process again without a full re-upload.

    Flow:
      1. Download the file from the stored file_url (Supabase Storage).
      2. Extract text using the same extractor as /upload.
      3. Return extracted_text — the client then calls POST /process.

    The result row is NOT modified here; /process will update it.
    """
    sb = get_supabase()

    # Verify the session exists and belongs to the requesting user
    row = (
        sb.table("results")
        .select("id, user_id, file_url, file_name")
        .eq("id", result_id)
        .execute()
    )
    if not row.data:
        raise HTTPException(404, f"No result found with ID '{result_id}'.")

    record   = row.data[0]
    file_url = body.file_url or record.get("file_url", "")

    if not file_url:
        raise HTTPException(
            422,
            "No file_url stored for this session. "
            "Please upload the document again.",
        )

    # Download the file from storage
    try:
        async with httpx.AsyncClient(timeout=30) as client:
            resp = await client.get(file_url)
            resp.raise_for_status()
            file_bytes = resp.content
    except httpx.HTTPError as e:
        raise HTTPException(
            502,
            f"Could not download the stored file: {e}. "
            "The file may have been deleted from storage.",
        )

    # Re-extract text
    file_name = record.get("file_name") or file_url.split("/")[-1]
    try:
        extracted_text = extract_text(file_name, file_bytes)
    except ValueError as e:
        raise HTTPException(422, str(e))

    # Mark the session as pending so the UI shows a spinner while /process runs
    sb.table("results").update({
        "summary":    "__pending__",
        "quiz":       [],
        "flashcards": [],
    }).eq("id", result_id).execute()

    return {
        "result_id":      result_id,
        "extracted_text": extracted_text,
        "char_count":     len(extracted_text),
        "message":        "Text extracted. Call POST /process to regenerate.",
    }