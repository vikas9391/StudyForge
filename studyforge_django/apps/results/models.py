"""
apps/results/models.py
Replaces the Supabase 'results' table — no RLS needed, Django querysets handle it.
"""

import uuid
from django.db import models
from django.conf import settings


class Result(models.Model):
    id         = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user       = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
                                   related_name="results")
    file_url   = models.URLField(blank=True, default="")
    file_name  = models.CharField(max_length=500, blank=True, default="")

    # Stored file (local or cloud)
    file       = models.FileField(upload_to="uploads/%Y/%m/", blank=True, null=True)

    summary    = models.TextField(blank=True, default="")
    quiz       = models.JSONField(default=list)
    flashcards = models.JSONField(default=list)

    # Shared-session fields (replaces Supabase ALTER TABLE)
    is_public   = models.BooleanField(default=False)
    clone_count = models.IntegerField(default=0)
    cloned_from = models.UUIDField(null=True, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    STATUS_PENDING    = "pending"
    STATUS_EXTRACTING = "extracting"
    STATUS_READY      = "ready"
    STATUS_FAILED     = "failed"
    
    status         = models.CharField(max_length=20, default="pending")
    extracted_text = models.TextField(blank=True, default="")
    error_message  = models.TextField(blank=True, default="")

    class Meta:
        db_table = "results"
        ordering = ["-created_at"]
        indexes  = [models.Index(fields=["user", "-created_at"])]

    def __str__(self):
        return f"Result({self.file_name or self.id})"
