"""
utils/supabase_client.py
Shared Supabase client instance used across all backend modules.
"""

import os
from supabase import create_client, Client

_client: Client | None = None


def get_supabase() -> Client:
    """Lazily create and return the shared Supabase client."""
    global _client
    if _client is None:
        url = os.getenv("SUPABASE_URL", "")
        key = os.getenv("SUPABASE_SERVICE_KEY", "")

        if not url or not key:
            raise RuntimeError(
                "SUPABASE_URL and SUPABASE_SERVICE_KEY must be set in your .env file.\n"
                "Get them from: Supabase Dashboard → Project Settings → API"
            )

        _client = create_client(url, key)
        print("✅ Supabase client initialised")

    return _client
