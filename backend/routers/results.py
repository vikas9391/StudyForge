"""
routers/results.py
GET /results/{result_id}  — fetch one saved result
GET /results/?user_id=    — fetch all results for a user (last 20)
"""

from fastapi import APIRouter, HTTPException, Query
from utils.supabase_helpers import get_result, get_results_by_user

router = APIRouter()


@router.get("/{result_id}")
def fetch_result(result_id: str):
    """Retrieve a specific study-material result by its UUID."""
    data = get_result(result_id)
    if data is None:
        raise HTTPException(404, f"No result found with ID '{result_id}'.")
    return {"result_id": result_id, **data}


@router.get("/")
def fetch_user_results(
    user_id: str = Query(..., description="Supabase user UID")
):
    """Return the 20 most recent results for the given user."""
    results = get_results_by_user(user_id)
    return {"user_id": user_id, "count": len(results), "results": results}
