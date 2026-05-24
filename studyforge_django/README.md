# 📚 Studyforge V3 — Django Backend

> Full replacement of the FastAPI + Supabase backend with **Django + PostgreSQL + JWT**.
> Drop-in compatible — all API paths, request shapes, and response shapes are identical.
> Your Flutter app needs **one file change** (auth_service.dart) and a **.env update**.

---

## 🗂 Project Structure

```
studyforge_django/
├── manage.py
├── requirements.txt
├── .env.example
├── run.sh                        ← dev start (migrate + runserver)
├── setup.sh                      ← first-time venv + pip install
│
├── studyforge/                   ← Django project
│   ├── settings.py
│   ├── urls.py                   ← root URL router
│   └── wsgi.py
│
├── apps/
│   ├── accounts/                 ← User + Profile + Auth + Admin
│   │   ├── models.py             (User, Profile — replaces Supabase auth + profiles table)
│   │   ├── serializers.py
│   │   ├── views.py              (signup, signin, signout, profile CRUD, admin endpoints)
│   │   ├── urls.py
│   │   └── health_urls.py
│   │
│   ├── results/                  ← Upload + Process + CRUD + Retry
│   │   ├── models.py             (Result — replaces Supabase results table)
│   │   ├── serializers.py
│   │   ├── views.py
│   │   ├── urls.py
│   │   ├── upload_urls.py
│   │   ├── process_urls.py
│   │   └── retry_urls.py
│   │
│   ├── analytics/                ← Quiz attempts + accuracy + weak topics
│   │   ├── models.py             (QuizAttempt — replaces Supabase quiz_attempts table)
│   │   ├── views.py
│   │   └── urls.py
│   │
│   ├── ingest/                   ← URL scraping, YouTube transcript, OCR
│   │   ├── views.py
│   │   └── urls.py
│   │
│   ├── shared/                   ← Public/shared study sessions
│   │   ├── views.py
│   │   └── urls.py
│   │
│   └── spaced_repetition/        ← SM-2 flashcard scheduling
│       ├── models.py             (SRCard — replaces Supabase sr_cards table)
│       ├── views.py
│       └── urls.py
│
├── utils/
│   ├── file_extractor.py         ← PDF + DOCX text extraction (unchanged)
│   ├── ai_generator.py           ← Hugging Face AI calls (unchanged)
│   └── storage.py                ← Local filesystem or Cloudinary (replaces Supabase Storage)
│
└── flutter_auth_service.dart     ← Drop-in replacement for Flutter auth_service.dart
```

---

## 🔄 What Changed vs Supabase

| Before (Supabase) | After (Django) |
|---|---|
| Supabase Auth | Django custom User + `djangorestframework-simplejwt` |
| Supabase PostgreSQL | Self-hosted or managed PostgreSQL |
| Row Level Security (RLS) | `queryset.filter(user=request.user)` |
| Supabase Storage | Local `media/` folder or Cloudinary |
| SQL migration scripts | `python manage.py migrate` |
| Supabase trigger (profile on signup) | Django `post_save` signal |
| `supabase_client.py` | Removed entirely |
| `supabase_helpers.py` | Removed entirely |

---

## 🚀 Quick Start

### 1. PostgreSQL — free options
| Service | Free tier | URL format |
|---|---|---|
| **Neon.tech** ✅ recommended | 0.5 GB, always free | `postgresql://user:pass@ep-xxx.us-east-2.aws.neon.tech/neondb` |
| **Render.com** | 90 days free, then $7/mo | connection string from dashboard |
| **Local** | Unlimited | `localhost` |

For Neon: sign up → New project → copy the connection string → split into `DB_NAME`, `DB_USER`, `DB_PASSWORD`, `DB_HOST`.

### 2. Backend setup

```bash
cd studyforge_django
bash setup.sh          # creates venv + pip install + copies .env

# Fill in .env:
#   DB_NAME, DB_USER, DB_PASSWORD, DB_HOST
#   HF_API_TOKEN   (from https://huggingface.co/settings/tokens)

source venv/bin/activate
python manage.py migrate        # creates all tables
python manage.py createsuperuser  # optional — gives you Django admin at /admin/

bash run.sh            # starts on http://localhost:8000
```

Open **http://localhost:8000** — you should see:
```json
{"status": "ok", "message": "Studyforge API (Django) is running 🚀"}
```

### 3. Make yourself admin (same as before, but SQL)

```sql
-- In psql or Neon SQL editor:
UPDATE profiles SET is_admin = TRUE WHERE id = (
  SELECT id FROM auth_user WHERE email = 'your@email.com'
);
```

### 4. Flutter changes (minimal)

**File 1 — replace `lib/services/auth_service.dart`** with `flutter_auth_service.dart` from this repo.

**File 2 — update `flutter_app/.env`:**
```
# Remove these two lines:
SUPABASE_URL=...
SUPABASE_ANON_KEY=...

# Keep only:
API_BASE_URL=http://localhost:8000
```

**File 3 — `pubspec.yaml`** — remove the Supabase package, add `http`:
```yaml
# Remove:
supabase_flutter: ^2.5.3

# Add (if not already present):
http: ^1.2.1
```

Run `flutter pub get` and you're done.

---

## 🌐 API Reference

All endpoints are identical to the FastAPI version.

### Auth
| Method | Endpoint | Auth | Description |
|---|---|---|---|
| POST | `/auth/signup/` | ❌ | Create account → returns JWT tokens |
| POST | `/auth/signin/` | ❌ | Sign in → returns JWT tokens |
| POST | `/auth/refresh/` | ❌ | Refresh access token |
| POST | `/auth/signout/` | ✅ | Invalidate refresh token |

