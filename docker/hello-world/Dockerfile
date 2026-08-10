# Dockerfile
# Customises the public infrastructureascode/hello-world image. That image is a tiny
# Go HTTP server that listens on :8080 and exposes "/" (200 OK) and "/health".
# We add an OCI label and a container HEALTHCHECK so ECS/Docker can report health.

FROM infrastructureascode/hello-world:latest

# Build-time metadata so reviewers can trace the image back to the pipeline build.
ARG BUILD_TAG="local"
LABEL org.opencontainers.image.title="broken-cloud-pipeline-hello-world" \
      org.opencontainers.image.description="Customised hello-world app for the challenge" \
      build.tag="${BUILD_TAG}"

# The upstream app serves on 8080; make that explicit.
ENV PORT=8080
EXPOSE 8080

# Container-level health check hits the app's own /health endpoint.
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:8080/health || exit 1
