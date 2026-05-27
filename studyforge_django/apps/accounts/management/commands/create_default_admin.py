# apps/accounts/management/commands/create_default_admin.py

from django.core.management.base import BaseCommand
from django.contrib.auth import get_user_model

User = get_user_model()


class Command(BaseCommand):
    help = "Create a default admin user if one does not already exist."

    def handle(self, *args, **kwargs):
        email    = "admin@gmail.com"
        password = "admin123"

        if User.objects.filter(email=email).exists():
            self.stdout.write(
                self.style.WARNING(f"Admin user '{email}' already exists — skipping.")
            )
            return

        user = User.objects.create_superuser(
            email=email,
            password=password,
            username="admin",
        )
        user.is_staff     = True
        user.is_superuser = True
        user.is_active    = True
        user.save()

        self.stdout.write(
            self.style.SUCCESS(f"Admin user '{email}' created successfully.")
        )