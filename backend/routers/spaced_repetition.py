"""
routers/spaced_repetition.py
Spaced repetition system using the SM-2 algorithm.

Endpoints:
  POST /sr/review          — submit a card review (quality 0-5)
  GET  /sr/due/{user_id}   — get all cards due for review today
  GET  /sr/stats/{user_id} — retention stats across all cards
  POST /sr/init/{result_id}— initialise SR records for all flashcards in a session
"""

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime, date, timedelta
import math

from utils.supabase_client import get_supabase

router = APIRouter()


# ── SM-2 algorithm ────────────────────────────────────────────────────────────

def sm2(
    easiness: float,
    interval: int,
    repetitions: int,
    quality: int,           # 0–5: 5=perfect, 3=correct with difficulty, <3=fail
) -> tuple[float, int, int]:
    """
    Returns updated (easiness, interval_days, repetitions).
    quality: 5=perfect recall, 4=correct after hesitation, 3=correct with difficulty,
             2=incorrect but easy to recall, 1=incorrect, 0=complete blackout
    """
    if quality < 3:
        # Failed — reset
        repetitions = 0
        interval = 1
    else:
        if repetitions == 0:
            interval = 1
        elif repetitions == 1:
            interval = 6
        else:
            interval = math.ceil(interval * easiness)
        repetitions += 1

    # Update easiness factor (min 1.3)
    easiness = max(1.3, easiness + 0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02))

    return easiness, interval, repetitions


# ── Supabase helpers ──────────────────────────────────────────────────────────

def _ensure_sr_table_exists():
    """Reminder: run the SQL migration below in Supabase SQL Editor."""
    pass

# SQL to run in Supabase:
# create table if not exists sr_cards (
#   id           uuid primary key default gen_random_uuid(),
#   user_id      text not null,
#   result_id    text not null,
#   card_index   int  not null,
#   front        text not null,
#   back         text not null,
#   easiness     float default 2.5,
#   interval     int   default 1,
#   repetitions  int   default 0,
#   due_date     date  default current_date,
#   last_quality int   default -1,
#   created_at   timestamptz default now(),
#   updated_at   timestamptz default now(),
#   unique(user_id, result_id, card_index)
# );
# alter table sr_cards enable row level security;
# create policy "Users manage own sr_cards"
#   on sr_cards for all
#   using (auth.uid()::text = user_id)
#   with check (auth.uid()::text = user_id);


# ── Request / response models ─────────────────────────────────────────────────

class ReviewRequest(BaseModel):
    user_id:    str
    result_id:  str
    card_index: int
    quality:    int = Field(..., ge=0, le=5, description="SM-2 quality 0–5")


class InitRequest(BaseModel):
    user_id: str
    cards:   list[dict]  # [{front, back}, ...]


# ── Endpoints ─────────────────────────────────────────────────────────────────

@router.post("/init/{result_id}")
def init_sr_cards(result_id: str, body: InitRequest):
    """
    Create SR records for every flashcard in a session.
    Safe to call multiple times — uses upsert.
    """
    sb = get_supabase()
    rows = []
    for i, card in enumerate(body.cards):
        rows.append({
            "user_id":    body.user_id,
            "result_id":  result_id,
            "card_index": i,
            "front":      card.get("front", ""),
            "back":       card.get("back", ""),
            "easiness":   2.5,
            "interval":   1,
            "repetitions": 0,
            "due_date":   date.today().isoformat(),
            "last_quality": -1,
        })

    if not rows:
        return {"message": "No cards to initialise.", "count": 0}

    # Upsert — skip existing records
    result = sb.table("sr_cards").upsert(
        rows,
        on_conflict="user_id,result_id,card_index"
    ).execute()

    return {
        "message": f"Initialised {len(rows)} SR cards for session {result_id}.",
        "count": len(rows),
    }


