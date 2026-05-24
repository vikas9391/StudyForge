"""
apps/accounts/views.py
Auth (signup/signin/signout) + Profile + Admin endpoints.
Mirrors the FastAPI routers/auth.py and routers/profile.py exactly.
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
        """GET /profile/{user_id}/ — fetch profile."""
        user = get_object_or_404(User, id=user_id)
        profile, _ = Profile.objects.get_or_create(user=user)
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
    from rest_framework.exceptions import PermissionDenied
    profile = getattr(user, "profile", None)
    if not profile or not profile.is_admin:
        raise PermissionDenied("Admin access required.")


class AdminStatsView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        """GET /admin/stats/ — platform-wide stats."""
        _assert_admin(request.user)
        cutoff = timezone.now() - timedelta(hours=24)
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
        page  = int(request.query_params.get("page", 1))
        limit = int(request.query_params.get("limit", 20))
        offset = (page - 1) * limit

        profiles = Profile.objects.select_related("user").order_by("-created_at")[offset:offset + limit]
        users = []
        for p in profiles:
            users.append({
                "id":            str(p.user.id),
                "email":         p.user.email,
                "full_name":     p.full_name,
                "is_admin":      p.is_admin,
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
        user = get_object_or_404(User, id=target_user_id)
        profile, _ = Profile.objects.get_or_create(user=user)
        sessions = Result.objects.filter(user=user).order_by("-created_at") \
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
        user = get_object_or_404(User, id=target_user_id)
        profile, _ = Profile.objects.get_or_create(user=user)
        profile.is_admin = not profile.is_admin
        profile.save()
        action = "promoted to" if profile.is_admin else "removed from"
        return Response({
            "message":  f"User {action} admin.",
            "is_admin": profile.is_admin,
        })


class ResetPasswordView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        """POST /auth/reset-password/ — send password reset email."""
        from django.contrib.auth.forms import PasswordResetForm
        email = request.data.get("email", "").lower().strip()
        if not email:
            return Response({"detail": "Email is required."}, status=400)

        form = PasswordResetForm(data={"email": email})
        if form.is_valid():
            form.save(
                request=request,
                use_https=request.is_secure(),
                email_template_name="registration/password_reset_email.html",
            )
        # Always return 200 — don't reveal whether the email exists
        return Response({"message": "If that email exists, a reset link has been sent."})