from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from django.shortcuts import get_object_or_404

from .models import Notification


class NotificationListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, user_id):
        """GET /notifications/{user_id}/ — list all notifications."""
        if str(request.user.id) != str(user_id):
            from rest_framework.exceptions import PermissionDenied
            raise PermissionDenied()

        notes = Notification.objects.filter(user=request.user)
        return Response({
            "notifications": [
                {
                    "id":         str(n.id),
                    "message":    n.message,
                    "is_read":    n.is_read,
                    "created_at": n.created_at.isoformat(),
                }
                for n in notes
            ],
            "unread_count": notes.filter(is_read=False).count(),
        })


class NotificationMarkReadView(APIView):
    permission_classes = [IsAuthenticated]

    def patch(self, request, notification_id):
        """PATCH /notifications/{id}/read/ — mark one notification as read."""
        note = get_object_or_404(Notification, id=notification_id, user=request.user)
        note.is_read = True
        note.save()
        return Response({"id": str(note.id), "is_read": True})


class NotificationMarkAllReadView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, user_id):
        """POST /notifications/{user_id}/read-all/ — mark all as read."""
        if str(request.user.id) != str(user_id):
            from rest_framework.exceptions import PermissionDenied
            raise PermissionDenied()

        count = Notification.objects.filter(user=request.user, is_read=False).update(is_read=True)
        return Response({"message": f"Marked {count} notifications as read."})


class NotificationDeleteView(APIView):
    permission_classes = [IsAuthenticated]

    def delete(self, request, notification_id):
        """DELETE /notifications/{id}/ — delete a notification."""
        note = get_object_or_404(Notification, id=notification_id, user=request.user)
        note.delete()
        return Response({"message": "Notification deleted."})