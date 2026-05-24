from django.urls import path
from .views import InitSRCardsView, ReviewView, DueCardsView, SRStatsView

urlpatterns = [
    path("init/<uuid:result_id>/", InitSRCardsView.as_view()),
    path("review/",                ReviewView.as_view()),
    path("due/<int:user_id>/",     DueCardsView.as_view()),
    path("stats/<int:user_id>/",   SRStatsView.as_view()),
]