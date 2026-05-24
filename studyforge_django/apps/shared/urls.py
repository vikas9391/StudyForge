from django.urls import path
from .views import (
    VisibilityView, BrowsePublicView, FeaturedView,
    PublicSessionDetailView, CloneSessionView,
)

urlpatterns = [
    path("browse/",                          BrowsePublicView.as_view()),
    path("featured/",                        FeaturedView.as_view()),
    path("<uuid:result_id>/visibility/",     VisibilityView.as_view()),
    path("<uuid:result_id>/clone/",          CloneSessionView.as_view()),
    path("<uuid:result_id>/",                PublicSessionDetailView.as_view()),
]
