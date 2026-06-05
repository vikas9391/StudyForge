from django.urls import path
from .views import UploadView, UploadStatusView

urlpatterns = [
    path("",                        UploadView.as_view()),
    path("status/<uuid:result_id>/", UploadStatusView.as_view()),
]