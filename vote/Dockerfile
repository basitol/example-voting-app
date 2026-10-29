# Base image for development and production
FROM python:3.11-slim AS base

# Install curl for health checks
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl && \
    rm -rf /var/lib/apt/lists/*

# Create a non-root application user
RUN useradd --create-home --shell /usr/sbin/nologin app

WORKDIR /usr/local/app

# Install Python dependencies
COPY requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Development stage
FROM base AS dev
RUN pip install watchdog
ENV FLASK_ENV=development
CMD ["python", "app.py"]

# Production stage
FROM base AS final

COPY --chown=app:app . .

# Run the application without root privileges
USER app

EXPOSE 80

CMD ["gunicorn", "app:app", "-b", "0.0.0.0:80", "--log-file", "-", "--access-logfile", "-", "--workers", "4", "--keep-alive", "0"]
