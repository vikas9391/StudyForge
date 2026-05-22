# 📚 Studyforge V3 — AI-Powered Study Assistant

> Upload a PDF or DOCX → AI generates a **Summary**, **Quiz**, and **Flashcards** instantly.
> Includes **User Profiles**, **Study History**, **Spaced Repetition**, **Analytics**, and a full **Admin Panel**.
> 100% free-tier stack: Supabase + Hugging Face + FastAPI + Flutter.

---

## 🗂 Project Structure

```
studyforge_v2/
├── backend/
│   ├── main.py
│   ├── requirements.txt
│   ├── run.sh
│   ├── .env.example
│   ├── routers/
│   │   ├── auth.py          # signup / signin / signout
│   │   ├── upload.py        # file upload + text extraction
│   │   ├── process.py       # AI generation
│   │   ├── results.py       # fetch / delete / rename / retry  ← UPDATED
│   │   └── profile.py       # profile CRUD + admin endpoints
│   └── utils/
│       ├── supabase_client.py
│       ├── supabase_helpers.py
│       ├── file_extractor.py
│       └── ai_generator.py
│
└── flutter_app/
    ├── pubspec.yaml                          ← UPDATED (2 new packages)
    ├── .env.example
    └── lib/
        ├── main.dart
        ├── core/constants.dart
        ├── models/
        │   ├── study_result.dart
        │   └── profile.dart
        ├── services/
        │   ├── auth_service.dart
        │   ├── api_service.dart              ← UPDATED (rename + retry + stats + notifications)
        │   └── profile_service.dart
        ├── widgets/
        │   ├── sf_logo.dart
        │   └── app_bottom_nav.dart           ← NEW
        └── screens/
            ├── login_screen.dart
            ├── home_screen.dart              ← UPDATED
            ├── upload_screen.dart            ← UPDATED
            ├── results_screen.dart           ← UPDATED
            ├── profile_screen.dart
            ├── analytics_screen.dart         ← NEW
            ├── sr_review_screen.dart         ← NEW
            ├── shared_sessions_screen.dart   ← NEW
            ├── notifications_screen.dart     ← NEW
            └── admin/
                ├── admin_dashboard_screen.dart
                ├── admin_users_screen.dart
                └── admin_user_detail_screen.dart
```

---

## 🆓 Free Services Used

| Service | Purpose | Free Limit |
|---------|---------|-----------|
| **Supabase** | Auth + DB + Storage | 500 MB DB, 1 GB Storage, 50k MAU |
| **Hugging Face** | AI text generation | ~30k requests/month |
| **FastAPI** | Backend API | Self-hosted (free) |
| **Flutter** | Mobile frontend | Free & open source |

---

## 🔥 STEP 1 — Supabase Setup

### 1a. Create project
1. Go to **https://supabase.com** → Sign up free
2. Click **"New project"** → name it `studyforge` → **Create project**

### 1b. Run the SQL setup (2 scripts)

Go to **SQL Editor** → run each script separately:

**Script 1 — `supabase_setup.sql`** (results table):
```sql
create table if not exists results (
    id          uuid primary key default gen_random_uuid(),
    user_id     text not null,
    file_url    text,
    file_name   text default '',
    summary     text,
    quiz        jsonb default '[]',
    flashcards  jsonb default '[]',
    created_at  timestamptz default now()
);
alter table results enable row level security;
create policy "Users manage own results"
    on results for all
    using  (auth.uid()::text = user_id)
    with check (auth.uid()::text = user_id);
create index if not exists results_user_id_idx
    on results (user_id, created_at desc);
```

> ⚠️ If you already created this table without the `file_name` column, add it with:
> ```sql
> alter table results add column if not exists file_name text default '';
> ```

**Script 2 — `supabase_profiles_admin.sql`** (profiles table + trigger):
```sql
create table if not exists profiles (
    id          uuid primary key references auth.users(id) on delete cascade,
    email       text,
    full_name   text default '',
    avatar_url  text default '',
    bio         text default '',
    is_admin    boolean default false,
    created_at  timestamptz default now(),
    updated_at  timestamptz default now()
);
alter table profiles enable row level security;
create policy "Users read own profile"
    on profiles for select using (auth.uid() = id);
create policy "Users update own profile"
    on profiles for update using (auth.uid() = id);
create policy "Admins read all profiles"
    on profiles for select
    using (exists (
        select 1 from profiles where id = auth.uid() and is_admin = true
    ));
create or replace function public.handle_new_user()
returns trigger as $$
begin
    insert into public.profiles (id, email) values (new.id, new.email);
    return new;
end;
$$ language plpgsql security definer;
create trigger on_auth_user_created
    after insert on auth.users
    for each row execute procedure public.handle_new_user();
create index if not exists profiles_email_idx on profiles (email);
create index if not exists results_created_at_idx on results (created_at desc);
```

