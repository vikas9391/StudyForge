"""
apps/results/views.py
Replaces routers/upload.py + routers/process.py + routers/results.py
"""

import os
import httpx

from rest_framework import status
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from rest_framework.parsers import MultiPartParser, FormParser, JSONParser
from django.shortcuts import get_object_or_404

from .models import Result
from .serializers import ResultSerializer, ResultListSerializer
from utils.file_extractor import extract_text, MAX_FILE_SIZE_MB
from utils.ai_generator import generate_summary, generate_quiz, generate_flashcards
from utils.storage import save_uploaded_file


ALLOWED_CONTENT_TYPES = {
    "application/pdf",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "application/msword",
}


# ── POST /upload/ ──────────────────────────────────────────────────────────────

class UploadView(APIView):
    permission_classes = [IsAuthenticated]
    parser_classes     = [MultiPartParser, FormParser]

    def post(self, request):
        """
        Step 1 of 2 — upload file, extract text, save pending stub.
        Returns result_id + extracted_text (pass both to POST /process/).
        """
        file = request.FILES.get("file")
        if not file:
            return Response({"detail": "No file provided."}, status=400)

        if file.content_type not in ALLOWED_CONTENT_TYPES:
            return Response(
                {"detail": f"Unsupported file type. Upload a PDF or DOCX."},
                status=400,
            )

        file_bytes = file.read()
        size_mb = len(file_bytes) / (1024 * 1024)
        if size_mb > MAX_FILE_SIZE_MB:
            return Response(
                {"detail": f"File is {size_mb:.1f} MB — max is {MAX_FILE_SIZE_MB} MB."},
                status=413,
            )

        try:
            extracted_text = extract_text(file.name, file_bytes)
        except ValueError as e:
            return Response({"detail": str(e)}, status=422)

        # Save file to local/cloud storage
        file_url = save_uploaded_file(file_bytes, file.name, str(request.user.id))

        # Save pending stub row
        result = Result.objects.create(
            user      = request.user,
            file_url  = file_url,
            file_name = file.name,
            summary   = "__pending__",
            quiz      = [],
            flashcards= [],
        )

        return Response({
            "result_id":      str(result.id),
            "file_url":       file_url,
            "char_count":     len(extracted_text),
            "extracted_text": extracted_text,
            "message":        "Uploaded! Call POST /process/ to generate study materials.",
        }, status=status.HTTP_201_CREATED)


# ── POST /process/ ─────────────────────────────────────────────────────────────

class ProcessView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        """
        Step 2 of 2 — generate AI study materials, update the result row.
        """
        result_id      = request.data.get("result_id")
        extracted_text = request.data.get("extracted_text", "")
        num_quiz       = max(5, min(10, int(request.data.get("num_quiz", 5))))
        num_cards      = max(4, min(15, int(request.data.get("num_flashcards", 8))))

        if not extracted_text.strip():
            return Response({"detail": "extracted_text cannot be empty."}, status=400)

        result = get_object_or_404(Result, id=result_id, user=request.user)

        errors = []

        try:
            summary = generate_summary(extracted_text)
        except Exception as e:
            summary = "Summary generation failed. Please retry."
            errors.append(f"summary: {e}")

        try:
            quiz = generate_quiz(extracted_text, num_questions=num_quiz)
        except Exception as e:
            quiz = []
            errors.append(f"quiz: {e}")

        try:
            flashcards = generate_flashcards(extracted_text, num_cards=num_cards)
        except Exception as e:
            flashcards = []
            errors.append(f"flashcards: {e}")

        result.summary    = summary
        result.quiz       = quiz
        result.flashcards = flashcards
        result.save()

        resp = {
            "result_id":  str(result.id),
            "summary":    summary,
            "quiz":       quiz,
            "flashcards": flashcards,
            "message":    "Processing complete ✅",
        }
        if errors:
            resp["warnings"] = errors
        return Response(resp)


# ── GET/DELETE/PATCH /results/ ─────────────────────────────────────────────────

class ResultListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        """GET /results/?user_id= — last 20 results for authenticated user."""
        results = Result.objects.filter(user=request.user)[:20]
        return Response({
            "user_id": str(request.user.id),
            "count":   results.count(),
            "results": ResultListSerializer(results, many=True).data,
        })


class ResultDetailView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, result_id):
        """GET /results/{id}/ — fetch one result."""
        result = get_object_or_404(Result, id=result_id, user=request.user)
        return Response(ResultSerializer(result).data)

    def delete(self, request, result_id):
        """DELETE /results/{id}/ — delete a session."""
        result = get_object_or_404(Result, id=result_id, user=request.user)
        result.delete()
        return Response({"message": f"Result '{result_id}' deleted."})

    def patch(self, request, result_id):
        """PATCH /results/{id}/ — rename a session."""
        name = (request.data.get("file_name") or "").strip()
        if not name:
            return Response({"detail": "file_name must not be empty."}, status=422)
        if len(name) > 200:
            return Response({"detail": "file_name must be 200 characters or fewer."}, status=422)

        result = get_object_or_404(Result, id=result_id, user=request.user)
        result.file_name = name
        result.save()
        return Response({
            "result_id": str(result.id),
            "file_name": name,
            "message":   "Session renamed successfully.",
        })


# ── POST /retry/{id}/ ──────────────────────────────────────────────────────────

class RetryView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, result_id):
        """
        Re-download the stored file and re-extract text so the client
        can call POST /process/ again without re-uploading.
        """
        result = get_object_or_404(Result, id=result_id, user=request.user)
        file_url = request.data.get("file_url") or result.file_url

        if not file_url:
            return Response(
                {"detail": "No file_url stored. Please upload the document again."},
                status=422,
            )

        try:
            resp = httpx.get(file_url, timeout=30)
            resp.raise_for_status()
            file_bytes = resp.content
        except Exception as e:
            return Response({"detail": f"Could not download stored file: {e}"}, status=502)

        file_name = result.file_name or file_url.split("/")[-1]
        try:
            extracted_text = extract_text(file_name, file_bytes)
        except ValueError as e:
            return Response({"detail": str(e)}, status=422)

        # Reset to pending
        result.summary    = "__pending__"
        result.quiz       = []
        result.flashcards = []
        result.save()

        return Response({
            "result_id":      str(result.id),
            "extracted_text": extracted_text,
            "char_count":     len(extracted_text),
            "message":        "Text extracted. Call POST /process/ to regenerate.",
        })
