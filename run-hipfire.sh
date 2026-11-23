#!/usr/bin/env bash
# Serve hipfire models from upstream's own container (ghcr.io/warpfront/hipfire,
# the same image hipfire_run uses in capacity-ttl.yaml). hipfire keeps ONE
# resident model: the first model arg is pre-warmed, the rest are pulled up
# front and swap in per-request via the "model" field (docs/SERVE.md).
#
#   ./run-hipfire.sh qwen3.8:27b-mq4-xts qwen3.5:9b
#   curl -s localhost:$PORT/v1/chat/completions -H 'Content-Type: application/json' \
#     -d '{"model":"qwen3.5:9b","messages":[{"role":"user","content":"hi"}]}'
#
# Models = CLI args (anything not starting with '-'); all other args pass
# through to `hipfire serve` (e.g. --no-prewarm, --spec off, --kv-mode q8).
# List the tags: ./run-hipfire.sh --list (or run with no args) — the table is
# baked into the image (docs/MODELS.md), so no checkout is needed.
#
# The image serves as uid 1000 with HOME=/home/hipfire: the store mounts at
# /home/hipfire/.hipfire/models and both binds carry `,z` so podman relabels
# them SHARED (container_file_t:s0). A `:Z` (private) run pins the store to that
# one container's MCS categories, and every later container — every llama-swap
# start — then reads "failed to list model directory: Permission denied
# (os error 13)". Under rootless podman the entrypoint sees the store is not
# writable by uid 1000 and keeps container root, which is this host user.
#
# Run this on the host: $MODELS resolves in podman's mount namespace, not in a
# distrobox's (AGENTS.md, Paths) — inside one, mkdir below would create an empty
# directory that shadows nothing and reads as an empty model store.
#
# To move to a new release: IMAGE=<tag> ./run-hipfire.sh <tag> to try it, then
# bump hipfire_image, podman pull, restart the swap. Building from a checkout is
# still there if you need it (--target runtime is the slim variant):
#   cd ~/strix/hipfire && podman build -f Containerfile --target full -t localhost/hipfire .
set -euo pipefail

IMAGE=${IMAGE:-ghcr.io/warpfront/hipfire:0.4.7}
MODELS=${MODELS:-/var/lib/models/hipfire}
KCACHE=${KCACHE:-$HOME/hipfire-kcache}
NAME=${NAME:-hipfire}
PORT=${PORT:-8080}
# serve has no auth/TLS: keep the published port on loopback unless PUB says otherwise.
PUB=${PUB:-0.0.0.0}

# What is on disk plus what the image's registry offers, sizes and all. The
# store is only mounted when it exists here: podman would otherwise create an
# empty directory at $MODELS and report it as an empty store.
list_models() {
  if [[ -d $MODELS ]]; then
    podman run --rm --volume "$MODELS":/home/hipfire/.hipfire/models:ro,z "$IMAGE" list --remote
  else
    podman run --rm "$IMAGE" list --remote
  fi
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
# No chcon here: the `,z` below relabels both, and shared is the label they need.

# Pre-pull every requested model (idempotent: existing installs are kept,
# sidecars verified); non-resident tags become loadable on first request.
# Anything already in $MODELS is used as-is — 0.4.7 still loads the monolithic
# flash-next files an older build installed, no re-download.
#podman run --rm --volume "$MODELS":/home/hipfire/.hipfire/models:z "$IMAGE" pull <tag>
if [[ ${#MODEL_ARGS[@]} -gt 1 ]]; then
  echo "resident: ${MODEL_ARGS[0]} — swap in another by sending \"model\": \"<tag>\" in the request" >&2
fi

# Upstream run shape (docs/CONTAINER.md): bind 0.0.0.0 in-container so the
# published-port DNAT reaches it; no -d (PID 1 would exit).
exec podman run \
  --name "$NAME" --replace --rm \
  --device /dev/dri --device /dev/kfd --device /dev/accel/accel0 \
  --group-add keep-groups --security-opt seccomp=unconfined \
  --volume "$MODELS":/home/hipfire/.hipfire/models:ro,z \
  --volume "$KCACHE":/var/cache/hipfire:z \
  --ulimit memlock=-1:-1 \
  --publish "$PUB:$PORT:11435" \
  --env HIPFIRE_QWEN4_NPU_TRUNK=auto \
  "$IMAGE" \
  serve "${MODEL_ARGS[0]}" 0.0.0.0:11435 \
  ${EXTRA[@]+"${EXTRA[@]}"}
#  bench qwen3.8:flash-next --prompt-file /var/cache/hipfire/prompt.md --runs 2 --warmups 1 --max-tokens 32 --json
