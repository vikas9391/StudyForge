"""
apps/accounts/views.py
Auth (signup/signin/signout) + Profile + Admin endpoints.
Mirrors the FastAPI routers/auth.py and routers/profile.py exactly.

CHANGES:
  - ProfileView.get: auto-syncs is_staff/is_superuser → Profile.is_admin on get_or_create
  - _assert_admin: falls back to user.is_staff / user.is_superuser if profile missing
"""

from rest_framework import status
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated, AllowAny
from rest_framework_simplejwt.tokens import RefreshToken
from django.contrib.auth import authenticate
from django.shortcuts import get_object_or_404
from django.utils import timezone
from datetime import timedelta

from .models import User, Profile
from .serializers import SignupSerializer, ProfileSerializer, ProfileUpdateSerializer
from apps.results.models import Result
from google.oauth2 import id_token
from google.auth.transport import requests as google_requests
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import AllowAny
from rest_framework_simplejwt.tokens import RefreshToken
from django.contrib.auth import get_user_model
from django.conf import settings

User = get_user_model()

class GoogleSignInView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        token = request.data.get('id_token')
        if not token:
            return Response({'detail': 'id_token required.'}, status=400)

        try:
            info = id_token.verify_oauth2_token(
                token,
                google_requests.Request(),
                audience=settings.GOOGLE_CLIENT_ID,
            )
        except Exception as e:
            return Response({'detail': f'Invalid Google token: {e}'}, status=400)

        email = info.get('email')
        if not email:
            return Response({'detail': 'Email not in token.'}, status=400)

        # Get or create user silently
        user, created = User.objects.get_or_create(
            email=email,
            defaults={
                'username':  email.split('@')[0],
                'is_active': True,
            }
        )

        # Issue your app's JWT tokens
        refresh = RefreshToken.for_user(user)
        return Response({
            'access_token':  str(refresh.access_token),
            'refresh_token': str(refresh),
            'user_id':       user.id,
            'email':         user.email,
        })


# ── Auth ───────────────────────────────────────────────────────────────────────

class SignupView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        """POST /auth/signup/ — create account, return tokens."""
        ser = SignupSerializer(data=request.data)
        ser.is_valid(raise_exception=True)
        user = ser.save()

        refresh = RefreshToken.for_user(user)
        return Response({
            "message":       "Account created successfully!",
            "user_id":       str(user.id),
            "email":         user.email,
            "access_token":  str(refresh.access_token),
            "refresh_token": str(refresh),
        }, status=status.HTTP_201_CREATED)


class SigninView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        """POST /auth/signin/ — sign in, return JWT tokens."""
        email    = request.data.get("email", "").lower()
        password = request.data.get("password", "")

        user = authenticate(request, username=email, password=password)
        if user is None:
            return Response({"detail": "Invalid email or password."},
                            status=status.HTTP_401_UNAUTHORIZED)

        refresh = RefreshToken.for_user(user)
        return Response({
            "access_token":  str(refresh.access_token),
            "refresh_token": str(refresh),
            "user_id":       str(user.id),
            "email":         user.email,
        })


class SignoutView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        """POST /auth/signout/ — blacklist refresh token (client deletes access token)."""
        try:
            token = RefreshToken(request.data.get("refresh_token", ""))
            token.blacklist()
        except Exception:
            pass  # Token may already be expired — that's fine
        return Response({"message": "Signed out successfully."})


# ── Health check ───────────────────────────────────────────────────────────────

class HealthView(APIView):
    permission_classes = [AllowAny]

    def get(self, request):
        return Response({"status": "ok", "message": "Studyforge API (Django) is running 🚀"})


# ── Profile ────────────────────────────────────────────────────────────────────

class ProfileView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, user_id):
        """GET /profile/{user_id}/ — fetch profile.

        Also syncs Django's is_staff / is_superuser → Profile.is_admin
        so that superusers created via createsuperuser automatically get
        admin access without needing a manual DB patch.
        """
        user = get_object_or_404(User, id=user_id)
        profile, _ = Profile.objects.get_or_create(user=user)

        # ── Auto-sync Django superuser/staff → Profile.is_admin ──────────────
        if (user.is_staff or user.is_superuser) and not profile.is_admin:
            profile.is_admin = True
            profile.save(update_fields=["is_admin"])

        return Response(ProfileSerializer(profile).data)

    def put(self, request, user_id):
        """PUT /profile/{user_id}/ — update profile (own only)."""
        if str(request.user.id) != str(user_id):
            return Response({"detail": "You can only update your own profile."},
                            status=status.HTTP_403_FORBIDDEN)

        profile, _ = Profile.objects.get_or_create(user=request.user)
        ser = ProfileUpdateSerializer(profile, data=request.data, partial=True)
        ser.is_valid(raise_exception=True)
        ser.save()
        return Response({"message": "Profile updated.", "data": ProfileSerializer(profile).data})


class StudyHistoryView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, user_id):
        """GET /profile/{user_id}/history/ — study session history."""
        if str(request.user.id) != str(user_id):
            return Response({"detail": "You can only view your own history."},
                            status=status.HTTP_403_FORBIDDEN)

        sessions = Result.objects.filter(user=request.user).order_by("-created_at") \
                         .values("id", "file_url", "summary", "created_at")
        return Response({
            "user_id":  str(request.user.id),
            "count":    len(sessions),
            "sessions": list(sessions),
        })


# ── Admin ──────────────────────────────────────────────────────────────────────

def _assert_admin(user):
    """Raise PermissionDenied if the user is not an admin.

    Falls back to Django's own is_staff / is_superuser flags so that
    superusers created via createsuperuser always have access even before
    their Profile row has been synced.
    """
    from rest_framework.exceptions import PermissionDenied
    profile  = getattr(user, "profile", None)
    is_admin = (profile and profile.is_admin) or user.is_staff or user.is_superuser
    if not is_admin:
        raise PermissionDenied("Admin access required.")


