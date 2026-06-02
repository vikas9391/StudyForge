#!/usr/bin/env bash
set -e

echo "=== Tesseract version ==="
tesseract --version

echo "=== Installing Python dependencies ==="
pip install -r requirements.txt

echo "=== Collecting static files ==="
python manage.py collectstatic --noinput

echo "=== Running migrations ==="
python manage.py migrate

echo "=== Creating default admin ==="
python manage.py create_default_admin

echo "=== Build complete ==="