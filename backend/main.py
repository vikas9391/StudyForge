"""
Studyforge Backend — main.py  (V3)
FastAPI app using Supabase (free tier) for auth, database, and storage.
Run with: uvicorn main:app --reload

New in V3:
  /sr/*       — Spaced repetition (SM-2 algorithm)
  /ingest/*   — YouTube, URL, and OCR input sources
  /analytics/*— Weak-topic heatmap + accuracy over time
  /shared/*   — Public/shared study sessions
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from dotenv import load_dotenv

load_dotenv()

from routers import auth, upload, process, results, profile
from routers import spaced_repetition, ingest, analytics, shared

app = FastAPI(
    title="Studyforge API",
    description="AI-powered study assistant — V3",
    version="3.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

# V2 routers
app.include_router(auth.router,    prefix="/auth",    tags=["Auth"])
app.include_router(upload.router,  prefix="/upload",  tags=["Upload"])
app.include_router(process.router, prefix="/process", tags=["Process"])
app.include_router(results.router, prefix="/results", tags=["Results"])
app.include_router(profile.router, prefix="",         tags=["Profile & Admin"])

# V3 routers
app.include_router(spaced_repetition.router, prefix="/sr",        tags=["Spaced Repetition"])
app.include_router(ingest.router,            prefix="/ingest",     tags=["Ingest"])
app.include_router(analytics.router,         prefix="/analytics",  tags=["Analytics"])
app.include_router(shared.router,            prefix="/shared",     tags=["Shared Sessions"])


@app.get("/")
def root():
    return {"status": "ok", "message": "Studyforge API V3 is running 🚀"}