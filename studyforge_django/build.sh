#!/usr/bin/env bash
set -e

echo "=== Installing system dependencies ==="
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
    tesseract-ocr \
    tesseract-ocr-eng \
    poppler-utils

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