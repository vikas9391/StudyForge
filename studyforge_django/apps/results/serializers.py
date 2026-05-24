from rest_framework import serializers
from .models import Result


class ResultSerializer(serializers.ModelSerializer):
    user_id = serializers.UUIDField(source="user.id", read_only=True)

    class Meta:
        model  = Result
        fields = ["id", "user_id", "file_url", "file_name", "summary",
                  "quiz", "flashcards", "is_public", "clone_count",
                  "cloned_from", "created_at"]
        read_only_fields = ["id", "user_id", "created_at"]


class ResultListSerializer(serializers.ModelSerializer):
    """Lighter serializer for list views."""
    user_id = serializers.UUIDField(source="user.id", read_only=True)

    class Meta:
        model  = Result
        fields = ["id", "user_id", "file_url", "file_name", "summary",
                  "quiz", "flashcards", "is_public", "clone_count", "created_at"]
