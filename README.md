# 📚 Studyforge V3 — AI-Powered Study Assistant

> Upload a PDF or DOCX → AI generates a **Summary**, **Quiz**, and **Flashcards** instantly.
> Includes **User Profiles**, **Study History**, **Spaced Repetition**, **Analytics**, and a full **Admin Panel**.
> 100% free-tier stack: **Django + PostgreSQL + Hugging Face + Flutter**. No Supabase.

---

## 🗂 Project Structure

```
studyforge_v3/
├── studyforge_django/                  ← Django backend (replaces FastAPI + Supabase)
│   ├── manage.py
│   ├── requirements.txt
│   ├── run.sh                          ← dev start (migrate + runserver)
│   ├── setup.sh                        ← first-time venv + pip install
│   ├── .env.example
│   │
│   ├── studyforge/                     ← Django project config
│   │   ├── settings.py
│   │   ├── urls.py
│   │   └── wsgi.py
│   │
│   ├── apps/
│   │   ├── accounts/                   ← User + Profile + Auth + Admin
│   │   │   ├── models.py               (User, Profile)
│   │   │   ├── serializers.py
│   │   │   ├── views.py                (signup, signin, signout, profile, admin)
│   │   │   ├── urls.py
│   │   │   └── health_urls.py
│   │   ├── results/                    ← Upload + Process + CRUD + Retry
│   │   │   ├── models.py               (Result)
│   │   │   ├── serializers.py
│   │   │   ├── views.py
│   │   │   ├── urls.py
│   │   │   ├── upload_urls.py
│   │   │   ├── process_urls.py
│   │   │   └── retry_urls.py
│   │   ├── analytics/                  ← Quiz attempts + accuracy + weak topics
│   │   │   ├── models.py               (QuizAttempt)
│   │   │   ├── views.py
│   │   │   └── urls.py
│   │   ├── ingest/                     ← URL scraping, YouTube transcript, OCR
│   │   │   ├── views.py
│   │   │   └── urls.py
│   │   ├── shared/                     ← Public/shared study sessions
│   │   │   ├── views.py
│   │   │   └── urls.py
│   │   ├── spaced_repetition/          ← SM-2 flashcard scheduling
│   │   │   ├── models.py               (SRCard)
│   │   │   ├── views.py
│   │   │   └── urls.py
│   │   └── notifications/              ← In-app notifications
│   │       ├── models.py               (Notification)
│   │       ├── views.py
│   │       └── urls.py
│   │
│   └── utils/
│       ├── file_extractor.py           ← PDF + DOCX text extraction
│       ├── ai_generator.py             ← Hugging Face AI calls
│       └── storage.py                  ← Local filesystem or Cloudinary
│
└── flutter_app/
    ├── pubspec.yaml
    ├── .env.example
    └── lib/
        ├── main.dart
        ├── core/constants.dart
        ├── models/
        │   ├── study_result.dart
        │   └── profile.dart
        ├── services/
        │   ├── auth_service.dart       ← JWT auth (replaces Supabase auth)
        │   ├── api_service.dart
        │   └── profile_service.dart
        ├── widgets/
        │   ├── sf_logo.dart
        │   └── app_bottom_nav.dart
        └── screens/
            ├── login_screen.dart
            ├── home_screen.dart
            ├── upload_screen.dart
            ├── results_screen.dart
            ├── profile_screen.dart
            ├── analytics_screen.dart
            ├── sr_review_screen.dart
            ├── shared_sessions_screen.dart
            ├── notifications_screen.dart
            └── admin/
                ├── admin_dashboard_screen.dart
                ├── admin_users_screen.dart
                └── admin_user_detail_screen.dart
```

---

## 🆓 Free Services Used

| Service | Purpose | Free Limit |
|---------|---------|-----------|
| **Neon.tech** | PostgreSQL database | 0.5 GB, always free |
| **Render.com** | Django backend hosting | 750 hrs/month |
| **Cloudinary** | File storage (optional) | 25 GB free |
| **Hugging Face** | AI text generation | ~30k requests/month |
| **Flutter** | Mobile frontend | Free & open source |