### 1c. Make yourself admin
After creating your account in the app, run this in SQL Editor:
```sql
update profiles set is_admin = true where email = 'your@email.com';
```

### 1d. Create Storage bucket
1. Left sidebar → **Storage** → **New bucket**
2. Name: `studyforge-files` → Toggle **Public** ON → **Create**

### 1e. Get API keys
1. **Project Settings → API**
2. Copy: **Project URL**, **anon key** (Flutter), **service_role key** (backend)

---

## 🤗 STEP 2 — Hugging Face Token

1. **https://huggingface.co** → Sign up free
2. Settings → Access Tokens → **New token** (Read role)
3. Copy the `hf_...` token

---

## 🐍 STEP 3 — Backend Setup

```bash
cd studyforge_v2/backend
cp .env.example .env
# Fill in: SUPABASE_URL, SUPABASE_SERVICE_KEY, HF_API_TOKEN

python3 -m venv venv
source venv/bin/activate      # Windows: venv\Scripts\activate
pip install -r requirements.txt
uvicorn main:app --reload
```

Open **http://localhost:8000/docs** to verify it's running.

---

## 📱 STEP 4 — Flutter Setup

```bash
cd studyforge_v2/flutter_app
cp .env.example .env
# Fill in: API_BASE_URL, SUPABASE_URL, SUPABASE_ANON_KEY

flutter pub get
flutter run
```

---

## 🌟 Features

### User Features
| Feature | Description |
|---------|-------------|
| **Auth** | Email/password sign up & sign in via Supabase |
| **Dashboard** | Stats (sessions, questions, flashcards, accuracy) with animated number roll |
| **Upload** | PDF/DOCX upload with drag-and-drop + animated step progress |
| **AI Study Materials** | Summary, MCQ quiz with score tracker, 3D flip flashcards |
| **Profile** | Edit name & bio, view account info |
| **History** | Sessions grouped by date with search/filter |
| **Spaced Repetition** | Due-for-review section on home screen with dedicated review screen |
| **Analytics** | Per-user accuracy trends and weekly stats |
| **Notifications** | In-app notification centre with unread badge dot |
| **Shared Sessions** | Browse and study sessions shared by other users |

### Navigation
| Feature | Description |
|---------|-------------|
| **Bottom nav bar** | Persistent `AppBottomNav` widget with `AppNavTab` enum — switches between Home, Upload, Review, Analytics, and Shared screens |

### Dashboard Features (home_screen)
| Feature | Description |
|---------|-------------|
| **Animated stat cards** | Numbers roll from 0 → value on load (TweenAnimationBuilder) |
| **Reactive greeting** | Updates every minute on hour boundary (Good morning / afternoon / evening) |
| **Last synced timestamp** | Shows "Synced 2m ago" below the header |
| **Notifications bell** | Icon button in the header; red dot badge shows unread count; tapping opens `NotificationsScreen` and refreshes the count on return |
| **Stat cards — Questions & Flashcards** | All-time totals computed locally from loaded sessions; delta pill shows week-over-week change (e.g. "+5 new this week") in green/red |
| **Stat card — Accuracy rate** | Shows average quiz accuracy as a percentage with an animated `LinearProgressIndicator` bar; sourced from `/analytics/summary` |
| **Stat card — Docs processed** | Running count of all sessions with "PDFs, links & more" label |
| **Search & filter** | Live client-side search across session names and summaries |
| **Grouped sessions** | Sessions bucketed into This week / This month / Older |
| **Long-press context menu** | Hold any tile → Rename or Delete |
| **Swipe to delete** | Swipe left on any tile to delete with confirmation |
| **Rename sessions** | Rename dialog syncs to backend via PATCH /results/{id} |
| **Retry failed sessions** | Pending tiles show a Retry button — re-runs AI generation inline |
| **Continue where you left off card** | Amber-bordered card showing the most recent non-pending session with quick-jump buttons to Review Q&A and Flashcards |
| **Due for review section** | Bottom card listing up to 3 sessions with flashcard counts and colour-coded dots; "Start review session" button opens `SrReviewScreen` |
| **Tappable stat cards** | Tap Sessions card → scrolls to the sessions list |
| **Haptic feedback** | Light impact on tile tap, medium on long-press / delete |
| **Offline banner** | Red bar slides in when connectivity is lost |
| **Confetti on first upload** | 🎉 Fires when the very first session is created |

