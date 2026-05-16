# 📚 Studyforge V2 — AI-Powered Study Assistant

> Upload a PDF or DOCX → AI generates a **Summary**, **Quiz**, and **Flashcards** instantly.
> Includes **User Profiles**, **Study History**, and a full **Admin Panel**.
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
│   │   ├── results.py       # fetch results
│   │   └── profile.py       # profile CRUD + admin endpoints
│   └── utils/
│       ├── supabase_client.py
│       ├── supabase_helpers.py
│       ├── file_extractor.py
│       └── ai_generator.py
│
└── flutter_app/
    ├── pubspec.yaml
    ├── .env.example
    └── lib/
        ├── main.dart
        ├── core/constants.dart
        ├── models/
        │   ├── study_result.dart
        │   └── profile.dart          ← NEW
        ├── services/
        │   ├── auth_service.dart
        │   ├── api_service.dart
        │   └── profile_service.dart  ← NEW
        ├── widgets/sf_logo.dart
        └── screens/
            ├── login_screen.dart
            ├── home_screen.dart      (updated — profile + admin buttons)
            ├── upload_screen.dart
            ├── results_screen.dart
            ├── profile_screen.dart   ← NEW
            └── admin/
                ├── admin_dashboard_screen.dart    ← NEW
                ├── admin_users_screen.dart        ← NEW
                └── admin_user_detail_screen.dart  ← NEW
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
| **Dashboard** | Stats (sessions, questions, flashcards), recent sessions |
| **Upload** | PDF/DOCX upload with animated progress |
| **AI Study Materials** | Summary, MCQ quiz, flip flashcards |
| **Profile** | Edit name & bio, view account info |
| **History** | Full list of past study sessions with dates |

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

### Profile Endpoints
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/profile/{user_id}` | Get user profile |
| PUT | `/profile/{user_id}` | Update name/bio |
| GET | `/profile/{user_id}/history` | Get study history |

### Admin Endpoints (requires admin token)
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/admin/stats` | Platform stats |
| GET | `/admin/users` | List all users (paginated) |
| GET | `/admin/users/{id}` | One user + all sessions |
| DELETE | `/admin/results/{id}` | Delete a session |
| PUT | `/admin/users/{id}/toggle-admin` | Promote/demote admin |

---

## ✅ Quick Checklist

```
Supabase:
□ Project created
□ supabase_setup.sql executed
□ supabase_profiles_admin.sql executed
□ Storage bucket "studyforge-files" created as Public
□ Your account set as admin: UPDATE profiles SET is_admin=true WHERE email='you@...'

Backend:
□ backend/.env filled (SUPABASE_URL + SUPABASE_SERVICE_KEY + HF_API_TOKEN)
□ venv created + pip install -r requirements.txt
□ uvicorn running on port 8000

Flutter:
□ flutter_app/.env filled (API_BASE_URL + SUPABASE_URL + SUPABASE_ANON_KEY)
□ flutter pub get
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

## 🗂 Project Structure

```
studyforge_v2/
├── backend/
│   ├── main.py                    # FastAPI entry point
│   ├── requirements.txt
│   ├── run.sh                     # One-command start script
│   ├── .env.example               # Copy → .env, fill in values
│   ├── routers/
│   │   ├── auth.py                # POST /auth/signup|signin|signout
│   │   ├── upload.py              # POST /upload
│   │   ├── process.py             # POST /process  (AI generation)
│   │   └── results.py             # GET  /results
│   └── utils/
│       ├── supabase_client.py     # Shared Supabase client
│       ├── supabase_helpers.py    # DB + Storage helpers
│       ├── file_extractor.py      # PDF + DOCX text extraction
│       └── ai_generator.py        # Hugging Face API calls
│
└── flutter_app/
    ├── pubspec.yaml
    ├── .env.example               # Copy → .env, fill in values
    └── lib/
        ├── main.dart              # Entry point + Supabase init
        ├── core/
        │   └── constants.dart     # Colors, fonts, theme
        ├── models/
        │   └── study_result.dart
        ├── services/
        │   ├── auth_service.dart  # Supabase Auth wrapper
        │   └── api_service.dart   # FastAPI HTTP client
        ├── widgets/
        │   └── sf_logo.dart       # Animated logo widget
        └── screens/
            ├── login_screen.dart
            ├── home_screen.dart
            ├── upload_screen.dart
            └── results_screen.dart
```

---

## 🆓 Free Services Used

| Service | Purpose | Free Limit |
|---------|---------|-----------|
| **Supabase** | Auth + Database + Storage | 500 MB DB, 1 GB Storage, 50k MAU |
| **Hugging Face** | AI text generation | ~30k requests/month |
| **FastAPI** | Backend API | Self-hosted (free) |
| **Flutter** | Mobile frontend | Free & open source |

---

## 🔥 STEP 1 — Supabase Setup (5 minutes)

### 1a. Create project
1. Go to **https://supabase.com** → Sign up (free, no credit card)
2. Click **"New project"** → name it `studyforge`
3. Choose a region close to you → **Create project** (takes ~1 min)

### 1b. Create the database table
1. In Supabase dashboard → left sidebar → **SQL Editor**
2. Click **"New query"** → paste this SQL → click **Run**:

```sql
-- Create results table
create table results (
    id          uuid primary key default gen_random_uuid(),
    user_id     text not null,
    file_url    text,
    summary     text,
    quiz        jsonb default '[]',
    flashcards  jsonb default '[]',
    created_at  timestamptz default now()
);

