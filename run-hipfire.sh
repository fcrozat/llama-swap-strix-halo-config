#!/usr/bin/env bash
# Serve hipfire models from the upstream container (localhost/hipfire, built
# from ~/strix/hipfire/Containerfile). hipfire keeps ONE resident model: the
# first model arg is pre-warmed, the rest are pulled up front and swap in
# per-request via the "model" field (docs/SERVE.md).
#
#   ./run-hipfire.sh qwen3.8:27b-mq4-xts qwen3.5:9b
#   curl -s localhost:$PORT/v1/chat/completions -H 'Content-Type: application/json' \
#     -d '{"model":"qwen3.5:9b","messages":[{"role":"user","content":"hi"}]}'
#
# Models = CLI args (anything not starting with '-'); all other args pass
# through to `hipfire serve` (e.g. --no-prewarm, --spec off, --kv-mode q8).
# List the tags: ./run-hipfire.sh --list (or run with no args).
# Tags come from ~/strix/hipfire/registry/models.json — the table behind
# docs/MODELS.md (qwen3.5:*, qwen3.6:*, qwen3.8:*, deepseek-v4-flash, flux.schnell:1, …)
#
# Rebuild the image after updating the repo (optional; IMAGE defaults to the
# local tag):
#   cd ~/strix/hipfire && podman build -f Containerfile --target runtime -t localhost/hipfire .
set -euo pipefail

IMAGE=${IMAGE:-localhost/hipfire:latest}
MODELS=${MODELS:-/var/lib/models/hipfire}
KCACHE=${KCACHE:-$HOME/hipfire-kcache}
NAME=${NAME:-hipfire}
PORT=${PORT:-8080}
# serve has no auth/TLS: keep the published port on loopback unless PUB says otherwise.
PUB=${PUB:-0.0.0.0}

# Registry table behind docs/MODELS.md: {tag: {size_gb, min_vram_gb, ...}}.
list_models() {
  local reg=${HIPFIRE_REGISTRY:-$HOME/strix/hipfire/registry/models.json}
  if [[ ! -e $reg ]]; then
    echo "model registry not found: $reg (see ~/strix/hipfire/docs/MODELS.md)" >&2
    return 1
  fi
  python3 - "$reg" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))["models"]
print(f"{len(d)} tags — {sys.argv[1]}")
for tag in sorted(d):
    e = d[tag]
    print(f"  {tag:<34} {e.get('size_gb', 0):>7} GB   min VRAM {e.get('min_vram_gb', 0)} GB")
EOF
}
if [[ ${1:-} == "--list" ]]; then
  list_models
  exit 0
fi

MODEL_ARGS=(); EXTRA=()
for a in "$@"; do
  case $a in -*) EXTRA+=("$a");; *) MODEL_ARGS+=("$a");; esac
done
if [[ ${#MODEL_ARGS[@]} -lt 1 ]]; then
  echo "usage: $0 <model-tag> [model-tag ...] [serve flags...]" >&2
  echo "tags: see --list (docs/MODELS.md)" >&2
  list_models || true
  exit 1
fi
mkdir -p "$MODELS" "$KCACHE"
chcon -R -t container_file_t "$MODELS" "$KCACHE"


# Pre-pull every requested model (idempotent: existing installs are kept,
# sidecars verified); non-resident tags become loadable on first request.
#for m in "${MODEL_ARGS[@]}"; do
#  podman run --rm --volume "$MODELS":/root/.hipfire/models:Z "$IMAGE" pull "$m"
#done
if [[ ${#MODEL_ARGS[@]} -gt 1 ]]; then
  echo "resident: ${MODEL_ARGS[0]} — swap in another by sending \"model\": \"<tag>\" in the request" >&2
fi

# Upstream run shape (docs/CONTAINER.md): bind 0.0.0.0 in-container so the
# published-port DNAT reaches it; no -d (PID 1 would exit).
exec podman run \
  --name "$NAME" --replace --rm \
  --device /dev/dri --device /dev/kfd --device /dev/accel/accel0 \
  --group-add keep-groups --security-opt seccomp=unconfined \
  --volume "$MODELS":/root/.hipfire/models:ro,Z \
  --volume "$KCACHE":/var/cache/hipfire:Z \
  --ulimit memlock=-1:-1 \
  --publish "$PUB:$PORT:11435" \
  --env HIPFIRE_QWEN4_NPU_TRUNK=auto \
  "$IMAGE" \
  serve "${MODEL_ARGS[0]}" 0.0.0.0:11435 \
  ${EXTRA[@]+"${EXTRA[@]}"}
#  bench qwen3.8:flash-next --prompt-file /var/cache/hipfire/prompt.md --runs 2 --warmups 1 --max-tokens 32 --json
