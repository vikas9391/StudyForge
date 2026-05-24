"""
apps/accounts/models.py
Custom User model + Profile — replaces Supabase Auth and profiles table.
"""

from django.contrib.auth.models import AbstractUser
from django.db import models
from django.db.models.signals import post_save
from django.dispatch import receiver


class User(AbstractUser):
    """
    Custom user model — email is used as the username for login.
    AbstractUser already has: id, email, password, date_joined, is_active, etc.
    """
    email = models.EmailField(unique=True)
    USERNAME_FIELD = "email"
    REQUIRED_FIELDS = ["username"]

    class Meta:
        db_table = "auth_user"

    def __str__(self):
        return self.email


class Profile(models.Model):
    """
    Extended profile data — replaces the Supabase profiles table.
    Auto-created when a User is created (via post_save signal).
    """
    user       = models.OneToOneField(User, on_delete=models.CASCADE, related_name="profile")
    full_name  = models.CharField(max_length=200, blank=True, default="")
    phone      = models.CharField(max_length=50, blank=True, default="")
    bio        = models.TextField(blank=True, default="")
    avatar_url = models.URLField(blank=True, default="")
    is_admin   = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = "profiles"

    def __str__(self):
        return f"Profile({self.user.email})"


# Auto-create profile on user creation (replaces Supabase trigger)
@receiver(post_save, sender=User)
def create_user_profile(sender, instance, created, **kwargs):
    if created:
        Profile.objects.get_or_create(user=instance)
