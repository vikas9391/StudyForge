from django.urls import path
from .views import ResultListView, ResultDetailView

urlpatterns = [
    path("",              ResultListView.as_view()),
    path("<uuid:result_id>/", ResultDetailView.as_view()),
]