---

## 🔥 STEP 1 — PostgreSQL Setup

### Option A — Neon.tech (recommended, always free)
1. Go to **https://neon.tech** → Sign up free
2. Click **New Project** → name it `studyforge`
3. Copy the **connection string** — looks like:
   ```
   postgresql://user:password@ep-xxx.us-east-2.aws.neon.tech/neondb?sslmode=require
   ```
4. Paste it as `DATABASE_URL` in your `.env`

### Option B — Local PostgreSQL
```bash
createdb studyforge
# DATABASE_URL=postgresql://postgres:yourpassword@localhost:5432/studyforge
```

---

## 🤗 STEP 2 — Hugging Face Token

1. **https://huggingface.co** → Sign up free
2. Settings → Access Tokens → **New token** (Read role)
3. Copy the `hf_...` token

---

## 🐍 STEP 3 — Backend Setup

```bash
cd studyforge_django
bash setup.sh          # creates venv, pip install, copies .env.example → .env
```

Fill in `.env`:
```env
SECRET_KEY=your-long-random-secret-key
DEBUG=True
DATABASE_URL=postgresql://user:password@host:5432/dbname
HF_API_TOKEN=hf_xxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

Then:
```bash
source venv/bin/activate
python manage.py migrate        # creates all tables
bash run.sh                     # starts on http://localhost:8000
```

Visit **http://localhost:8000** — you should see:
```json
{"status": "ok", "message": "Studyforge API (Django) is running 🚀"}
```

### Make yourself admin
After signing up in the app, run this SQL (in Neon SQL editor or psql):
```sql
UPDATE profiles SET is_admin = TRUE
WHERE id = (SELECT id FROM auth_user WHERE email = 'your@email.com');
```

---

## 📱 STEP 4 — Flutter Setup

```bash
cd flutter_app
cp .env.example .env
# Fill in: API_BASE_URL
flutter pub get
flutter run
```

**`.env` contents:**
```env
# Django backend URL — no trailing slash
# Android emulator:  http://10.0.2.2:8000
# iOS simulator:     http://localhost:8000
# Real device (WiFi): http://192.168.x.x:8000
# Production:        https://your-app.onrender.com
API_BASE_URL=http://10.0.2.2:8000
```

> ⚠️ `SUPABASE_URL` and `SUPABASE_ANON_KEY` have been removed. Delete them from your `.env` if they exist.

---

## 🔄 What Changed vs Original (Supabase → Django)

| Before | After |
|--------|-------|
| Supabase Auth | Django custom User + JWT (`djangorestframework-simplejwt`) |
| Supabase PostgreSQL | Self-hosted or Neon.tech PostgreSQL |
| Row Level Security (RLS) | `queryset.filter(user=request.user)` |
| Supabase Storage | Local `media/` folder or Cloudinary |
| SQL migration scripts | `python manage.py migrate` |
| Supabase trigger (profile on signup) | Django `post_save` signal |
| FastAPI routers | Django REST Framework views |
| `supabase_flutter` package | `http` + `shared_preferences` |

---

## 🌟 Features

### User Features
| Feature | Description |
|---------|-------------|
| **Auth** | Email/password sign up & sign in via JWT |
| **Dashboard** | Stats (sessions, questions, flashcards, accuracy) with animated number roll |
| **Upload** | PDF/DOCX upload with drag-and-drop + animated step progress |
| **AI Study Materials** | Summary, MCQ quiz with score tracker, 3D flip flashcards |
| **Profile** | Edit name, bio & phone, view account info |
| **History** | Sessions grouped by date with search/filter |
| **Spaced Repetition** | SM-2 algorithm — due-for-review section + dedicated review screen |
| **Analytics** | Per-user accuracy trends, weak topics, and weekly stats |
| **Notifications** | In-app notification centre with unread badge dot |
| **Shared Sessions** | Browse and clone sessions shared by other users |
| **Ingest** | Create sessions from URLs, YouTube videos, or scanned images (OCR) |

### Navigation
| Feature | Description |
|---------|-------------|
| **Bottom nav bar** | Persistent `AppBottomNav` widget — Home, Upload, Review, Analytics, Shared |

### Dashboard Features (home_screen)
| Feature | Description |
|---------|-------------|
| **Animated stat cards** | Numbers roll from 0 → value on load |
| **Reactive greeting** | Good morning / afternoon / evening |
| **Notifications bell** | Red dot badge; opens `NotificationsScreen` |
| **Stat cards** | Questions, Flashcards, Accuracy rate, Docs processed |
| **Week-over-week deltas** | Green/red pill on Questions and Flashcards cards |
| **Search & filter** | Live client-side search across session names |
| **Grouped sessions** | This week / This month / Older |
| **Long-press context menu** | Rename or Delete |
| **Swipe to delete** | With confirmation |
| **Retry failed sessions** | Re-runs AI generation inline |
| **Continue where you left off** | Amber card for most recent session |
| **Due for review section** | Up to 3 SR sessions; opens `SrReviewScreen` |
| **Haptic feedback** | On tile tap and long-press |
| **Offline banner** | Red bar on connectivity loss |
| **Confetti on first upload** | 🎉 |

### Upload Features
| Feature | Description |
|---------|-------------|
| **Drag-and-drop zone** | Animated dashed border on hover |
| **Animated step pills** | Upload → Extract → Generate → Done |
| **Offline banner** | Disables the CTA button |

### Quiz Features
| Feature | Description |
|---------|-------------|
| **Live score tracker** | Answered / correct / wrong pills |
| **Progress ring** | Animated CustomPainter arc |
| **Streak flame 🔥** | Longest consecutive correct run |
| **Try Again** | Resets all answers and score |

### Flashcard Features
| Feature | Description |
|---------|-------------|
| **True 3D flip** | Matrix4.rotateY with perspective |
| **Per-card controller** | Each card flips independently |

### Admin Features
| Feature | Description |
|---------|-------------|
| **Dashboard** | Total users, sessions, sessions today, recent signups |
| **User List** | Paginated + searchable |
| **User Detail** | Profile + all sessions |
| **Delete Sessions** | Swipe-to-delete any session |
| **Toggle Admin** | Promote/demote users |

---

## 🌐 API Reference

### Auth
| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| POST | `/auth/signup/` | ❌ | Create account → returns JWT |
| POST | `/auth/signin/` | ❌ | Sign in → returns JWT |
| POST | `/auth/refresh/` | ❌ | Refresh access token |
| POST | `/auth/signout/` | ✅ | Invalidate refresh token |
| POST | `/auth/reset-password/` | ❌ | Send password reset email |

### Upload & Process
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/upload/` | Upload PDF/DOCX, extract text, save pending row |
| POST | `/process/` | Run AI generation → update result |
| POST | `/retry/{id}/` | Re-extract text for retry |

