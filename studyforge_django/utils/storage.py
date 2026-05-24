"""
utils/storage.py
Replaces Supabase Storage.
- Development: saves files to MEDIA_ROOT/uploads/<user_id>/
- Production:  set CLOUDINARY_* vars to use Cloudinary instead (free 25 GB)
"""

import os
import uuid
from pathlib import Path
from django.conf import settings


def save_uploaded_file(file_bytes: bytes, filename: str, user_id: str) -> str:
    """
    Save file bytes to local storage (or Cloudinary if configured).
    Returns a public URL string.
    """
    # Try Cloudinary first if configured
    cloud_name = getattr(settings, "CLOUDINARY_CLOUD_NAME", "") or os.getenv("CLOUDINARY_CLOUD_NAME", "")
    if cloud_name:
        return _save_to_cloudinary(file_bytes, filename, user_id)

    return _save_to_local(file_bytes, filename, user_id)


def _save_to_local(file_bytes: bytes, filename: str, user_id: str) -> str:
    """Save to MEDIA_ROOT/uploads/<user_id>/<uuid>_<filename>."""
    upload_dir = Path(settings.MEDIA_ROOT) / "uploads" / user_id
    upload_dir.mkdir(parents=True, exist_ok=True)

    ext       = Path(filename).suffix.lower()
    safe_name = f"{uuid.uuid4().hex}{ext}"
    full_path = upload_dir / safe_name

    with open(full_path, "wb") as f:
        f.write(file_bytes)

    # Build a relative URL — served by Django in DEBUG or nginx in prod
    rel_path = full_path.relative_to(settings.MEDIA_ROOT)
    return f"{settings.MEDIA_URL}{rel_path}"


def _save_to_cloudinary(file_bytes: bytes, filename: str, user_id: str) -> str:
    """Upload to Cloudinary and return the secure URL."""
    try:
        import cloudinary
        import cloudinary.uploader

        cloudinary.config(
            cloud_name = os.getenv("CLOUDINARY_CLOUD_NAME"),
            api_key    = os.getenv("CLOUDINARY_API_KEY"),
            api_secret = os.getenv("CLOUDINARY_API_SECRET"),
        )

        import io
        result = cloudinary.uploader.upload(
            io.BytesIO(file_bytes),
            folder          = f"studyforge/{user_id}",
            resource_type   = "raw",
            use_filename    = True,
            unique_filename = True,
        )
        return result.get("secure_url", "")
    except Exception as e:
        print(f"⚠️  Cloudinary upload failed, falling back to local: {e}")
        return _save_to_local(file_bytes, filename, user_id)
