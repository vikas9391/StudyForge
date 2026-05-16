#!/usr/bin/env bash
# run.sh — Start the Studyforge FastAPI backend
# Usage: bash run.sh

set -e
echo "🔧 Studyforge Backend"
echo "====================="

if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
  echo "✅ Loaded .env"
else
  echo "⚠️  No .env found — copy .env.example to .env and fill in values"
fi

if [ -z "$SUPABASE_URL" ] || [ -z "$SUPABASE_SERVICE_KEY" ]; then
  echo "⚠️  SUPABASE_URL and/or SUPABASE_SERVICE_KEY not set"
fi
if [ -z "$HF_API_TOKEN" ]; then
  echo "⚠️  HF_API_TOKEN not set — get free token at huggingface.co/settings/tokens"
fi

if [ ! -d venv ]; then
  echo "📦 Creating virtual environment..."
  python3 -m venv venv
fi

source venv/bin/activate
pip install -q -r requirements.txt

echo ""
echo "🚀 Starting on http://0.0.0.0:8000"
echo "   Swagger docs → http://localhost:8000/docs"
echo ""
uvicorn main:app --host 0.0.0.0 --port 8000 --reload