### Upload Features (upload_screen)
| Feature | Description |
|---------|-------------|
| **Drag-and-drop zone** | DragTarget with animated dashed border on hover |
| **Animated step pills** | Upload → Extract → Generate → Done light up in sequence |
| **Offline banner** | Disables the CTA button and shows a warning when offline |
| **Confetti burst** | Fires after the Done step on first upload |

### Quiz Features (results_screen)
| Feature | Description |
|---------|-------------|
| **Live score tracker** | Answered / correct / wrong pills update as you tap answers |
| **Progress ring** | Animated CustomPainter arc shows % correct after submission |
| **Streak flame 🔥** | Tracks longest consecutive correct run, shown in amber banner |
| **Try Again** | Resets all answers and score for another attempt |

### Flashcard Features (results_screen)
| Feature | Description |
|---------|-------------|
| **True 3D flip** | Matrix4.rotateY with perspective — real 3D, not a crossfade |
| **Per-card controller** | Each card has its own AnimationController — flips independently |
| **Front / back labels** | TERM pill on front, ANSWER pill on back |

### Admin Features (your account only)
| Feature | Description |
|---------|-------------|
| **Dashboard** | Total users, total sessions, sessions today, recent signups |
| **User List** | Paginated + searchable list of all users |
| **User Detail** | View any user's profile + all their sessions |
| **Delete Sessions** | Swipe-to-delete any user's study session |
| **Toggle Admin** | Promote/demote any user to admin |

---

## 🌐 API Reference

### Results Endpoints
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/results/` | All results for a user (`?user_id=`) |
| GET | `/results/{id}` | Single result |
| DELETE | `/results/{id}` | Delete a session |
| PATCH | `/results/{id}` | Rename a session (`{"file_name": "new name"}`) |
| POST | `/retry/{id}` | Re-extract text + reset to pending for retry |

### Profile Endpoints
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/profile/{user_id}` | Get user profile |
| PUT | `/profile/{user_id}` | Update name/bio |
| GET | `/profile/{user_id}/history` | Get study history |

### Upload & Process Endpoints
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/upload/` | Upload file, extract text, save stub row |
| POST | `/process/` | Run AI generation on extracted text |

### Analytics & Stats Endpoints
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/analytics/weekly?user_id=` | **NEW** — Questions & flashcards created this week vs last week (deltas) |
| GET | `/analytics/summary?user_id=` | **NEW** — Average accuracy rate across all completed quizzes |

### Notifications Endpoints
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/notifications?user_id=` | **NEW** — List all notifications for a user (includes `is_read` flag) |

### Admin Endpoints (requires admin token)
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/admin/stats` | Platform stats |
| GET | `/admin/users` | List all users (paginated) |
| GET | `/admin/users/{id}` | One user + all sessions |
| DELETE | `/admin/results/{id}` | Delete a session |
| PUT | `/admin/users/{id}/toggle-admin` | Promote/demote admin |

---

## 📦 Flutter Dependencies

```yaml
dependencies:
  supabase_flutter: ^2.5.3   # Auth + DB + Storage
  file_picker: ^8.0.3         # File selection
  dio: ^5.4.3+1               # HTTP client
  google_fonts: ^6.2.1        # Typography
  flutter_animate: ^4.5.0     # Animations
  fluttertoast: ^8.2.4        # Toast messages
  flutter_dotenv: ^5.1.0      # .env loading
  shared_preferences: ^2.2.3  # Local storage
  image_picker: ^1.1.2        # Avatar upload
  confetti: ^0.7.0            # ← NEW: first-upload celebration
  connectivity_plus: ^6.0.3   # ← NEW: offline banner
```

Run `flutter pub get` after updating `pubspec.yaml`.

---

## ✅ Quick Checklist

