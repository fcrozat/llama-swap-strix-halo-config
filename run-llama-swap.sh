#!/usr/bin/env bash
# Run llama-swap for the strix box.
#
#   ./run-llama-swap.sh                      # UI http://localhost:18080/ui/
#   LISTEN=:9000 ./run-llama-swap.sh         # other port (gufo owns :8080)
#   CONFIG=/path/other.yaml ./run-llama-swap.sh
#   WATCH_CONFIG=false ./run-llama-swap.sh   # ignore config.yaml edits
#   ./run-llama-swap.sh -- -listen :9000     # pass raw flags to llama-swap
#
# Handles the one thing that differs between the host and a distrobox: models
# are in /var/lib/models on the host, /run/host/var/lib/models inside one. The
# config always says /var/lib/models (including the paths handed to podman), so
# inside a distrobox this script makes that path exist as a symlink once.
#
# llama-swap starts and stops every model container itself, gufo included, so the
# host's gufo quadlet (rootful, /etc/containers/systemd/gufo.container) must stay
# down or it loads the same weights twice and holds :8080:
#
#   sudo systemctl disable --now gufo            # on the host
#   sudo loginctl enable-linger $USER            # so the user unit runs at boot
set -euo pipefail

MODELS_HOST=${MODELS_HOST:-/var/lib/models}
IN_DISTROBOX=${IN_DISTROBOX:-/run/host/var/lib/models}
CONFIG=${CONFIG:-$HOME/strix/launchers/config.yaml}
LISTEN=${LISTEN:-:9931}
# reload config.yaml when it changes: a model entry then applies without a unit
# restart, which would drop whatever model an interactive session is running on
WATCH_CONFIG=${WATCH_CONFIG:-true}
# the host package install - this script is run by the host unit, not from a
# distrobox, where /usr/bin/llama-swap does not exist: from inside one, call
# ./llama-swap -config config.yaml -validate directly. Override with
# LLAMA_SWAP=/path/to/llama-swap
BIN=${LLAMA_SWAP:-/usr/bin/llama-swap}

if [[ ! -x $BIN ]]; then
  echo "llama-swap binary not found: $BIN (set LLAMA_SWAP=/path/to/llama-swap)" >&2
  exit 1
fi
[[ -e $CONFIG ]] || { echo "missing config: $CONFIG" >&2; exit 1; }

if [[ -d $IN_DISTROBOX ]]; then
  MODELS=$IN_DISTROBOX
  # the config's absolute paths, pointed at the host: models + gufo's disk cache.
  # sudo -n so this fails fast instead of waiting on a password prompt
  for src in "$MODELS" /run/host/var/cache/gufo; do
    dst=${src#/run/host}
    [[ -e $dst || ! -d $src ]] || sudo -n ln -sfn "$src" "$dst" \
      || { echo "need: sudo ln -sfn $src $dst" >&2; exit 1; }
  done
else
  MODELS=$MODELS_HOST
  [[ -d $MODELS ]] || { echo "no models at $MODELS" >&2; exit 1; }
fi

# a gufo already answering on :8080 is the rootful quadlet: it would fight
# llama-swap for the unified memory and for the port
if timeout 3 curl -fsS -o /dev/null http://127.0.0.1:8080/health 2>/dev/null; then
  echo "warning: something answers on :8080 (gufo quadlet?) - sudo systemctl disable --now gufo" >&2
fi

echo "models: $MODELS  config: $CONFIG  listen: $LISTEN" >&2
if [[ ${1:-} == -- ]]; then
  shift
  exec "$BIN" -config "$CONFIG" -watch-config="$WATCH_CONFIG" "$@"
fi
exec "$BIN" -config "$CONFIG" -listen "$LISTEN" -watch-config="$WATCH_CONFIG"
