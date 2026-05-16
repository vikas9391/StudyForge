"""
Studyforge Backend — main.py
FastAPI app using Supabase (free tier) for auth, database, and storage.
Run with: uvicorn main:app --reload
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

# Import route handlers
from routers import auth, upload, process, results, profile

app = FastAPI(
    title="Studyforge API",
    description="AI-powered study assistant — Supabase edition",
    version="2.0.0",
)

# Allow Flutter app to connect from any origin (tighten in production)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Register all routers
app.include_router(auth.router,    prefix="/auth",    tags=["Auth"])
app.include_router(upload.router,  prefix="/upload",  tags=["Upload"])
app.include_router(process.router, prefix="/process", tags=["Process"])
app.include_router(results.router, prefix="/results", tags=["Results"])
app.include_router(profile.router, prefix="",         tags=["Profile & Admin"])


@app.get("/")
def root():
    """Health-check endpoint."""
    return {"status": "ok", "message": "Studyforge API is running 🚀"}
