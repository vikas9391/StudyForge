from django.urls import path
from .views import (
    UploadView, UploadStatusView,
    ProcessView,
    ResultListView, ResultDetailView,
    RetryView,
)

urlpatterns = [
    path("upload/",                         UploadView.as_view()),
    path("upload/status/<uuid:result_id>/", UploadStatusView.as_view()),
    path("process/",                        ProcessView.as_view()),
    path("results/",                        ResultListView.as_view()),
    path("results/<uuid:result_id>/",       ResultDetailView.as_view()),
    path("retry/<uuid:result_id>/",         RetryView.as_view()),
]