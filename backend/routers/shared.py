"""
routers/shared.py
Shared / public study sessions.

PATCH /shared/{result_id}/visibility  — toggle public/private
GET   /shared/browse                  — list public sessions (paginated + search)
GET   /shared/{result_id}             — view any public session
POST  /shared/{result_id}/clone       — copy a public session to your own library
GET   /shared/featured                — top 10 most-cloned sessions
"""

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
from typing import Optional

from utils.supabase_client import get_supabase

router = APIRouter()

# SQL migration — run in Supabase SQL Editor:
#
# alter table results add column if not exists is_public   boolean default false;
# alter table results add column if not exists clone_count int     default 0;
# alter table results add column if not exists cloned_from text    default null;
#
# -- Let anyone read public results
# create policy "Anyone reads public results"
#   on results for select
#   using (is_public = true);


# ── Models ────────────────────────────────────────────────────────────────────

class VisibilityRequest(BaseModel):
    is_public: bool


class CloneRequest(BaseModel):
    user_id: str


# ── Endpoints ─────────────────────────────────────────────────────────────────

@router.patch("/{result_id}/visibility")
def set_visibility(result_id: str, body: VisibilityRequest):
    """Make a session public (discoverable by others) or private."""
    sb = get_supabase()

    existing = sb.table("results").select("id").eq("id", result_id).execute()
    if not existing.data:
        raise HTTPException(404, "Session not found.")

    sb.table("results").update({"is_public": body.is_public}) \
        .eq("id", result_id).execute()

    status = "public" if body.is_public else "private"
    return {"result_id": result_id, "is_public": body.is_public,
            "message": f"Session is now {status}."}


@router.get("/browse")
def browse_public_sessions(
    search: Optional[str] = Query(default=None, max_length=100),
    limit:  int           = Query(default=20, ge=1, le=50),
    offset: int           = Query(default=0,  ge=0),
):
    """
    Browse public study sessions. Optionally filter by keyword in file_name.
    Results ordered by clone_count desc (most popular first).
    """
    sb = get_supabase()

    query = sb.table("results") \
        .select("id, file_name, summary, quiz, flashcards, created_at, clone_count") \
        .eq("is_public", True) \
        .order("clone_count", desc=True) \
        .range(offset, offset + limit - 1)

    if search:
        # Supabase ilike filter
        query = query.ilike("file_name", f"%{search}%")

    result = query.execute()
    sessions = result.data or []

    # Strip full quiz/flashcard content from list view — return counts only
    lite = []
    for s in sessions:
        lite.append({
            "id":           s["id"],
            "file_name":    s.get("file_name") or "Untitled",
            "summary":      (s.get("summary") or "")[:200],   # snippet only
            "quiz_count":   len(s.get("quiz") or []),
            "card_count":   len(s.get("flashcards") or []),
            "clone_count":  s.get("clone_count") or 0,
            "created_at":   s.get("created_at"),
        })

    return {
        "sessions": lite,
        "count":    len(lite),
        "offset":   offset,
        "limit":    limit,
    }


@router.get("/featured")
def get_featured_sessions():
    """Top 10 most-cloned public sessions — used for the 'Featured' shelf."""
    sb = get_supabase()

    result = sb.table("results") \
        .select("id, file_name, summary, quiz, flashcards, clone_count") \
        .eq("is_public", True) \
        .order("clone_count", desc=True) \
        .limit(10) \
        .execute()

    sessions = []
    for s in (result.data or []):
        sessions.append({
            "id":          s["id"],
            "file_name":   s.get("file_name") or "Untitled",
            "summary":     (s.get("summary") or "")[:120],
            "quiz_count":  len(s.get("quiz") or []),
            "card_count":  len(s.get("flashcards") or []),
            "clone_count": s.get("clone_count") or 0,
        })

    return {"sessions": sessions}


@router.get("/{result_id}")
def get_public_session(result_id: str):
    """
    Fetch full content of a public session.
    Returns 403 if the session is private.
    """
    sb = get_supabase()

    row = sb.table("results") \
        .select("*") \
        .eq("id", result_id) \
        .execute()

    if not row.data:
        raise HTTPException(404, "Session not found.")

    s = row.data[0]
    if not s.get("is_public"):
        raise HTTPException(403, "This session is private.")

    return {
        "id":          s["id"],
        "file_name":   s.get("file_name") or "Untitled",
        "summary":     s.get("summary") or "",
        "quiz":        s.get("quiz") or [],
        "flashcards":  s.get("flashcards") or [],
        "clone_count": s.get("clone_count") or 0,
        "created_at":  s.get("created_at"),
        "cloned_from": s.get("cloned_from"),
    }


@router.post("/{result_id}/clone")
def clone_session(result_id: str, body: CloneRequest):
    """
    Copy a public session into the requesting user's own library.
    Increments clone_count on the original.
    """
    sb = get_supabase()

    # Fetch the original
    row = sb.table("results") \
        .select("*") \
        .eq("id", result_id) \
        .execute()

    if not row.data:
        raise HTTPException(404, "Session not found.")

    original = row.data[0]
    if not original.get("is_public"):
        raise HTTPException(403, "This session is private and cannot be cloned.")

    # Insert a private copy for the requesting user
    new_row = sb.table("results").insert({
        "user_id":     body.user_id,
        "file_url":    original.get("file_url") or "",
        "file_name":   f"{original.get('file_name') or 'Untitled'} (copy)",
        "summary":     original.get("summary") or "",
        "quiz":        original.get("quiz") or [],
        "flashcards":  original.get("flashcards") or [],
        "is_public":   False,
        "clone_count": 0,
        "cloned_from": result_id,
    }).execute()

    if not new_row.data:
        raise HTTPException(500, "Clone failed — please try again.")

    new_id = new_row.data[0]["id"]

    # Bump clone_count on the original
    current_count = original.get("clone_count") or 0
    sb.table("results").update({"clone_count": current_count + 1}) \
        .eq("id", result_id).execute()

    return {
        "new_result_id": new_id,
        "cloned_from":   result_id,
        "message":       "Session cloned to your library!",
    }