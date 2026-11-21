#!/usr/bin/env bash
# Serve every model in strix-models.ini from one container, using llama-server
# router ("serve") mode: one process, one port, models loaded on demand and
# selected per request by the "model" field.
#
#   curl -s localhost:$PORT/models | jq -r '.data[].id'      # list models
#   curl -s localhost:$PORT/v1/chat/completions -H 'Content-Type: application/json' \
#     -d '{"model":"qwen3.8-27b","messages":[{"role":"user","content":"hi"}]}'
#
# Add a model = add an ini section; no new script.
# Build the image first (optional, IMAGE defaults to the public tag):
#   cd toolboxes && podman build --no-cache -t llama-rocm-10.0-strix-llama -f Dockerfile.rocm-10.0-strix-llama .
set -euo pipefail

#IMAGE=${IMAGE:-ghcr.io/yamz-labs/kyojin-glm:latest}
#MODELS=${MODELS:-/var/lib/models/kyojin/glm-pack}
#NAME=${NAME:-kyojin-glm}
IMAGE=${IMAGE:-localhost/kyojin-mimo:latest}
MODELS=${MODELS:-/var/lib/models/kyojin/mimo-pack}
NAME=${NAME:-kyojin-mimo}
PORT=${PORT:-8731}

# Only two kinds of args belong here: router plumbing, and device placement
# (ROCm). They override the same key in strix-models.ini for *every* model, so
# anything about loading, memory or scheduling stays in the ini.
exec podman run \
  --name "$NAME" --replace --rm \
  --device /dev/dri --device /dev/kfd \
  --security-opt seccomp=unconfined \
  --volume "$MODELS:/models:ro,Z" \
  --publish "$PORT:8731" \
  --ipc=host --ulimit memlock=-1:-1 \
  -v ~/kyojin-cache:/root/.cache \
  "$IMAGE" \
    "$@"
