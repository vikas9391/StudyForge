from django.urls import path
from .views import IngestURLView, IngestYouTubeView, IngestOCRView

urlpatterns = [
    path("url/",     IngestURLView.as_view()),
    path("youtube/", IngestYouTubeView.as_view()),
    path("ocr/",     IngestOCRView.as_view()),
]