@router.post("/review")
def submit_review(body: ReviewRequest):
    """
    Record a review and compute next due date using SM-2.
    """
    sb = get_supabase()

    # Fetch existing record
    row = sb.table("sr_cards") \
        .select("*") \
        .eq("user_id", body.user_id) \
        .eq("result_id", body.result_id) \
        .eq("card_index", body.card_index) \
        .execute()

    if not row.data:
        raise HTTPException(404, "SR card not found. Call POST /sr/init/{result_id} first.")

    card = row.data[0]
    easiness    = float(card["easiness"])
    interval    = int(card["interval"])
    repetitions = int(card["repetitions"])

    new_easiness, new_interval, new_repetitions = sm2(
        easiness, interval, repetitions, body.quality
    )

    next_due = (date.today() + timedelta(days=new_interval)).isoformat()

    sb.table("sr_cards").update({
        "easiness":     new_easiness,
        "interval":     new_interval,
        "repetitions":  new_repetitions,
        "due_date":     next_due,
        "last_quality": body.quality,
        "updated_at":   datetime.utcnow().isoformat(),
    }).eq("user_id", body.user_id) \
      .eq("result_id", body.result_id) \
      .eq("card_index", body.card_index) \
      .execute()

    return {
        "card_index":   body.card_index,
        "easiness":     round(new_easiness, 3),
        "interval":     new_interval,
        "repetitions":  new_repetitions,
        "next_due":     next_due,
        "message":      "Review recorded.",
    }


@router.get("/due/{user_id}")
def get_due_cards(user_id: str):
    """
    Return all SR cards due today or overdue.
    Groups cards by session (result_id) with session name from results table.
    """
    sb = get_supabase()
    today = date.today().isoformat()

    due = sb.table("sr_cards") \
        .select("*, results(file_name)") \
        .eq("user_id", user_id) \
        .lte("due_date", today) \
        .order("due_date") \
        .execute()

    cards = due.data or []

    # Group by result_id
    grouped: dict[str, dict] = {}
    for c in cards:
        rid = c["result_id"]
        if rid not in grouped:
            file_name = ""
            if c.get("results"):
                file_name = c["results"].get("file_name", "")
            grouped[rid] = {
                "result_id": rid,
                "session_name": file_name or f"Session {rid[:8]}",
                "cards": [],
            }
        grouped[rid]["cards"].append({
            "id":           c["id"],
            "card_index":   c["card_index"],
            "front":        c["front"],
            "back":         c["back"],
            "due_date":     c["due_date"],
            "interval":     c["interval"],
            "repetitions":  c["repetitions"],
            "last_quality": c["last_quality"],
        })

    return {
        "user_id":    user_id,
        "due_today":  len(cards),
        "sessions":   list(grouped.values()),
    }


@router.get("/stats/{user_id}")
def get_sr_stats(user_id: str):
    """
    Retention stats for the user's SR deck.
    Returns: total cards, mastered, learning, due today, avg easiness.
    """
    sb = get_supabase()
    today = date.today().isoformat()

    all_cards = sb.table("sr_cards") \
        .select("easiness, interval, repetitions, due_date, last_quality") \
        .eq("user_id", user_id) \
        .execute()

    cards = all_cards.data or []
    if not cards:
        return {
            "total": 0, "mastered": 0, "learning": 0,
            "due_today": 0, "avg_easiness": 0,
        }

    mastered   = sum(1 for c in cards if c["interval"] >= 21)
    learning   = sum(1 for c in cards if c["repetitions"] > 0 and c["interval"] < 21)
    due_today  = sum(1 for c in cards if c["due_date"] <= today)
    avg_ease   = sum(c["easiness"] for c in cards) / len(cards)

    return {
        "total":        len(cards),
        "mastered":     mastered,
        "learning":     learning,
        "new":          len(cards) - mastered - learning,
        "due_today":    due_today,
        "avg_easiness": round(avg_ease, 2),
    }