-- Enable Row Level Security
alter table results enable row level security;

-- Allow users to only access their own data
create policy "Users manage own results"
    on results for all
    using  (auth.uid()::text = user_id)
    with check (auth.uid()::text = user_id);
```

### 1c. Create Storage bucket
1. Left sidebar → **Storage** → **New bucket**
2. Name: `studyforge-files`
3. Toggle **Public bucket** ON → **Create bucket**

### 1d. Get your API keys
1. Left sidebar → **Project Settings** → **API**
2. Copy:
   - **Project URL** → `SUPABASE_URL`
   - **anon/public key** → `SUPABASE_ANON_KEY` (for Flutter)
   - **service_role key** → `SUPABASE_SERVICE_KEY` (for backend — keep secret!)

---

## 🤗 STEP 2 — Hugging Face Token (2 minutes)

1. Go to **https://huggingface.co** → Sign up (free)
2. Click your avatar → **Settings** → **Access Tokens**
3. Click **"New token"** → Name: `studyforge` → Role: **Read** → **Generate**
4. Copy the token (starts with `hf_`) — you only see it once!

---

## 🐍 STEP 3 — Backend Setup

### 3a. Create the .env file
```bash
cd studyforge_v2/backend
cp .env.example .env
```

Open `.env` and fill in:
```
SUPABASE_URL=https://YOUR_PROJECT_ID.supabase.co
SUPABASE_SERVICE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
HF_API_TOKEN=hf_your_token_here
```

### 3b. Install Python dependencies
```bash
# Windows
python -m venv venv
venv\Scripts\activate
pip install -r requirements.txt

# Mac / Linux
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### 3c. Run the backend
```bash
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

Or just run:
```bash
bash run.sh
```

✅ Open **http://localhost:8000/docs** — you should see the Swagger UI.

**Keep this terminal open** while using the app.

---

## 📱 STEP 4 — Flutter App Setup

### 4a. Create the .env file
```bash
cd studyforge_v2/flutter_app
cp .env.example .env
```

Open `.env` and fill in:
```
API_BASE_URL=http://10.0.2.2:8000
SUPABASE_URL=https://YOUR_PROJECT_ID.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

> ⚠️ Use `http://10.0.2.2:8000` for Android emulator
> Use `http://localhost:8000` for iOS simulator
> Use your machine's local IP (e.g. `http://192.168.1.x:8000`) for a real device

### 4b. Install Flutter dependencies
```bash
flutter pub get
```

### 4c. Run the app
```bash
# Make sure an emulator is running first!
flutter run
```

---

## ✅ Quick Checklist

```
Backend:
□ Supabase project created
□ SQL table created (results)
□ Storage bucket created (studyforge-files) — set to Public
□ backend/.env filled with SUPABASE_URL + SUPABASE_SERVICE_KEY + HF_API_TOKEN
□ Python venv created and dependencies installed
□ Backend running on port 8000

Flutter:
□ flutter_app/.env filled with API_BASE_URL + SUPABASE_URL + SUPABASE_ANON_KEY
□ flutter pub get run successfully
□ Android/iOS emulator running
□ flutter run executed
```

---

## 🌐 API Reference

### `POST /auth/signup`
```json
{ "email": "user@example.com", "password": "password123" }
```

### `POST /auth/signin`
```json
{ "email": "user@example.com", "password": "password123" }
```
Returns: `{ "access_token": "...", "user_id": "...", "email": "..." }`

### `POST /upload/`
Form data: `file` (PDF/DOCX), `user_id` (string)
Returns: `{ "result_id": "...", "extracted_text": "...", "file_url": "..." }`

### `POST /process/`
```json
{
  "result_id": "uuid",
  "extracted_text": "...",
  "user_id": "uuid",
  "num_quiz": 5,
  "num_flashcards": 8
}
```
Returns: `{ "summary": "...", "quiz": [...], "flashcards": [...] }`

### `GET /results/{result_id}`
Returns the full study result.

### `GET /results/?user_id={uid}`
Returns all results for a user.

---

## 🆘 Troubleshooting

| Problem | Fix |
|---------|-----|
| `SUPABASE_URL not set` | Check your `backend/.env` file |
| `Connection refused` in app | Make sure `uvicorn` is running |
| `10.0.2.2` not working | Use your PC's local IP for real devices |
| HF API returns 503 | Model is cold-starting — wait 30s and retry |
| `No text extracted` from PDF | Use a text-based PDF, not a scanned image |
| `flutter pub get` fails | Run `flutter doctor` to check Flutter install |
| Storage upload fails | Check bucket is set to **Public** in Supabase |

---

## 🚀 Free Deployment

### Backend → Render.com (free)
1. Push `backend/` to a GitHub repo
2. Go to **render.com** → New Web Service → connect your repo
3. Build command: `pip install -r requirements.txt`
4. Start command: `uvicorn main:app --host 0.0.0.0 --port $PORT`
5. Add environment variables in Render dashboard

### Flutter → Android APK
```bash
flutter build apk --release
# APK is at: build/app/outputs/flutter-apk/app-release.apk
```

---

## 📝 License
MIT — free for personal and commercial use.
#   S t u d y F o r g e  
 