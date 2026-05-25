import uuid
from django.db import models
from django.conf import settings


class Notification(models.Model):
    TYPE_CHOICES = [
        ('ready',   'Ready'),
        ('review',  'Review'),
        ('streak',  'Streak'),
        ('insight', 'Insight'),
        ('general', 'General'),
    ]

    id         = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user       = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE,
                                   related_name='notifications')
    type       = models.CharField(max_length=20, choices=TYPE_CHOICES, default='general')
    title      = models.CharField(max_length=255, default='')
    body       = models.TextField(default='')
    is_read    = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'notifications'
        ordering = ['-created_at']

    def __str__(self):
        return f'Notification({self.user_id} type={self.type} read={self.is_read})'