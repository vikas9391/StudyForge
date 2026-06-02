#!/usr/bin/env bash
set -e
python manage.py collectstatic --noinput
python manage.py migrate
python manage.py create_default_admin
gunicorn studyforge_django.wsgi:application --bind 0.0.0.0:$PORT