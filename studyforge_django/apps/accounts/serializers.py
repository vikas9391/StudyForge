from rest_framework import serializers
from .models import User, Profile


class SignupSerializer(serializers.Serializer):
    email    = serializers.EmailField()
    password = serializers.CharField(min_length=6, write_only=True)

    def validate_email(self, value):
        if User.objects.filter(email=value).exists():
            raise serializers.ValidationError("An account with this email already exists.")
        return value.lower()

    def create(self, validated_data):
        email = validated_data["email"]
        user = User.objects.create_user(
            username=email,
            email=email,
            password=validated_data["password"],
        )
        return user


class ProfileSerializer(serializers.ModelSerializer):
    email      = serializers.EmailField(source="user.email", read_only=True)
    user_id    = serializers.UUIDField(source="user.id", read_only=True)
    created_at = serializers.DateTimeField(read_only=True)
    updated_at = serializers.DateTimeField(read_only=True)

    class Meta:
        model  = Profile
        fields = ["user_id", "email", "full_name", "phone", "bio", "avatar_url",
                  "is_admin", "created_at", "updated_at"]
        read_only_fields = ["user_id", "email", "is_admin", "created_at", "updated_at"]


class ProfileUpdateSerializer(serializers.ModelSerializer):
    class Meta:
        model  = Profile
        fields = ["full_name", "phone", "bio", "avatar_url"]