class AdminStatsView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        """GET /admin/stats/ — platform-wide stats."""
        _assert_admin(request.user)
        cutoff       = timezone.now() - timedelta(hours=24)
        recent_users = Profile.objects.order_by("-created_at")[:5]

        return Response({
            "total_users":    User.objects.count(),
            "total_sessions": Result.objects.count(),
            "sessions_today": Result.objects.filter(created_at__gte=cutoff).count(),
            "recent_signups": [
                {
                    "id":         str(p.user.id),
                    "email":      p.user.email,
                    "full_name":  p.full_name,
                    "created_at": p.created_at.isoformat(),
                }
                for p in recent_users
            ],
        })


class AdminUsersView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        """GET /admin/users/ — paginated user list."""
        _assert_admin(request.user)
        page   = int(request.query_params.get("page", 1))
        limit  = int(request.query_params.get("limit", 20))
        offset = (page - 1) * limit

        profiles = Profile.objects.select_related("user").order_by("-created_at")[offset:offset + limit]
        users = []
        for p in profiles:
            users.append({
                "id":            str(p.user.id),
                "email":         p.user.email,
                "full_name":     p.full_name,
                "is_admin":      p.is_admin or p.user.is_staff or p.user.is_superuser,
                "session_count": Result.objects.filter(user=p.user).count(),
                "created_at":    p.created_at.isoformat(),
            })

        return Response({
            "page":  page,
            "limit": limit,
            "total": Profile.objects.count(),
            "users": users,
        })


class AdminUserDetailView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, target_user_id):
        """GET /admin/users/{id}/ — full profile + sessions."""
        _assert_admin(request.user)
        user            = get_object_or_404(User, id=target_user_id)
        profile, _      = Profile.objects.get_or_create(user=user)
        sessions        = Result.objects.filter(user=user).order_by("-created_at") \
                                .values("id", "file_url", "summary", "created_at")
        return Response({
            "profile":  ProfileSerializer(profile).data,
            "sessions": list(sessions),
        })


class AdminDeleteResultView(APIView):
    permission_classes = [IsAuthenticated]

    def delete(self, request, result_id):
        """DELETE /admin/results/{id}/ — hard delete any session."""
        _assert_admin(request.user)
        result = get_object_or_404(Result, id=result_id)
        result.delete()
        return Response({"message": f"Result '{result_id}' deleted."})


class AdminToggleAdminView(APIView):
    permission_classes = [IsAuthenticated]

    def put(self, request, target_user_id):
        """PUT /admin/users/{id}/toggle-admin/ — promote/demote admin."""
        _assert_admin(request.user)
        user            = get_object_or_404(User, id=target_user_id)
        profile, _      = Profile.objects.get_or_create(user=user)
        profile.is_admin = not profile.is_admin
        profile.save()
        action = "promoted to" if profile.is_admin else "removed from"
        return Response({
            "message":  f"User {action} admin.",
            "is_admin": profile.is_admin,
        })


# ── Password Reset ─────────────────────────────────────────────────────────────

class ResetPasswordView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        """POST /auth/reset-password/ — send password reset email."""
        from django.contrib.auth.tokens import default_token_generator
        from django.utils.http import urlsafe_base64_encode
        from django.utils.encoding import force_bytes
        from django.core.mail import send_mail
        from django.template.loader import render_to_string

        email = request.data.get("email", "").lower().strip()
        if not email:
            return Response({"detail": "Email is required."}, status=400)

        try:
            user = User.objects.get(email=email)
            uid   = urlsafe_base64_encode(force_bytes(user.pk))
            token = default_token_generator.make_token(user)

            # Build the reset link — opens your Django confirm endpoint
            scheme   = "https" if request.is_secure() else "http"
            host     = request.get_host()
            reset_url = f"studyforge://reset-password?uid={uid}&token={token}"

            html_message = render_to_string("accounts/password_reset_email.html", {
                "user":      user,
                "reset_url": reset_url,
                "site_name": "Studyforge",
            })

            send_mail(
                subject="Reset your Studyforge password",
                message=f"Open this link to reset your password: {reset_url}",
                from_email=None,   # uses DEFAULT_FROM_EMAIL from settings
                recipient_list=[user.email],
                html_message=html_message,
                fail_silently=False,
            )
        except User.DoesNotExist:
            pass  # Don't reveal whether the email exists

        return Response({"message": "If that email exists, a reset link has been sent."})

class ResetPasswordConfirmView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        """POST /auth/reset-password/confirm/ — verify token and set new password."""
        from django.contrib.auth.tokens import default_token_generator
        from django.utils.http import urlsafe_base64_decode
        from django.utils.encoding import force_str

        uid      = request.data.get("uid", "")
        token    = request.data.get("token", "")
        password = request.data.get("password", "")

        if not uid or not token or not password:
            return Response(
                {"detail": "uid, token, and password are required."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if len(password) < 8:
            return Response(
                {"detail": "Password must be at least 8 characters."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        try:
            pk   = force_str(urlsafe_base64_decode(uid))
            user = User.objects.get(pk=pk)
        except (User.DoesNotExist, ValueError, TypeError):
            return Response(
                {"detail": "Invalid reset link."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if not default_token_generator.check_token(user, token):
            return Response(
                {"detail": "Reset link is invalid or has expired."},
                status=status.HTTP_400_BAD_REQUEST,
            )
        user.set_password(password)
        user.save()
        return Response({"message": "Password reset successfully. You can now sign in."})