"""
utils/supabase_helpers.py
Wrappers around Supabase Storage and Database (PostgreSQL via PostgREST).

Run this SQL once in Supabase SQL Editor before starting the backend:

    create table results (
        id          uuid primary key default gen_random_uuid(),
        user_id     text not null,
        file_url    text,
        summary     text,
        quiz        jsonb default '[]',
        flashcards  jsonb default '[]',
        created_at  timestamptz default now()
    );

    alter table results enable row level security;

    create policy "Users manage own results"
        on results for all
        using  (auth.uid()::text = user_id)
        with check (auth.uid()::text = user_id);

Storage bucket "studyforge-files" must also be created as Public in
Supabase Dashboard → Storage → New bucket.
"""

import uuid
import mimetypes
from utils.supabase_client import get_supabase

BUCKET = "studyforge-files"


# ── Storage ───────────────────────────────────────────────────────────────────

def upload_file_to_storage(file_bytes: bytes, filename: str, user_id: str) -> str:
    """
    Upload a file to Supabase Storage.
    Returns the public URL.
    """
    sb = get_supabase()

    # Unique path so filenames never clash
    unique_name = f"{user_id}/{uuid.uuid4().hex}_{filename}"
    mime_type, _ = mimetypes.guess_type(filename)
    mime_type = mime_type or "application/octet-stream"

    sb.storage.from_(BUCKET).upload(
        path=unique_name,
        file=file_bytes,
        file_options={"content-type": mime_type, "upsert": "true"},
    )

    public_url = sb.storage.from_(BUCKET).get_public_url(unique_name)
    print(f"✅ Uploaded: {unique_name}")
    return public_url


# ── Database ──────────────────────────────────────────────────────────────────

def save_result(
    user_id: str,
    file_url: str,
    file_name: str,
    summary: str,
    quiz: list,
    flashcards: list,
) -> str:
    """Insert a new result row. Returns the generated UUID."""
    sb = get_supabase()
    res = sb.table("results").insert({
        "user_id":    user_id,
        "file_url":   file_url,
        "file_name":  file_name,
        "summary":    summary,
        "quiz":       quiz,
        "flashcards": flashcards,
    }).execute()
    row_id = res.data[0]["id"]
    print(f"✅ Saved result: {row_id}")
    return row_id


def update_result(
    result_id: str,
    summary: str,
    quiz: list,
    flashcards: list,
) -> None:
    """Update summary/quiz/flashcards for an existing row."""
    sb = get_supabase()
    sb.table("results").update({
        "summary":    summary,
        "quiz":       quiz,
        "flashcards": flashcards,
    }).eq("id", result_id).execute()
    print(f"✅ Updated result: {result_id}")


def get_result(result_id: str) -> dict | None:
    """Fetch one result row by ID. Returns None if not found."""
    sb = get_supabase()
    res = (
        sb.table("results")
        .select("*")
        .eq("id", result_id)
        .maybe_single()
        .execute()
    )
    return res.data


def get_results_by_user(user_id: str, limit: int = 20) -> list[dict]:
    """Return the most recent results for a user."""
    sb = get_supabase()
    res = (
        sb.table("results")
        .select("*")
        .eq("user_id", user_id)
        .order("created_at", desc=True)
        .limit(limit)
        .execute()
    )
    return res.data or []
