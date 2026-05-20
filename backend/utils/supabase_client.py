"""
utils/supabase_client.py
Supabase client — creates a fresh instance per call to avoid
HTTP/2 'Server disconnected' errors on Windows.
"""

import os
from supabase import create_client, Client


def get_supabase() -> Client:
    """Return a fresh Supabase client for every call.
    
    We intentionally do NOT cache the client globally because the
    underlying HTTP/2 connection drops after the first use on Windows,
    causing 'RemoteProtocolError: Server disconnected' on subsequent calls.
    """
    url = os.getenv("SUPABASE_URL", "")
    key = os.getenv("SUPABASE_SERVICE_KEY", "")

    if not url or not key:
        raise RuntimeError(
            "SUPABASE_URL and SUPABASE_SERVICE_KEY must be set in your .env file.\n"
            "Get them from: Supabase Dashboard → Project Settings → API"
        )

    return create_client(url, key)