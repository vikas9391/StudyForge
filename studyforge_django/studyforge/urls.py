"""
studyforge/urls.py
Root URL configuration — mirrors the FastAPI router prefixes exactly
so your Flutter app needs zero URL changes.
"""

from django.contrib import admin
from django.urls import path, include
from django.conf import settings
from django.conf.urls.static import static
from rest_framework_simplejwt.views import TokenRefreshView
from apps.accounts.views import GoogleSignInView
from apps.accounts.views import (
    SignupView, SigninView, SignoutView,
    ResetPasswordView, ResetPasswordConfirmView,
)

urlpatterns = [
    # Django admin UI
    path("django-admin/", admin.site.urls),

    # Auth
    path("auth/signup/",                 SignupView.as_view(),              name="signup"),
    path("auth/signin/",                 SigninView.as_view(),              name="signin"),
    path("auth/refresh/",                TokenRefreshView.as_view(),        name="token_refresh"),
    path("auth/signout/",                SignoutView.as_view(),             name="signout"),
    path("auth/reset-password/",         ResetPasswordView.as_view(),       name="reset_password"),
    path("auth/reset-password/confirm/", ResetPasswordConfirmView.as_view(),name="reset_password_confirm"),
    path("auth/google/", GoogleSignInView.as_view(), name="google_signin"),


    # Core features
    path("upload/",  include("apps.results.upload_urls")),
    path("process/", include("apps.results.process_urls")),
    path("results/", include("apps.results.urls")),
    path("retry/",   include("apps.results.retry_urls")),

    # Profile & Admin
    path("", include("apps.accounts.urls")),

    # V3 features
    path("analytics/",     include("apps.analytics.urls")),
    path("ingest/",        include("apps.ingest.urls")),
    path("shared/",        include("apps.shared.urls")),
    path("sr/",            include("apps.spaced_repetition.urls")),
    path("notifications/", include("apps.notifications.urls")),

    # Health check
    path("", include("apps.accounts.health_urls")),
]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)