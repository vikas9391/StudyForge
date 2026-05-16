"""
routers/profile.py
GET  /profile/{user_id}        — get a user's profile
PUT  /profile/{user_id}        — update name/bio
GET  /admin/users              — list all users (admin only)
GET  /admin/users/{user_id}    — get one user's full data
GET  /admin/stats              — platform-wide stats
DELETE /admin/results/{result_id} — delete a result (admin only)
"""

import os
from fastapi import APIRouter, HTTPException, Header
from pydantic import BaseModel
from typing import Optional
from utils.supabase_client import get_supabase

router = APIRouter()

ADMIN_EMAIL = os.getenv("ADMIN_EMAIL", "")   # Set in .env for extra safety


# ── Helpers ──────────────────────────────────────────────────────────────────

def _verify_admin(user_id: str) -> None:
    """Raise 403 if the user is not an admin."""
    sb   = get_supabase()
    resp = sb.table("profiles").select("is_admin").eq("id", user_id).single().execute()
    if not resp.data or not resp.data.get("is_admin"):
        raise HTTPException(403, "Admin access required.")


def _get_user_id_from_token(authorization: str) -> str:
    """Extract and verify user_id from 'Bearer <token>'."""
    if not authorization.startswith("Bearer "):
        raise HTTPException(401, "Missing or invalid Authorization header.")
    token = authorization.split(" ", 1)[1]
    sb    = get_supabase()
    try:
        user = sb.auth.get_user(token)
        return user.user.id
    except Exception:
        raise HTTPException(401, "Invalid or expired token.")


# ── Profile models ────────────────────────────────────────────────────────────

class ProfileUpdate(BaseModel):
    full_name:  Optional[str] = None
    bio:        Optional[str] = None
    avatar_url: Optional[str] = None


# ── Profile endpoints ─────────────────────────────────────────────────────────

@router.get("/profile/{user_id}")
def get_profile(user_id: str):
    """Return a user's public profile."""
    sb   = get_supabase()
    resp = sb.table("profiles").select("*").eq("id", user_id).maybe_single().execute()
    if not resp.data:
        raise HTTPException(404, f"Profile not found for user '{user_id}'.")
    return resp.data


@router.put("/profile/{user_id}")
def update_profile(
    user_id:       str,
    body:          ProfileUpdate,
    authorization: str = Header(...),
):
    """Update the authenticated user's profile."""
    token_uid = _get_user_id_from_token(authorization)
    if token_uid != user_id:
        raise HTTPException(403, "You can only update your own profile.")

    sb      = get_supabase()
    updates = {k: v for k, v in body.model_dump().items() if v is not None}
    if not updates:
        raise HTTPException(400, "No fields to update.")

    updates["updated_at"] = "now()"
    resp = sb.table("profiles").update(updates).eq("id", user_id).execute()
    return {"message": "Profile updated.", "data": resp.data[0] if resp.data else {}}


@router.get("/profile/{user_id}/history")
def get_user_history(user_id: str, authorization: str = Header(...)):
    """Return all study sessions for the authenticated user."""
    token_uid = _get_user_id_from_token(authorization)
    if token_uid != user_id:
        raise HTTPException(403, "You can only view your own history.")

    sb   = get_supabase()
    resp = (
        sb.table("results")
        .select("id, file_url, summary, created_at")
        .eq("user_id", user_id)
        .order("created_at", desc=True)
        .execute()
    )
    return {"user_id": user_id, "count": len(resp.data or []), "sessions": resp.data or []}


# ── Admin endpoints ────────────────────────────────────────────────────────────

@router.get("/admin/stats")
def admin_stats(authorization: str = Header(...)):
    """Platform-wide stats — total users, sessions, etc."""
    uid = _get_user_id_from_token(authorization)
    _verify_admin(uid)

    sb = get_supabase()

    # Total users
    users_resp = sb.table("profiles").select("id", count="exact").execute()
    total_users = users_resp.count or 0

    # Total sessions
    sessions_resp = sb.table("results").select("id", count="exact").execute()
    total_sessions = sessions_resp.count or 0

    # Sessions today
    today_resp = (
        sb.table("results")
        .select("id", count="exact")
        .gte("created_at", "now() - interval '24 hours'")
        .execute()
    )
    sessions_today = today_resp.count or 0

    # Recent 5 signups
    recent_users_resp = (
        sb.table("profiles")
        .select("id, email, full_name, created_at")
        .order("created_at", desc=True)
        .limit(5)
        .execute()
    )

    return {
        "total_users":     total_users,
        "total_sessions":  total_sessions,
        "sessions_today":  sessions_today,
        "recent_signups":  recent_users_resp.data or [],
    }


@router.get("/admin/users")
def admin_list_users(
    authorization: str = Header(...),
    page:          int = 1,
    limit:         int = 20,
):
    """Paginated list of all users with their session counts."""
    uid = _get_user_id_from_token(authorization)
    _verify_admin(uid)

    sb     = get_supabase()
    offset = (page - 1) * limit

    profiles_resp = (
        sb.table("profiles")
        .select("*")
        .order("created_at", desc=True)
        .range(offset, offset + limit - 1)
        .execute()
    )
    profiles = profiles_resp.data or []

    # Attach session count to each profile
    for p in profiles:
        count_resp = (
            sb.table("results")
            .select("id", count="exact")
            .eq("user_id", p["id"])
            .execute()
        )
        p["session_count"] = count_resp.count or 0

    total_resp = sb.table("profiles").select("id", count="exact").execute()

    return {
        "page":       page,
        "limit":      limit,
        "total":      total_resp.count or 0,
        "users":      profiles,
    }


@router.get("/admin/users/{target_user_id}")
def admin_get_user(target_user_id: str, authorization: str = Header(...)):
    """Full profile + all sessions for one user."""
    uid = _get_user_id_from_token(authorization)
    _verify_admin(uid)

    sb = get_supabase()

    profile_resp = (
        sb.table("profiles")
        .select("*")
        .eq("id", target_user_id)
        .maybe_single()
        .execute()
    )
    if not profile_resp.data:
        raise HTTPException(404, f"User '{target_user_id}' not found.")

    sessions_resp = (
        sb.table("results")
        .select("id, file_url, summary, created_at")
        .eq("user_id", target_user_id)
        .order("created_at", desc=True)
        .execute()
    )

    return {
        "profile":  profile_resp.data,
        "sessions": sessions_resp.data or [],
    }


@router.delete("/admin/results/{result_id}")
def admin_delete_result(result_id: str, authorization: str = Header(...)):
    """Hard-delete a study session (admin only)."""
    uid = _get_user_id_from_token(authorization)
    _verify_admin(uid)

    sb = get_supabase()
    sb.table("results").delete().eq("id", result_id).execute()
    return {"message": f"Result '{result_id}' deleted."}


@router.put("/admin/users/{target_user_id}/toggle-admin")
def admin_toggle_admin(target_user_id: str, authorization: str = Header(...)):
    """Promote or demote a user to/from admin."""
    uid = _get_user_id_from_token(authorization)
    _verify_admin(uid)

    sb   = get_supabase()
    resp = sb.table("profiles").select("is_admin").eq("id", target_user_id).single().execute()
    if not resp.data:
        raise HTTPException(404, "User not found.")

    new_val = not resp.data["is_admin"]
    sb.table("profiles").update({"is_admin": new_val}).eq("id", target_user_id).execute()

    return {
        "message":  f"User {'promoted to' if new_val else 'removed from'} admin.",
        "is_admin": new_val,
    }
