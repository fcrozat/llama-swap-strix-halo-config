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

IMAGE=${IMAGE:-docker.io/kyuz0/amd-strix-halo-toolboxes:rocm-10.0-strix-llama}
MODELS=${MODELS:-/var/lib/models/llama}
PRESET=${PRESET:-/var/lib/models/llama/strix-models.ini}
NAME=${NAME:-llama-strix}
PORT=${PORT:-9931}
# gfx1151 has unified CPU/GPU memory: keep one model resident, the router
# unloads the least recently used one when another is requested. 0 = unlimited.
MODELS_MAX=${MODELS_MAX:-1}

[[ -e $PRESET ]] || { echo "missing $PRESET" >&2; exit 1; }
# Guard: managed memory corrupts the MTP draft under retained PM4 on gfx1151.
unset GGML_HIP_ENABLE_UNIFIED_MEMORY GGML_CUDA_ENABLE_UNIFIED_MEMORY || true

# Only two kinds of args belong here: router plumbing, and device placement
# (ROCm). They override the same key in strix-models.ini for *every* model, so
# anything about loading, memory or scheduling stays in the ini.
exec podman run \
  --pull always \
  --name "$NAME" --replace --rm \
  --device /dev/dri --device /dev/kfd \
  --group-add video --group-add render \
  --security-opt seccomp=unconfined \
  --volume "$MODELS:/models:ro,Z" \
  --volume "$PRESET:/strix-models.ini:ro,Z" \
  --publish "$PORT:9931" \
  "$IMAGE" \
  llama-server \
    --models-preset /strix-models.ini \
    --models-max "$MODELS_MAX" \
    --host 0.0.0.0 --port 9931 \
    -dev ROCm0 -ngl 999 \
    --spec-draft-device ROCm0 --spec-draft-ngl 99 \
    "$@"
