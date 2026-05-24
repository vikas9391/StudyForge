"""
apps/analytics/models.py
Replaces the Supabase 'quiz_attempts' table.
"""

import uuid
from django.db import models
from django.conf import settings
from apps.results.models import Result


class QuizAttempt(models.Model):
    id           = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user         = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
                                     related_name="quiz_attempts")
    result       = models.ForeignKey(Result, on_delete=models.CASCADE,
                                     related_name="quiz_attempts", null=True, blank=True)
    session_name = models.CharField(max_length=500, blank=True, default="")
    score        = models.IntegerField()
    total        = models.IntegerField()
    # answers: [{question, correct_answer, user_answer, is_correct, topic_hint}]
    answers      = models.JSONField(default=list)
    created_at   = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "quiz_attempts"
        ordering = ["-created_at"]
        indexes  = [models.Index(fields=["user", "-created_at"])]

    def __str__(self):
        return f"QuizAttempt({self.user_id} {self.score}/{self.total})"
