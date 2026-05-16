"""
routers/auth.py
POST /auth/signup  — register with email + password via Supabase Auth
POST /auth/signin  — sign in, receive JWT access token
POST /auth/signout — invalidate current session
"""

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from utils.supabase_client import get_supabase

router = APIRouter()


class AuthRequest(BaseModel):
    email:    str
    password: str


@router.post("/signup")
def signup(req: AuthRequest):
    """Create a new user account."""
    sb = get_supabase()
    try:
        res = sb.auth.sign_up({"email": req.email, "password": req.password})
        if res.user is None:
            raise HTTPException(400, "Sign-up failed. Check email/password.")
        return {
            "message": "Account created! Check your email to confirm.",
            "user_id": res.user.id,
            "email":   res.user.email,
        }
    except Exception as e:
        raise HTTPException(400, str(e))


@router.post("/signin")
def signin(req: AuthRequest):
    """Sign in and receive JWT tokens."""
    sb = get_supabase()
    try:
        res = sb.auth.sign_in_with_password(
            {"email": req.email, "password": req.password}
        )
        if res.user is None:
            raise HTTPException(401, "Invalid email or password.")
        return {
            "access_token":  res.session.access_token,
            "refresh_token": res.session.refresh_token,
            "user_id":       res.user.id,
            "email":         res.user.email,
        }
    except Exception as e:
        raise HTTPException(401, str(e))


@router.post("/signout")
def signout():
    """Sign out the current session."""
    try:
        get_supabase().auth.sign_out()
        return {"message": "Signed out successfully."}
    except Exception as e:
        raise HTTPException(400, str(e))
