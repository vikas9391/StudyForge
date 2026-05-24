"""
apps/shared/views.py
Mirrors routers/shared.py exactly — shared/public study sessions.
"""

from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated, AllowAny
from django.shortcuts import get_object_or_404

from apps.results.models import Result


class VisibilityView(APIView):
    permission_classes = [IsAuthenticated]

    def patch(self, request, result_id):
        """PATCH /shared/{result_id}/visibility/ — toggle public/private."""
        result = get_object_or_404(Result, id=result_id, user=request.user)
        result.is_public = bool(request.data.get("is_public", False))
        result.save()
        status_str = "public" if result.is_public else "private"
        return Response({
            "result_id": str(result.id),
            "is_public": result.is_public,
            "message":   f"Session is now {status_str}.",
        })


class BrowsePublicView(APIView):
    permission_classes = [AllowAny]

    def get(self, request):
        """GET /shared/browse/ — paginated list of public sessions."""
        search = request.query_params.get("search")
        limit  = min(int(request.query_params.get("limit", 20)), 50)
        offset = int(request.query_params.get("offset", 0))

        qs = Result.objects.filter(is_public=True).order_by("-clone_count")
        if search:
            qs = qs.filter(file_name__icontains=search)

        sessions = []
        for s in qs[offset:offset + limit]:
            sessions.append({
                "id":          str(s.id),
                "file_name":   s.file_name or "Untitled",
                "summary":     (s.summary or "")[:200],
                "quiz_count":  len(s.quiz or []),
                "card_count":  len(s.flashcards or []),
                "clone_count": s.clone_count,
                "created_at":  s.created_at.isoformat(),
            })

        return Response({
            "sessions": sessions,
            "count":    len(sessions),
            "offset":   offset,
            "limit":    limit,
        })


class FeaturedView(APIView):
    permission_classes = [AllowAny]

    def get(self, request):
        """GET /shared/featured/ — top 10 most-cloned sessions."""
        results = Result.objects.filter(is_public=True).order_by("-clone_count")[:10]
        return Response({
            "sessions": [
                {
                    "id":          str(s.id),
                    "file_name":   s.file_name or "Untitled",
                    "summary":     (s.summary or "")[:120],
                    "quiz_count":  len(s.quiz or []),
                    "card_count":  len(s.flashcards or []),
                    "clone_count": s.clone_count,
                }
                for s in results
            ]
        })


class PublicSessionDetailView(APIView):
    permission_classes = [AllowAny]

    def get(self, request, result_id):
        """GET /shared/{result_id}/ — full content of a public session."""
        result = get_object_or_404(Result, id=result_id)
        if not result.is_public:
            return Response({"detail": "This session is private."},
                            status=403)
        return Response({
            "id":          str(result.id),
            "file_name":   result.file_name or "Untitled",
            "summary":     result.summary or "",
            "quiz":        result.quiz or [],
            "flashcards":  result.flashcards or [],
            "clone_count": result.clone_count,
            "created_at":  result.created_at.isoformat(),
            "cloned_from": str(result.cloned_from) if result.cloned_from else None,
        })


class CloneSessionView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, result_id):
        """POST /shared/{result_id}/clone/ — copy public session to own library."""
        original = get_object_or_404(Result, id=result_id)
        if not original.is_public:
            return Response({"detail": "This session is private and cannot be cloned."},
                            status=403)

        new_result = Result.objects.create(
            user        = request.user,
            file_url    = original.file_url or "",
            file_name   = f"{original.file_name or 'Untitled'} (copy)",
            summary     = original.summary or "",
            quiz        = original.quiz or [],
            flashcards  = original.flashcards or [],
            is_public   = False,
            clone_count = 0,
            cloned_from = original.id,
        )

        original.clone_count += 1
        original.save()

        return Response({
            "new_result_id": str(new_result.id),
            "cloned_from":   str(result_id),
            "message":       "Session cloned to your library!",
        }, status=201)
