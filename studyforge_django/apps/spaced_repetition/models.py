"""
apps/spaced_repetition/models.py
Replaces the Supabase 'sr_cards' table.
"""

import uuid
from django.db import models
from django.conf import settings
from apps.results.models import Result


class SRCard(models.Model):
    id          = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user        = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
                                    related_name="sr_cards")
    result      = models.ForeignKey(Result, on_delete=models.CASCADE,
                                    related_name="sr_cards")
    card_index  = models.IntegerField()
    front       = models.TextField()
    back        = models.TextField()

    # SM-2 fields
    easiness    = models.FloatField(default=2.5)
    interval    = models.IntegerField(default=1)
    repetitions = models.IntegerField(default=0)
    due_date    = models.DateField()
    last_quality= models.IntegerField(default=-1)

    created_at  = models.DateTimeField(auto_now_add=True)
    updated_at  = models.DateTimeField(auto_now=True)

    class Meta:
        db_table    = "sr_cards"
        unique_together = [("user", "result", "card_index")]
        indexes = [models.Index(fields=["user", "due_date"])]

    def __str__(self):
        return f"SRCard({self.user_id} #{self.card_index})"
