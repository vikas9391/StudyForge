"""
apps/analytics/views.py
Mirrors routers/analytics.py exactly — same endpoints, same response shapes.
"""

from collections import defaultdict
from datetime import datetime, timedelta, date

from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from django.utils import timezone
from django.db.models import Avg

from .models import QuizAttempt
from apps.results.models import Result


class RecordQuizAttemptView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        """POST /analytics/quiz-attempt/ — record a completed quiz attempt."""
        data = request.data

        # Enrich answers with topic_hint
        answers = []
        for a in data.get("answers", []):
            hint = a.get("topic_hint") or " ".join(a.get("question", "").split()[:4])
            answers.append({
                "question":       a.get("question", ""),
                "correct_answer": a.get("correct_answer", ""),
                "user_answer":    a.get("user_answer", ""),
                "is_correct":     a.get("is_correct", False),
                "topic_hint":     hint,
            })

        result_id = data.get("result_id")
        result    = None
        if result_id:
            result = Result.objects.filter(id=result_id, user=request.user).first()

        attempt = QuizAttempt.objects.create(
            user         = request.user,
            result       = result,
            session_name = data.get("session_name", ""),
            score        = int(data.get("score", 0)),
            total        = int(data.get("total", 0)),
            answers      = answers,
        )

        total = attempt.total
        pct   = round(attempt.score / total * 100) if total else 0
        return Response({"message": "Attempt recorded.", "score_pct": pct}, status=201)


class WeakTopicsView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, user_id):
        """GET /analytics/weak-topics/{user_id}/ — topics ranked by error rate."""
        if str(request.user.id) != str(user_id):
            from rest_framework.exceptions import PermissionDenied
            raise PermissionDenied()

        limit    = int(request.query_params.get("limit", 15))
        attempts = QuizAttempt.objects.filter(user=request.user)

        if not attempts.exists():
            return Response({"user_id": str(user_id), "topics": []})

        topic_stats: dict = defaultdict(lambda: {"correct": 0, "total": 0})
        for attempt in attempts:
            for ans in (attempt.answers or []):
                topic = ans.get("topic_hint") or " ".join(ans.get("question", "").split()[:4])
                topic_stats[topic]["total"] += 1
                if ans.get("is_correct"):
                    topic_stats[topic]["correct"] += 1

        topics = []
        for topic, stats in topic_stats.items():
            t = stats["total"]
            if not t:
                continue
            wrong = t - stats["correct"]
            topics.append({
                "topic":      topic,
                "total":      t,
                "correct":    stats["correct"],
                "wrong":      wrong,
                "error_rate": round(wrong / t, 3),
            })

        topics.sort(key=lambda x: x["error_rate"], reverse=True)
        return Response({"user_id": str(user_id), "topics": topics[:limit]})


class AccuracyOverTimeView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, user_id):
        """GET /analytics/accuracy/{user_id}/ — daily accuracy % for last N days."""
        if str(request.user.id) != str(user_id):
            from rest_framework.exceptions import PermissionDenied
            raise PermissionDenied()

        days  = int(request.query_params.get("days", 30))
        since = timezone.now() - timedelta(days=days)

        attempts = QuizAttempt.objects.filter(
            user=request.user, created_at__gte=since
        ).order_by("created_at")

        daily: dict = defaultdict(lambda: {"score": 0, "total": 0, "attempts": 0})
        for a in attempts:
            day = a.created_at.strftime("%Y-%m-%d")
            daily[day]["score"]    += a.score
            daily[day]["total"]    += a.total
            daily[day]["attempts"] += 1

        points = []
        for day in sorted(daily):
            d   = daily[day]
            pct = round(d["score"] / d["total"] * 100) if d["total"] else 0
            points.append({"date": day, "pct": pct, "attempts": d["attempts"]})

        return Response({"user_id": str(user_id), "days": days, "points": points})


class AnalyticsSummaryView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, user_id):
        """GET /analytics/summary/{user_id}/ — high-level stats dashboard."""
        if str(request.user.id) != str(user_id):
            from rest_framework.exceptions import PermissionDenied
            raise PermissionDenied()

        attempts = list(
            QuizAttempt.objects.filter(user=request.user)
            .order_by("-created_at")
            .values("score", "total", "created_at", "session_name")
        )

        if not attempts:
            return Response({
                "total_attempts": 0, "avg_accuracy": 0,
                "best_session": None, "study_streak": 0,
            })

        total    = len(attempts)
        avg_acc  = round(
            sum(r["score"] / r["total"] * 100 for r in attempts if r["total"]) / total
        )
        best     = max(attempts, key=lambda r: r["score"] / r["total"] if r["total"] else 0)

        # Study streak
        days_set = sorted(set(r["created_at"].strftime("%Y-%m-%d") for r in attempts), reverse=True)
        streak, prev = 0, None
        for day_str in days_set:
            day = datetime.strptime(day_str, "%Y-%m-%d").date()
            if prev is None:
                streak = 1
            elif (prev - day).days == 1:
                streak += 1
            else:
                break
            prev = day

        return Response({
            "total_attempts": total,
            "avg_accuracy":   avg_acc,
            "best_session": {
                "name":  best.get("session_name") or "Unnamed",
                "score": best["score"],
                "total": best["total"],
                "pct":   round(best["score"] / best["total"] * 100) if best["total"] else 0,
            },
            "study_streak": streak,
        })


class WeeklyStatsView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, user_id):
        """GET /analytics/weekly-stats/{user_id}/ — questions & flashcards delta vs last week."""
        if str(request.user.id) != str(user_id):
            from rest_framework.exceptions import PermissionDenied
            raise PermissionDenied()

        now        = timezone.now()
        week_start = (now - timedelta(days=now.weekday())).replace(
            hour=0, minute=0, second=0, microsecond=0)
        last_week  = week_start - timedelta(days=7)

        def _totals(since, until):
            rows = Result.objects.filter(
                user=request.user, created_at__gte=since, created_at__lt=until
            ).values("quiz", "flashcards")
            q = sum(len(r.get("quiz") or []) for r in rows)
            c = sum(len(r.get("flashcards") or []) for r in rows)
            return q, c

        this_q, this_c = _totals(week_start, now)
        prev_q, prev_c = _totals(last_week,  week_start)

        return Response({
            "user_id":              str(user_id),
            "questions_this_week":  this_q,
            "flashcards_this_week": this_c,
            "questions_delta":      this_q - prev_q,
            "flashcards_delta":     this_c - prev_c,
        })
