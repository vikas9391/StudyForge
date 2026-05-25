from django.urls import path
from .views import (
    ProfileView, StudyHistoryView,
    AdminStatsView, AdminUsersView, AdminUserDetailView,
    AdminDeleteResultView, AdminToggleAdminView,
    ResetPasswordView,
)

urlpatterns = [
    path("profile/<int:user_id>/",         ProfileView.as_view()),
    path("profile/<int:user_id>/history/", StudyHistoryView.as_view()),

    path("admin/stats/",                                   AdminStatsView.as_view()),
    path("admin/users/",                                   AdminUsersView.as_view()),
    path("admin/users/<int:target_user_id>/",              AdminUserDetailView.as_view()),
    path("admin/results/<int:result_id>/",                 AdminDeleteResultView.as_view()),
    path("admin/users/<int:target_user_id>/toggle-admin/", AdminToggleAdminView.as_view()),
]