### Results
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/results/` | List user's results |
| GET | `/results/{id}/` | Fetch one result |
| DELETE | `/results/{id}/` | Delete result |
| PATCH | `/results/{id}/` | Rename result (`{"file_name": "new name"}`) |

### Profile & Admin
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET/PUT | `/profile/{user_id}/` | Get or update profile |
| GET | `/profile/{user_id}/history/` | Study history |
| GET | `/admin/stats/` | Platform stats |
| GET | `/admin/users/` | All users (paginated) |
| GET | `/admin/users/{id}/` | User + sessions |
| DELETE | `/admin/results/{id}/` | Delete any session |
| PUT | `/admin/users/{id}/toggle-admin/` | Promote/demote admin |

### Analytics
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/analytics/quiz-attempt/` | Record quiz attempt |
| GET | `/analytics/weak-topics/{user_id}/` | Topics ranked by error rate |
| GET | `/analytics/accuracy/{user_id}/` | Daily accuracy over N days |
| GET | `/analytics/summary/{user_id}/` | Dashboard stats (avg accuracy, streak) |
| GET | `/analytics/weekly-stats/{user_id}/` | Questions & flashcards delta vs last week |

### Ingest
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/ingest/url/` | Scrape webpage → extract text |
| POST | `/ingest/youtube/` | YouTube transcript |
| POST | `/ingest/ocr/` | Image OCR |

### Shared Sessions
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/shared/browse/` | Public sessions list |
| GET | `/shared/featured/` | Top 10 most cloned |
| GET | `/shared/{id}/` | Public session detail |
| POST | `/shared/{id}/clone/` | Clone to own library |
| PATCH | `/shared/{id}/visibility/` | Toggle public/private |

