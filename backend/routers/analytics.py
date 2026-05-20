"""
routers/analytics.py
Study analytics endpoints.

POST /analytics/quiz-attempt   — record a full quiz attempt with per-question results
GET  /analytics/weak-topics/{user_id} — heatmap of topics the user struggles with
GET  /analytics/accuracy/{user_id}    — accuracy over time (for line chart)
GET  /analytics/summary/{user_id}     — overall stats dashboard
"""

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
from typing import Optional
from datetime import datetime, timedelta
from collections import defaultdict

from utils.supabase_client import get_supabase

router = APIRouter()

# SQL to run in Supabase SQL Editor:
#
# create table if not exists quiz_attempts (
#   id          uuid primary key default gen_random_uuid(),
#   user_id     text not null,
#   result_id   text not null,
#   session_name text default '',
#   score       int  not null,
#   total       int  not null,
#   answers     jsonb default '[]',
#   -- answers: [{question, correct_answer, user_answer, is_correct, topic_hint}]
#   created_at  timestamptz default now()
# );
# alter table quiz_attempts enable row level security;
# create policy "Users manage own attempts"
#   on quiz_attempts for all
#   using (auth.uid()::text = user_id)
#   with check (auth.uid()::text = user_id);
# create index quiz_attempts_user_idx on quiz_attempts(user_id, created_at desc);


class QuizAnswer(BaseModel):
    question:       str
    correct_answer: str
    user_answer:    str
    is_correct:     bool
    topic_hint:     Optional[str] = ""   # first 4 words of question used as topic


class QuizAttemptRequest(BaseModel):
    user_id:      str
    result_id:    str
    session_name: str = ""
    score:        int
    total:        int
    answers:      list[QuizAnswer]


@router.post("/quiz-attempt")
def record_quiz_attempt(body: QuizAttemptRequest):
    """
    Record a completed quiz attempt.
    Called by Flutter after the user hits 'Submit Answers'.
    """
    sb = get_supabase()

    # Enrich answers with topic_hint if not supplied
    answers = []
    for a in body.answers:
        hint = a.topic_hint or " ".join(a.question.split()[:4])
        answers.append({
            "question":       a.question,
            "correct_answer": a.correct_answer,
            "user_answer":    a.user_answer,
            "is_correct":     a.is_correct,
            "topic_hint":     hint,
        })

    sb.table("quiz_attempts").insert({
        "user_id":      body.user_id,
        "result_id":    body.result_id,
        "session_name": body.session_name,
        "score":        body.score,
        "total":        body.total,
        "answers":      answers,
    }).execute()

    pct = round(body.score / body.total * 100) if body.total else 0
    return {"message": "Attempt recorded.", "score_pct": pct}


@router.get("/weak-topics/{user_id}")
def get_weak_topics(
    user_id: str,
    limit:   int = Query(default=15, ge=5, le=50),
):
    """
    Returns topics ranked by wrong-answer rate.
    Used by Flutter to render the heatmap.

    Each topic = first 4 words of the question (good enough for grouping).
    """
    sb = get_supabase()

    attempts = sb.table("quiz_attempts") \
        .select("answers") \
        .eq("user_id", user_id) \
        .execute()

    if not attempts.data:
        return {"user_id": user_id, "topics": []}

    # Aggregate by topic_hint
    topic_stats: dict[str, dict] = defaultdict(lambda: {"correct": 0, "total": 0})
    for row in attempts.data:
        for ans in (row.get("answers") or []):
            topic = ans.get("topic_hint") or " ".join(ans.get("question","").split()[:4])
            topic_stats[topic]["total"] += 1
            if ans.get("is_correct"):
                topic_stats[topic]["correct"] += 1

    # Compute error rate, sort worst first
    topics = []
    for topic, stats in topic_stats.items():
        total = stats["total"]
        if total == 0:
            continue
        wrong = total - stats["correct"]
        error_rate = wrong / total
        topics.append({
            "topic":      topic,
            "total":      total,
            "correct":    stats["correct"],
            "wrong":      wrong,
            "error_rate": round(error_rate, 3),
        })

    topics.sort(key=lambda x: x["error_rate"], reverse=True)

    return {
        "user_id": user_id,
        "topics":  topics[:limit],
    }


@router.get("/accuracy/{user_id}")
def get_accuracy_over_time(
    user_id: str,
    days:    int = Query(default=30, ge=7, le=90),
):
    """
    Quiz accuracy % per day for the last N days.
    Used by Flutter to draw the accuracy line chart.
    """
    sb = get_supabase()
    since = (datetime.utcnow() - timedelta(days=days)).isoformat()

    attempts = sb.table("quiz_attempts") \
        .select("score, total, created_at") \
        .eq("user_id", user_id) \
        .gte("created_at", since) \
        .order("created_at") \
        .execute()

    # Group by date
    daily: dict[str, dict] = defaultdict(lambda: {"score": 0, "total": 0, "attempts": 0})
    for row in (attempts.data or []):
        day = row["created_at"][:10]   # "YYYY-MM-DD"
        daily[day]["score"]    += row["score"]
        daily[day]["total"]    += row["total"]
        daily[day]["attempts"] += 1

    points = []
    for day in sorted(daily.keys()):
        d = daily[day]
        pct = round(d["score"] / d["total"] * 100) if d["total"] else 0
        points.append({
            "date":     day,
            "pct":      pct,
            "attempts": d["attempts"],
        })

    return {"user_id": user_id, "days": days, "points": points}


@router.get("/summary/{user_id}")
def get_analytics_summary(user_id: str):
    """
    High-level stats: total attempts, avg score, best session,
    total cards reviewed, study streak (consecutive days with activity).
    """
    sb = get_supabase()

    attempts = sb.table("quiz_attempts") \
        .select("score, total, created_at, session_name") \
        .eq("user_id", user_id) \
        .order("created_at", desc=True) \
        .execute()

    rows = attempts.data or []
    if not rows:
        return {
            "total_attempts": 0, "avg_accuracy": 0,
            "best_session": None, "study_streak": 0,
        }

    total = len(rows)
    avg_acc = round(
        sum(r["score"] / r["total"] * 100 for r in rows if r["total"]) / total
    )

    # Best session by accuracy
    best = max(rows, key=lambda r: r["score"] / r["total"] if r["total"] else 0)

    # Study streak: consecutive calendar days with at least one attempt
    days_with_activity = sorted(set(r["created_at"][:10] for r in rows), reverse=True)
    streak = 0
    prev = None
    for day_str in days_with_activity:
        day = datetime.strptime(day_str, "%Y-%m-%d").date()
        if prev is None:
            streak = 1
        elif (prev - day).days == 1:
            streak += 1
        else:
            break
        prev = day

    return {
        "total_attempts": total,
        "avg_accuracy":   avg_acc,
        "best_session": {
            "name":  best.get("session_name") or "Unnamed",
            "score": best["score"],
            "total": best["total"],
            "pct":   round(best["score"] / best["total"] * 100) if best["total"] else 0,
        },
        "study_streak": streak,
    }