from django.urls import path
from .views import RetryView

urlpatterns = [
    path("<uuid:result_id>/", RetryView.as_view()),
]
