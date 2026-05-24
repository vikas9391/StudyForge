from django.urls import path
from .views import (
    RecordQuizAttemptView, WeakTopicsView,
    AccuracyOverTimeView, AnalyticsSummaryView, WeeklyStatsView,
)

urlpatterns = [
    path("quiz-attempt/",               RecordQuizAttemptView.as_view()),
    path("weak-topics/<int:user_id>/",  WeakTopicsView.as_view()),
    path("accuracy/<int:user_id>/",     AccuracyOverTimeView.as_view()),
    path("summary/<int:user_id>/",      AnalyticsSummaryView.as_view()),
    path("weekly-stats/<int:user_id>/", WeeklyStatsView.as_view()),
]