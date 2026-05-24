from django.urls import path
from .views import ProcessView

urlpatterns = [
    path("", ProcessView.as_view()),
]
