from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from rest_framework.exceptions import PermissionDenied
from django.shortcuts import get_object_or_404
from django.contrib.auth import get_user_model
from django.utils import timezone

from .models import Notification

User = get_user_model()


def _time_label(dt):
    diff = timezone.now() - dt
    secs = diff.total_seconds()
    if secs < 60:       return 'Just now'
    if secs < 3600:     return f'{int(secs // 60)}m ago'
    if secs < 86400:    return f'{int(secs // 3600)}h ago'
    return f'{diff.days}d ago'


def _serialize(n):
    return {
        'id':         str(n.id),
        'type':       n.type,
        'title':      n.title,
        'body':       n.body,
        'is_read':    n.is_read,
        'created_at': n.created_at.isoformat(),
        'time_label': _time_label(n.created_at),
    }


class NotificationListView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, user_id):
        if str(request.user.id) != str(user_id):
            raise PermissionDenied()
        notes = Notification.objects.filter(user=request.user)
        return Response({
            'notifications': [_serialize(n) for n in notes],
            'unread_count':  notes.filter(is_read=False).count(),
        })


class NotificationMarkReadView(APIView):
    permission_classes = [IsAuthenticated]

    def patch(self, request, notification_id):
        note = get_object_or_404(
            Notification, id=notification_id, user=request.user)
        note.is_read = True
        note.save()
        return Response({'id': str(note.id), 'is_read': True})


class NotificationMarkAllReadView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, user_id):
        if str(request.user.id) != str(user_id):
            raise PermissionDenied()
        count = Notification.objects.filter(
            user=request.user, is_read=False).update(is_read=True)
        return Response({'message': f'Marked {count} notifications as read.'})


class NotificationDeleteView(APIView):
    permission_classes = [IsAuthenticated]

    def delete(self, request, notification_id):
        note = get_object_or_404(
            Notification, id=notification_id, user=request.user)
        note.delete()
        return Response({'message': 'Notification deleted.'})


class AdminSendNotificationView(APIView):
    """POST /notifications/admin/send/
    Admin sends a notification to one user (user_id in body)
    or broadcasts to all users (omit user_id).
    """
    permission_classes = [IsAuthenticated]

    def post(self, request):
        if not (request.user.is_staff or
                getattr(request.user, 'is_admin', False)):
            raise PermissionDenied()

        target_user_id = request.data.get('user_id')
        n_type  = request.data.get('type', 'general')
        title   = request.data.get('title', '').strip()
        body    = request.data.get('body', '').strip()

        if not title or not body:
            return Response(
                {'error': 'title and body are required.'}, status=400)

        if n_type not in dict(Notification.TYPE_CHOICES):
            n_type = 'general'

        if target_user_id:
            user = get_object_or_404(User, id=target_user_id)
            n = Notification.objects.create(
                user=user, type=n_type, title=title, body=body)
            return Response({
                'sent': 1,
                'notification': _serialize(n),
            }, status=201)
        else:
            # Broadcast to all users
            users = list(User.objects.all())
            Notification.objects.bulk_create([
                Notification(user=u, type=n_type, title=title, body=body)
                for u in users
            ])
            return Response({'sent': len(users)}, status=201)