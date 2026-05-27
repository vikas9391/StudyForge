"""
studyforge/settings.py
Django settings for Studyforge — replaces Supabase with PostgreSQL + JWT auth.
"""

from pathlib import Path
from datetime import timedelta
from decouple import config
import dj_database_url

BASE_DIR = Path(__file__).resolve().parent.parent

# ── Security ───────────────────────────────────────────────────────────────────
SECRET_KEY    = config("SECRET_KEY", default="django-insecure-change-me")
DEBUG         = config("DEBUG", default=True, cast=bool)
ALLOWED_HOSTS = config("ALLOWED_HOSTS", default="*", cast=lambda v: v.split(","))

# ── Apps ───────────────────────────────────────────────────────────────────────
INSTALLED_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    # Third party
    "rest_framework",
    "rest_framework_simplejwt",
    "corsheaders",
    "anymail",
    # Our apps
    "apps.accounts",
    "apps.results",
    "apps.analytics",
    "apps.ingest",
    "apps.shared",
    "apps.spaced_repetition",
    "apps.notifications",
]

# ── Middleware ─────────────────────────────────────────────────────────────────
MIDDLEWARE = [
    "corsheaders.middleware.CorsMiddleware",
    "django.middleware.security.SecurityMiddleware",
    "whitenoise.middleware.WhiteNoiseMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "studyforge.urls"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.debug",
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

WSGI_APPLICATION = "studyforge.wsgi.application"

# ── Database ───────────────────────────────────────────────────────────────────
DATABASES = {
    "default": dj_database_url.parse(
        str(config("DATABASE_URL", cast=str)),
        conn_max_age=600,
        conn_health_checks=True,
    )
}

# ── Custom User Model ──────────────────────────────────────────────────────────
AUTH_USER_MODEL = "accounts.User"

# ── Django REST Framework ──────────────────────────────────────────────────────
REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": (
        "rest_framework_simplejwt.authentication.JWTAuthentication",
    ),
    "DEFAULT_PERMISSION_CLASSES": (
        "rest_framework.permissions.IsAuthenticated",
    ),
    "DEFAULT_PARSER_CLASSES": [
        "rest_framework.parsers.JSONParser",
        "rest_framework.parsers.MultiPartParser",
        "rest_framework.parsers.FormParser",
    ],
}

# ── JWT ────────────────────────────────────────────────────────────────────────
SIMPLE_JWT = {
    "ACCESS_TOKEN_LIFETIME":  timedelta(hours=config("ACCESS_TOKEN_LIFETIME_HOURS", default=1,  cast=int)),
    "REFRESH_TOKEN_LIFETIME": timedelta(days=config("REFRESH_TOKEN_LIFETIME_DAYS",  default=30, cast=int)),
    "ROTATE_REFRESH_TOKENS":    True,
    "BLACKLIST_AFTER_ROTATION": False,
    "AUTH_HEADER_TYPES":        ("Bearer",),
}

# ── Google OAuth ───────────────────────────────────────────────────────────────
GOOGLE_CLIENT_ID = config("GOOGLE_CLIENT_ID", default="")

# ── CORS ───────────────────────────────────────────────────────────────────────
if DEBUG:
    CORS_ALLOW_ALL_ORIGINS = True
else:
    CORS_ALLOWED_ORIGINS = config(
        "CORS_ALLOWED_ORIGINS",
        default="",
        cast=lambda v: [s.strip() for s in v.split(",") if s.strip()],
    )

# ── File Storage ───────────────────────────────────────────────────────────────
MEDIA_URL  = "/media/"
MEDIA_ROOT = BASE_DIR / str(config("MEDIA_ROOT", default="media"))

# ── Static files (WhiteNoise) ──────────────────────────────────────────────────
STATIC_URL          = "/static/"
STATIC_ROOT         = BASE_DIR / "staticfiles"
STATICFILES_STORAGE = "whitenoise.storage.CompressedManifestStaticFilesStorage"

# ── Hugging Face ───────────────────────────────────────────────────────────────
HF_API_TOKEN = config("HF_API_TOKEN", default="")

# ── Internationalisation ───────────────────────────────────────────────────────
LANGUAGE_CODE = "en-us"
TIME_ZONE     = "UTC"
USE_I18N      = True
USE_TZ        = True

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

# ── Email ──────────────────────────────────────────────────────────────────────
# Dev  → console backend (prints to terminal, no real sending)
#        EMAIL_BACKEND=django.core.mail.backends.console.EmailBackend
#
# Prod → Resend via anymail (works on Render free tier, no SMTP ports needed)
#        EMAIL_BACKEND=anymail.backends.resend.EmailBackend
#        RESEND_API_KEY=re_xxxxxxxxxxxx
#        DEFAULT_FROM_EMAIL=Studyforge <onboarding@resend.dev>

EMAIL_BACKEND      = config("EMAIL_BACKEND",      default="django.core.mail.backends.console.EmailBackend")
DEFAULT_FROM_EMAIL = config("DEFAULT_FROM_EMAIL", default="Studyforge <onboarding@resend.dev>")

ANYMAIL = {
    "RESEND_API_KEY": config("RESEND_API_KEY", default=""),
}

# ── Production security ────────────────────────────────────────────────────────
if not DEBUG:
    SECURE_HSTS_SECONDS            = 31536000
    SECURE_HSTS_INCLUDE_SUBDOMAINS = True
    SECURE_SSL_REDIRECT            = True
    SESSION_COOKIE_SECURE          = True
    CSRF_COOKIE_SECURE             = True

# ── Templates ─────────────────────────────────────────────────────────────────
TEMPLATES[0]["DIRS"] += [BASE_DIR / "apps" / "accounts" / "templates"]