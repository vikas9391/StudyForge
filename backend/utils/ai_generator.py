"""
utils/ai_generator.py
Generates study materials using Hugging Face's FREE Inference API.

Models used (both free):
  Summary   → facebook/bart-large-cnn
  Quiz/Cards → mistralai/Mistral-7B-Instruct-v0.2

Set HF_API_TOKEN in your .env
Get a free token at: https://huggingface.co/settings/tokens
"""

import os
import re
import json
import httpx

HF_API_TOKEN   = os.getenv("HF_API_TOKEN", "")
HF_BASE_URL    = "https://api-inference.huggingface.co/models"
SUMMARY_MODEL  = "facebook/bart-large-cnn"
INSTRUCT_MODEL = "mistralai/Mistral-7B-Instruct-v0.2"
HEADERS        = {"Authorization": f"Bearer {HF_API_TOKEN}"}
TIMEOUT        = 60   # seconds — free tier can be slow on cold start


# ── Helpers ──────────────────────────────────────────────────────────────────

def _hf_post(model: str, payload: dict) -> dict:
    """POST to HF Inference API and return parsed JSON."""
    url  = f"{HF_BASE_URL}/{model}"
    resp = httpx.post(url, headers=HEADERS, json=payload, timeout=TIMEOUT)
    resp.raise_for_status()
    return resp.json()


def _truncate(text: str, max_chars: int = 3000) -> str:
    """Trim text to avoid exceeding model token limits."""
    return text[:max_chars] if len(text) > max_chars else text


# ── Summary ──────────────────────────────────────────────────────────────────

def generate_summary(text: str) -> str:
    """Generate a concise summary using BART. Falls back to first 3 sentences."""
    try:
        result = _hf_post(SUMMARY_MODEL, {
            "inputs": _truncate(text, 3000),
            "parameters": {
                "max_length": 200,
                "min_length": 60,
                "do_sample":  False,
            },
        })
        if isinstance(result, list) and result:
            return result[0].get("summary_text", "").strip()
    except Exception as e:
        print(f"⚠️  Summary API failed, using fallback: {e}")

    # Fallback: return first 3 sentences
    sentences = re.split(r'(?<=[.!?])\s+', text.strip())
    return " ".join(sentences[:3])


# ── Quiz ─────────────────────────────────────────────────────────────────────

def generate_quiz(text: str, num_questions: int = 5) -> list[dict]:
    """
    Generate MCQs using Mistral-7B-Instruct.
    Returns list of: { question, options: [A..,B..,C..,D..], answer: "A" }
    """
    prompt = f"""[INST]
Generate exactly {num_questions} multiple-choice questions from the text below.
Each question must have exactly 4 options labeled A, B, C, D.
Return ONLY valid JSON array, no extra text, no markdown:
[{{"question":"...","options":["A. ...","B. ...","C. ...","D. ..."],"answer":"A"}}]

TEXT:
{_truncate(text, 2500)}
[/INST]"""

    try:
        result = _hf_post(INSTRUCT_MODEL, {
            "inputs": prompt,
            "parameters": {
                "max_new_tokens":  1200,
                "temperature":     0.3,
                "return_full_text": False,
            },
        })
        raw = ""
        if isinstance(result, list) and result:
            raw = result[0].get("generated_text", "")
        elif isinstance(result, dict):
            raw = result.get("generated_text", "")

        match = re.search(r'\[.*\]', raw, re.DOTALL)
        if match:
            quiz = json.loads(match.group())
            validated = [
                q for q in quiz[:num_questions]
                if all(k in q for k in ("question", "options", "answer"))
            ]
            if validated:
                return validated
    except Exception as e:
        print(f"⚠️  Quiz API failed, using fallback: {e}")

    return _fallback_quiz(text, num_questions)


def _fallback_quiz(text: str, n: int) -> list[dict]:
    sentences = re.split(r'(?<=[.!?])\s+', text.strip())
    out = []
    for sent in sentences[:n]:
        words = sent.split()
        if len(words) >= 5:
            answer = words[min(4, len(words) - 1)]
            out.append({
                "question": " ".join(words[:4]) + " ___?",
                "options":  [f"A. {answer}", "B. Something else",
                             "C. Another option", "D. None of the above"],
                "answer":   "A",
            })
    return out or [{"question": "No questions generated.", "options": [], "answer": ""}]


# ── Flashcards ────────────────────────────────────────────────────────────────

def generate_flashcards(text: str, num_cards: int = 8) -> list[dict]:
    """
    Generate flashcards using Mistral-7B-Instruct.
    Returns list of: { front, back }
    """
    prompt = f"""[INST]
Generate exactly {num_cards} flashcards from the text below.
Return ONLY valid JSON array, no extra text, no markdown:
[{{"front":"key term or question","back":"definition or answer"}}]

TEXT:
{_truncate(text, 2500)}
[/INST]"""

    try:
        result = _hf_post(INSTRUCT_MODEL, {
            "inputs": prompt,
            "parameters": {
                "max_new_tokens":  1000,
                "temperature":     0.3,
                "return_full_text": False,
            },
        })
        raw = ""
        if isinstance(result, list) and result:
            raw = result[0].get("generated_text", "")
        elif isinstance(result, dict):
            raw = result.get("generated_text", "")

        match = re.search(r'\[.*\]', raw, re.DOTALL)
        if match:
            cards = json.loads(match.group())
            validated = [c for c in cards[:num_cards]
                         if "front" in c and "back" in c]
            if validated:
                return validated
    except Exception as e:
        print(f"⚠️  Flashcard API failed, using fallback: {e}")

    return _fallback_flashcards(text, num_cards)


def _fallback_flashcards(text: str, n: int) -> list[dict]:
    sentences = re.split(r'(?<=[.!?])\s+', text.strip())
    cards = [
        {"front": " ".join(s.split()[:4]) + "?", "back": s.strip()}
        for s in sentences[:n] if len(s.split()) >= 6
    ]
    return cards or [{"front": "Key concept", "back": text[:200]}]