### Upload & Process
| Method | Endpoint | Description |
|---|---|---|
| POST | `/upload/` | Upload PDF/DOCX, extract text, save pending row |
| POST | `/process/` | Run AI generation → update result row |
| POST | `/retry/{id}/` | Re-extract text for retry |

### Results
| Method | Endpoint | Description |
|---|---|---|
| GET | `/results/` | List user's results |
| GET | `/results/{id}/` | Fetch one result |
| DELETE | `/results/{id}/` | Delete result |
| PATCH | `/results/{id}/` | Rename result |

### Profile & Admin
| Method | Endpoint | Description |
|---|---|---|
| GET/PUT | `/profile/{user_id}/` | Get or update profile |
| GET | `/profile/{user_id}/history/` | Study history |
| GET | `/admin/stats/` | Platform stats |
| GET | `/admin/users/` | All users (paginated) |
| GET | `/admin/users/{id}/` | User + sessions |
| DELETE | `/admin/results/{id}/` | Delete any session |
| PUT | `/admin/users/{id}/toggle-admin/` | Promote/demote admin |

### Analytics
| Method | Endpoint | Description |
|---|---|---|
| POST | `/analytics/quiz-attempt/` | Record quiz attempt |
| GET | `/analytics/weak-topics/{user_id}/` | Topics ranked by error rate |
| GET | `/analytics/accuracy/{user_id}/` | Daily accuracy over N days |
| GET | `/analytics/summary/{user_id}/` | Dashboard stats |
| GET | `/analytics/weekly-stats/{user_id}/` | Questions & flashcards delta |

### Ingest
| Method | Endpoint | Description |
|---|---|---|
| POST | `/ingest/url/` | Scrape webpage |
| POST | `/ingest/youtube/` | YouTube transcript |
| POST | `/ingest/ocr/` | Image OCR |

### Shared Sessions
| Method | Endpoint | Description |
|---|---|---|
| GET | `/shared/browse/` | Public sessions list |
| GET | `/shared/featured/` | Top 10 most cloned |
| GET | `/shared/{id}/` | Public session detail |
| POST | `/shared/{id}/clone/` | Clone to own library |
| PATCH | `/shared/{id}/visibility/` | Toggle public/private |

### Spaced Repetition
| Method | Endpoint | Description |
|---|---|---|
| POST | `/sr/init/{result_id}/` | Create SR cards for a session |
| POST | `/sr/review/` | Record review (SM-2 update) |
| GET | `/sr/due/{user_id}/` | Cards due today |
| GET | `/sr/stats/{user_id}/` | SR deck stats |

---

## 🔐 Authentication

All protected endpoints expect:
```
Authorization: Bearer <access_token>
```

Tokens are returned from `/auth/signup/` and `/auth/signin/`. Use `/auth/refresh/` with the `refresh` token to get a new access token when it expires (default: 1 hour).

---

## 📦 Dependencies

```
django                          # web framework
djangorestframework             # REST API
djangorestframework-simplejwt   # JWT auth (replaces Supabase Auth)
psycopg2-binary                 # PostgreSQL driver (replaces Supabase client)
django-cors-headers             # CORS for Flutter
python-decouple                 # .env loading
httpx                           # async HTTP (AI calls, retry downloads)
PyPDF2                          # PDF extraction
python-docx                     # DOCX extraction
beautifulsoup4                  # URL scraping
youtube-transcript-api          # YouTube ingest
pytesseract                     # OCR ingest
Pillow                          # image handling
```

---

## 🚀 Production Deployment

**Render.com (free tier):**
```
Build command:  pip install -r requirements.txt && python manage.py migrate
Start command:  gunicorn studyforge.wsgi:application --bind 0.0.0.0:$PORT
```

Add env vars in Render dashboard (same as your `.env`).

**Database:** use Neon.tech — copy the connection string and split it into the `DB_*` vars.

**File storage:** set `CLOUDINARY_CLOUD_NAME`, `CLOUDINARY_API_KEY`, `CLOUDINARY_API_SECRET` and files will automatically go to Cloudinary instead of local disk.

---

## ✅ Migration Checklist

```
Backend:
□ PostgreSQL database created (Neon or local)
□ .env filled: DB_*, HF_API_TOKEN, SECRET_KEY
□ python manage.py migrate  — all tables created
□ Server running: bash run.sh → http://localhost:8000 returns {"status":"ok"}
□ Admin account: UPDATE profiles SET is_admin=TRUE WHERE ...

Flutter:
□ lib/services/auth_service.dart replaced with flutter_auth_service.dart
□ flutter_app/.env: SUPABASE_URL and SUPABASE_ANON_KEY removed
□ flutter_app/.env: API_BASE_URL=http://localhost:8000
□ pubspec.yaml: supabase_flutter removed, http added
□ flutter pub get

Done — test signup → upload → process → quiz
```

---

## 🆘 Troubleshooting

| Problem | Fix |
|---|---|
| `django.db.utils.OperationalError` | Check DB credentials in .env |
| `relation "auth_user" does not exist` | Run `python manage.py migrate` |
| `401 Unauthorized` | Pass `Authorization: Bearer <token>` header |
| `403 Admin access required` | Set `is_admin=TRUE` in profiles table for your user |
| HF API 503 | Model cold-starting — wait 30 s and retry |
| File upload 413 | File exceeds 10 MB limit |
| OCR returns empty | Install tesseract: `brew install tesseract` / `apt install tesseract-ocr` |
| CORS error from Flutter | `CORS_ALLOW_ALL_ORIGINS = True` is set in settings.py by default |
| Static files 404 in prod | Add `whitenoise` and `STATICFILES_STORAGE` in settings.py |

---

## 📝 License
MIT — free for personal and commercial use.
