from django.urls import path
from .views import (
    NotificationListView, NotificationMarkReadView,
    NotificationMarkAllReadView, NotificationDeleteView,
)

urlpatterns = [
    path("<int:user_id>/",                    NotificationListView.as_view()),
    path("<int:user_id>/read-all/",           NotificationMarkAllReadView.as_view()),
    path("<uuid:notification_id>/read/",      NotificationMarkReadView.as_view()),
    path("<uuid:notification_id>/",           NotificationDeleteView.as_view()),
]