"""
apps/spaced_repetition/views.py
Mirrors routers/spaced_repetition.py — SM-2 algorithm unchanged.
"""

import math
from datetime import date, timedelta

from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from django.shortcuts import get_object_or_404
from django.utils import timezone

from .models import SRCard
from apps.results.models import Result


# ── SM-2 algorithm (identical to FastAPI version) ─────────────────────────────

def sm2(easiness, interval, repetitions, quality):
    if quality < 3:
        repetitions = 0
        interval    = 1
    else:
        if repetitions == 0:
            interval = 1
        elif repetitions == 1:
            interval = 6
        else:
            interval = math.ceil(interval * easiness)
        repetitions += 1

    easiness = max(1.3, easiness + 0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02))
    return easiness, interval, repetitions


# ── Views ──────────────────────────────────────────────────────────────────────

class InitSRCardsView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, result_id):
        """POST /sr/init/{result_id}/ — create/upsert SR records for all flashcards."""
        result = get_object_or_404(Result, id=result_id, user=request.user)
        cards  = request.data.get("cards", [])

        if not cards:
            return Response({"message": "No cards to initialise.", "count": 0})

        today = date.today()
        created = 0
        for i, card in enumerate(cards):
            _, was_created = SRCard.objects.get_or_create(
                user       = request.user,
                result     = result,
                card_index = i,
                defaults   = {
                    "front":        card.get("front", ""),
                    "back":         card.get("back", ""),
                    "easiness":     2.5,
                    "interval":     1,
                    "repetitions":  0,
                    "due_date":     today,
                    "last_quality": -1,
                },
            )
            if was_created:
                created += 1

        return Response({
            "message": f"Initialised {len(cards)} SR cards for session {result_id}.",
            "count":   len(cards),
        }, status=201)


class ReviewView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        """POST /sr/review/ — record a review, compute next due date via SM-2."""
        user_id    = str(request.user.id)
        result_id  = request.data.get("result_id")
        card_index = int(request.data.get("card_index", 0))
        quality    = int(request.data.get("quality", 0))

        if quality < 0 or quality > 5:
            return Response({"detail": "quality must be 0–5."}, status=422)

        card = get_object_or_404(
            SRCard,
            user       = request.user,
            result__id = result_id,
            card_index = card_index,
        )

        new_ease, new_int, new_rep = sm2(
            card.easiness, card.interval, card.repetitions, quality
        )

        card.easiness     = new_ease
        card.interval     = new_int
        card.repetitions  = new_rep
        card.due_date     = date.today() + timedelta(days=new_int)
        card.last_quality = quality
        card.save()

        return Response({
            "card_index":  card_index,
            "easiness":    round(new_ease, 3),
            "interval":    new_int,
            "repetitions": new_rep,
            "next_due":    card.due_date.isoformat(),
            "message":     "Review recorded.",
        })


class DueCardsView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, user_id):
        """GET /sr/due/{user_id}/ — all cards due today or overdue, grouped by session."""
        if str(request.user.id) != str(user_id):
            from rest_framework.exceptions import PermissionDenied
            raise PermissionDenied()

        today = date.today()
        cards = SRCard.objects.filter(
            user=request.user, due_date__lte=today
        ).select_related("result").order_by("due_date")

        grouped = {}
        for c in cards:
            rid = str(c.result_id)
            if rid not in grouped:
                grouped[rid] = {
                    "result_id":    rid,
                    "session_name": c.result.file_name or f"Session {rid[:8]}",
                    "cards":        [],
                }
            grouped[rid]["cards"].append({
                "id":           str(c.id),
                "card_index":   c.card_index,
                "front":        c.front,
                "back":         c.back,
                "due_date":     c.due_date.isoformat(),
                "interval":     c.interval,
                "repetitions":  c.repetitions,
                "last_quality": c.last_quality,
            })

        return Response({
            "user_id":   str(user_id),
            "due_today": cards.count(),
            "sessions":  list(grouped.values()),
        })


class SRStatsView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, user_id):
        """GET /sr/stats/{user_id}/ — retention stats for user's SR deck."""
        if str(request.user.id) != str(user_id):
            from rest_framework.exceptions import PermissionDenied
            raise PermissionDenied()

        cards = list(
            SRCard.objects.filter(user=request.user)
            .values("easiness", "interval", "repetitions", "due_date", "last_quality")
        )

        if not cards:
            return Response({"total": 0, "mastered": 0, "learning": 0,
                             "due_today": 0, "avg_easiness": 0})

        today    = date.today().isoformat()
        mastered = sum(1 for c in cards if c["interval"] >= 21)
        learning = sum(1 for c in cards if c["repetitions"] > 0 and c["interval"] < 21)
        due_today= sum(1 for c in cards if str(c["due_date"]) <= today)
        avg_ease = sum(c["easiness"] for c in cards) / len(cards)

        return Response({
            "total":        len(cards),
            "mastered":     mastered,
            "learning":     learning,
            "new":          len(cards) - mastered - learning,
            "due_today":    due_today,
            "avg_easiness": round(avg_ease, 2),
        })