### Spaced Repetition
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/sr/init/{result_id}/` | Create SR cards for a session |
| POST | `/sr/review/` | Record review (SM-2 update) |
| GET | `/sr/due/{user_id}/` | Cards due today |
| GET | `/sr/stats/{user_id}/` | SR deck stats |

### Notifications
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/notifications/{user_id}/` | List notifications |
| PATCH | `/notifications/{id}/read/` | Mark one as read |
| POST | `/notifications/{user_id}/read-all/` | Mark all as read |
| DELETE | `/notifications/{id}/` | Delete notification |

---

## 🔐 Authentication

All protected endpoints require:
```
Authorization: Bearer <access_token>
```

Tokens are returned from `/auth/signup/` and `/auth/signin/`.
Use `/auth/refresh/` with the `refresh` token when the access token expires (default: 1 hour).
Tokens are stored in `SharedPreferences` by `auth_service.dart`.

---

## 📦 Flutter Dependencies

```yaml
dependencies:
  flutter:
    sdk: flutter

  dio: ^5.4.3+1               # HTTP client for API calls
  http: ^1.2.1                # Used by auth_service.dart
  file_picker: ^8.0.3         # File selection
  google_fonts: ^6.2.1        # Typography
  flutter_animate: ^4.5.0     # Animations
  fluttertoast: ^8.2.4        # Toast messages
  flutter_dotenv: ^5.1.0      # .env loading
  shared_preferences: ^2.2.3  # Stores JWT token + user_id
  image_picker: ^1.1.2        # Avatar upload
  confetti: ^0.7.0            # First-upload celebration
  connectivity_plus: ^6.0.3   # Offline banner
  url_launcher: ^6.3.0        # URL launcher
```

> `supabase_flutter` and `google_sign_in` have been removed.

---

## 📦 Backend Dependencies

```
django>=5.0
djangorestframework>=3.15
djangorestframework-simplejwt>=5.3
psycopg2-binary>=2.9
django-cors-headers>=4.3
python-decouple>=3.8
dj-database-url>=2.1.0
httpx>=0.27
PyPDF2>=3.0.1
python-docx>=1.1.0
beautifulsoup4>=4.12
youtube-transcript-api>=0.6.2
pytesseract>=0.3.10
Pillow>=10.3
```

---

## ✅ Quick Checklist

```
Backend:
□ PostgreSQL database created (Neon.tech or local)
□ .env filled: SECRET_KEY, DATABASE_URL, HF_API_TOKEN
□ python manage.py migrate     ← creates all 6 tables
□ bash run.sh                  ← http://localhost:8000 returns {"status":"ok"}
□ Admin set: UPDATE profiles SET is_admin=TRUE WHERE id=(SELECT id FROM auth_user WHERE email='you@...')

Flutter:
□ pubspec.yaml: supabase_flutter removed, http: ^1.2.1 added
□ flutter_app/.env: only API_BASE_URL (no Supabase keys)
□ lib/services/auth_service.dart replaced
□ lib/services/api_service.dart replaced
□ lib/services/profile_service.dart replaced
□ lib/main.dart replaced
□ flutter pub get
□ flutter run
```

---

## 🚀 Production Deployment

**Backend → Render.com (free):**
```
Build command:  pip install -r requirements.txt && python manage.py migrate
Start command:  gunicorn studyforge.wsgi:application --bind 0.0.0.0:$PORT
Environment vars: SECRET_KEY, DATABASE_URL, HF_API_TOKEN, DEBUG=False
```