```
Supabase:
□ Project created
□ supabase_setup.sql executed  (includes file_name column)
□ supabase_profiles_admin.sql executed
□ Storage bucket "studyforge-files" created as Public
□ Your account set as admin: UPDATE profiles SET is_admin=true WHERE email='you@...'

Backend:
□ backend/.env filled (SUPABASE_URL + SUPABASE_SERVICE_KEY + HF_API_TOKEN)
□ venv created + pip install -r requirements.txt
□ uvicorn running on port 8000
□ httpx installed (used by POST /retry): pip install httpx

Flutter:
□ flutter_app/.env filled (API_BASE_URL + SUPABASE_URL + SUPABASE_ANON_KEY)
□ flutter pub get  (picks up confetti + connectivity_plus)
□ Emulator running + flutter run
```

---

## 🆘 Troubleshooting

| Problem | Fix |
|---------|-----|
| Admin panel not showing | Run the SQL to set is_admin=true for your account |
| Profile not created on signup | Make sure the trigger was created (run Script 2) |
| `403 Admin access required` | Your account's is_admin is still false in DB |
| HF API 503 | Model cold-starting — wait 30s and retry |
| `Connection refused` | Make sure uvicorn backend is running |
| Rename not saving | Check `file_name` column exists in results table |
| Retry button not working | Make sure `httpx` is installed in the backend venv |
| Confetti not firing | Pass `isFirstUpload: true` when sessions list is empty |
| Offline banner not showing | Add `connectivity_plus` to pubspec and run `flutter pub get` |
| Drag-and-drop not working | Only works on desktop/web — mobile uses the tap picker |
| Stats showing 0 / accuracy blank | Implement `/analytics/weekly` and `/analytics/summary` endpoints in backend |
| Notifications bell always empty | Implement `/notifications` endpoint returning `[{id, is_read, ...}]` |
| Bottom nav not switching screens | Ensure `AppBottomNav` receives `currentTab` and `onTabChanged` and each `AppNavTab` pushes the correct screen |
| "Continue" card not showing | Card only appears when at least one non-pending session exists |
| Due for review section missing | Requires at least one session with flashcards; uses first 3 parsed sessions |

---

## 🚀 Free Deployment

**Backend → Render.com:**
```
Build: pip install -r requirements.txt
Start: uvicorn main:app --host 0.0.0.0 --port $PORT
```

**Flutter → APK:**
```bash
flutter build apk --release
```

---

## 📝 Changelog

### v2.1.0 — Latest
**Home screen**
- Animated stat number roll on load
- Reactive greeting (updates on hour boundary)
- Last synced timestamp
- Notifications bell with unread count badge; opens `NotificationsScreen`
- Stat cards for Questions, Flashcards, Docs processed, and Accuracy rate
- Week-over-week delta indicators on Questions and Flashcards cards (green/red)
- Accuracy rate card with animated `LinearProgressIndicator` bar
- "Continue where you left off" amber card for the most recent session
- Due-for-review section with spaced-repetition card list and "Start review session" CTA
- Search / filter bar with live client-side filtering
- Sessions grouped by date (This week / This month / Older)
- Long-press context menu (Rename + Delete)
- Swipe-to-delete on tiles
- Rename now persists to backend via PATCH /results/{id}
- Retry button on pending/failed tiles — re-runs AI inline
- Tappable Sessions stat card → scrolls to list
- Haptic feedback on tile tap and long-press
- Offline banner (connectivity_plus)
- Confetti on first upload
- Persistent bottom navigation bar (`AppBottomNav`)

**New screens**
- `NotificationsScreen` — in-app notification list with read/unread state
- `SrReviewScreen` — spaced repetition flashcard review session
- `AnalyticsScreen` — accuracy trends and weekly activity
- `SharedSessionsScreen` — browse sessions shared by other users

**Upload screen**
- Drag-and-drop file zone with animated dashed border
- 4-step animated progress pills (Upload → Extract → Generate → Done)
- Offline banner disables CTA

**Results screen — Quiz**
- Live score tracker (answered / correct / wrong pills)
- Progress ring (CustomPainter arc, animated on submit)
- Streak flame tracker 🔥

**Results screen — Flashcards**
- True 3D flip animation (Matrix4.rotateY + perspective)
- Per-card independent AnimationController

**Backend**
- `PATCH /results/{id}` — rename endpoint
- `POST /retry/{id}` — re-extract + reset + return text for retry
- `GET /analytics/weekly` — weekly question & flashcard delta stats
- `GET /analytics/summary` — average accuracy rate
- `GET /notifications` — user notification list

**Packages added**
- `confetti: ^0.7.0`
- `connectivity_plus: ^6.0.3`

### v2.0.0
- Initial release with Auth, Upload, Quiz, Flashcards, Profile, Admin panel

---

## 📝 License
MIT — free for personal and commercial use.