**Database → Neon.tech (free forever):**
Copy the connection string from Neon dashboard → paste as `DATABASE_URL`.

**File storage → Cloudinary (free 25 GB):**
Set `CLOUDINARY_CLOUD_NAME`, `CLOUDINARY_API_KEY`, `CLOUDINARY_API_SECRET` in `.env` — files automatically go to Cloudinary instead of local disk.

**Flutter → APK:**
```bash
flutter build apk --release
```

---

## 🆘 Troubleshooting

| Problem | Fix |
|---------|-----|
| `relation does not exist` | Run `python manage.py migrate` |
| `401 Unauthorized` | Check `Authorization: Bearer <token>` header is sent |
| `403 Admin access required` | Run the SQL to set `is_admin=TRUE` for your account |
| Admin panel not showing in app | Same as above — `is_admin` must be true in DB |
| HF API 503 | Model cold-starting — wait 30s and retry |
| `Connection refused` on emulator | Use `10.0.2.2:8000` not `localhost:8000` |
| `Connection refused` on iOS | Use `localhost:8000` |
| Rename not saving | Check trailing slash on PATCH `/results/{id}/` |
| Retry button not working | Check `httpx` is installed: `pip install httpx` |
| Stats showing 0 / accuracy blank | Make sure `/analytics/summary/{user_id}/` returns data |
| Notifications bell always empty | Notifications are created server-side; none exist until events fire |
| Offline banner not showing | `connectivity_plus` must be in `pubspec.yaml` |
| Drag-and-drop not working | Only works on desktop/web — mobile uses the tap picker |
| OCR not working | Install Tesseract: `apt install tesseract-ocr` / `brew install tesseract` |
| `CORS error` | `CORS_ALLOW_ALL_ORIGINS = True` is set in settings.py by default |
| Token expired mid-session | `AuthService.refreshAccessToken()` is called automatically |
| `instance_access_to_static_member` | Use `AuthService.userId` not `AuthService().userId` — or just update `auth_service.dart` |

---

## 🗄️ Database Tables

| Table | App | Purpose |
|-------|-----|---------|
| `auth_user` | accounts | Login credentials |
| `profiles` | accounts | Name, bio, avatar, is_admin |
| `results` | results | Study sessions (summary, quiz, flashcards) |
| `quiz_attempts` | analytics | Quiz scores and per-question answers |
| `sr_cards` | spaced_repetition | SM-2 flashcard scheduling data |
| `notifications` | notifications | In-app notification messages |

---

## 📝 Changelog

### v3.0.0 — Current
**Backend — full rewrite**
- Replaced FastAPI + Supabase with Django + PostgreSQL + JWT
- All API paths, request shapes, and response shapes identical to v2
- Django ORM queryset filtering replaces Supabase Row Level Security
- `post_save` signal replaces Supabase trigger for profile auto-creation
- Local filesystem storage replaces Supabase Storage (Cloudinary optional)
- Added `apps.notifications` — full CRUD for in-app notifications
- Added `POST /auth/reset-password/` endpoint
- Added `dj-database-url` for flexible DB connection via `DATABASE_URL`

**Flutter**
- Removed `supabase_flutter` and `google_sign_in` packages
- Added `http: ^1.2.1`
- `auth_service.dart` — JWT stored in SharedPreferences; works as both `AuthService.userId` (static) and `AuthService().userId` (instance)
- `api_service.dart` — token read from SharedPreferences; all endpoints have trailing slashes
- `profile_service.dart` — same token fix; all endpoints have trailing slashes
- `main.dart` — calls `AuthService.init()` to pre-load user cache; no Supabase initialisation

### v2.1.0
- Spaced repetition, analytics, shared sessions, notifications screens
- Ingest: URL scraping, YouTube, OCR
- Home screen: animated stats, grouping, search, swipe-to-delete, confetti

### v2.0.0
- Initial release with Auth, Upload, Quiz, Flashcards, Profile, Admin panel

---

## 📝 License
MIT — free for personal and commercial use.