#!/usr/bin/env bash
# Serve one gufo model straight from the gufo-runtime container: the standalone
# counterpart of run-llama-swap.sh, which starts gufo through llama-swap.
#
#   ./run-gufo.sh                                        # flash-next, the quadlet's model
#   ./run-gufo.sh 27b                                    # presets: flash-next | 27b | deepseek
#   ./run-gufo.sh --list                                 # presets + the files behind them
#   PORT=8090 ./run-gufo.sh deepseek                     # other published port
#   ./run-gufo.sh flash-next --context 262144 --sessions 2   # rest passes to `gufo serve`
#   ./run-gufo.sh ext list                                # gufo extension list
#   ./run-gufo.sh ext install lfm3@0.4.0                  # build a module into $EXT_DIR
#   ./run-gufo.sh ext update                              # after every podman pull
#   ./run-gufo.sh ext remove lfm3
#   ./run-gufo.sh ext install ./lfm3-ext                  # a local checkout, mounted ro
#   SRC=/workspace ./run-gufo.sh ext install /workspace/lfm3   # an extra -v
#
#   curl -s localhost:$PORT/v1/models | jq -r '.data[].id'          # ids gufo reports (some have spaces)
#   curl -s localhost:$PORT/v1/chat/completions -H 'Content-Type: application/json' \
#     -d '{"model":"Qwen3.8 Flash Next","messages":[{"role":"user","content":"hi"}]}'
#
# gufo keeps ONE resident model, so switching models means restarting this
# script; llama-swap does that swap for you (gufo-27b, gufo-deepseek, ...).
#
# Extensions (docs/extensions.md): `ext` runs `gufo extension ...` in a
# throwaway container - store only, no GPU, no port, no weights loaded - and
# `serve` mounts that same $EXT_DIR, so an installed module is live on the next
# serve start (a running server keeps its already-loaded set). A module is tied
# to the exact gufo build it was compiled for: after `podman pull`, `ext list`
# shows `needs update` and gufo skips the module until `ext update` rebuilds it
# - and the server still answers /ready while it skips, so the health check is
# not the check, the log line "is not built for this gufo" is.
# `ext list` also names a newer release when one exists ("0.3.0 available");
# `ext update` moves a registry install to it, a git pin is only rebuilt.
# llama-swap mounts the same store too (gufo_ext in config.yaml).
#
# A module that links a library the runtime image ships needs
# CMAKE_PREFIX_PATH, and loom wants it for `install` *and* for the post-pull
# `ext update`. In the image that library sits at a Nix store path whose hash
# changes with every build, so look it up instead of recording it:
#   LR=$(podman run --rm --entrypoint /bin/sh "$IMAGE" \
#        -c 'ls -d /nix/store/*loom-runtime*')
#   CMAKE_PREFIX_PATH=$LR ./run-gufo.sh ext update   # passed through when set
#
# The image carries its CA bundle as one file that OpenSSL does not pick up on
# its own, so registry/Git fetches fail with "unable to get local issuer
# certificate" unless SSL_CERT_FILE points at it (see CA below).
#
# In a distrobox/toolbox: the box has its own /var, so models and cache are
# checked through $HOSTFS (/run/host) and still handed to podman as plain host
# paths - the podman here is the host's, over its socket. $HOME and the network
# are shared, so the extension store, the published port and the /health probe
# need nothing. A path missing on the host needs a host shell, and the hints
# below use distrobox-host-exec for it.
#
# Shared flags are the ones from /etc/containers/systemd/gufo.container, and the
# presets are the Exec lines commented out next to it. :8080 is gufo's own port,
# also claimed by the rootful quadlet and by llama-swap's proxy, so take whoever
# holds it out of the way (or use PORT=8090) - otherwise the same weights get
# loaded twice:
#
#   sudo systemctl disable --now gufo            # the quadlet, on the host
#   systemctl stop llama-swap                    # the proxy, as $USER
#
# Foreground on purpose: Ctrl-C stops the container (--rm cleans it up).
# Refresh the image with: podman pull $IMAGE && ./run-gufo.sh ext update
set -euo pipefail

# modules in the store are built for one gufo build, so `ext install` has to run
# with the same IMAGE that serves: a module built for another build shows up as
# `needs update` and gufo skips it.
IMAGE=${IMAGE:-ghcr.io/gufo-org/toolboxes/gufo-runtime:latest}
MODELS=${MODELS:-/var/lib/models/llama}
CACHE=${CACHE:-/var/cache/gufo}    # --cache-disk; write side of the keep-id userns below
NAME=${NAME:-gufo}
PORT=${PORT:-8080}
# serve has no auth/TLS: publish on loopback unless PUB says otherwise
PUB=${PUB:-127.0.0.1}
# The store is a plain host directory, so `ls` and `rm` work on it: $HOME is
# shared with the host (also inside a distrobox, unlike /var/lib), and the path
# mirrors gufo's own default, so nothing else has to be told where it lives.
# SELinux: ':z' relabels it shared, as with the cache below.
EXT_DIR=${EXT_DIR:-$HOME/.local/share/gufo/extensions}
EXT_STORE=${EXT_STORE:-/home/gufo/.local/share/gufo/extensions}
CA=${CA:-/etc/ssl/certs/ca-bundle.crt}
# extra read-only mount for `install <dir>`; the source itself is mounted
# automatically when it is a path that exists on this host
SRC=${SRC:-}

# The serve flags every gufo model shares (from gufo.container / the gufo_run
# macro of the llama-swap configs). Presets and CLI flags come after, so both
# can override these same keys.
SERVE=(
  --sessions 4 --max-pending-per-client 4
  --max-tokens 32768 --context 131072
  --cache-disk /gufo_cache
  --reasoning-effort xhigh --preserve-thinking on
)

PRESETS=(flash-next 27b deepseek)

# preset -> the model + draft lines of gufo.container's Exec. Paths are the
# in-container ones (/models), which is what gufo gets handed.
preset_flags() {
  case $1 in
    flash-next) printf '%s\n' \
      --model /models/Qwen3.8-Flash-Next-GGUF-Gufo/UD-Q4_K_XL/Qwen3.8-Flash-Next-UD-Q4_K_XL-00001-of-00004.gguf \
      --speculative mtp \
      --mtp-model /models/Qwen3.8-Flash-Next-GGUF-Gufo/MTP/mtp-Qwen3.8-Flash-Next-shared-Q8_0.gguf \
      --mmproj /models/Qwen3.8-Flash-Next-GGUF-Gufo/mmproj-BF16.gguf \
      --temperature 1.0 --top-p 0.95 --top-k 20 --min-p 0.0 \
      --presence-penalty 0.0 --repeat-penalty 1.0 ;;
    # the DFlash2 draft moved into the model dir; the quadlet's
    # Qwen3.8-27B-DFlash2-GGUF/... path is stale.
    27b) printf '%s\n' \
      --model /models/Qwen3.8-27B-GGUF/Qwen3.8-27B-UD-Q4_K_XL.gguf \
      --speculative dflash2 \
      --dflash-model /models/Qwen3.8-27B-GGUF/Qwen3.8-27B-DFlash2-Q4_K_M.gguf ;;
    deepseek) printf '%s\n' \
      --model /models/deepseek-v4-flash/DeepSeek-V4-Flash-IQ2XXS-w2Q2K-AProjQ8-SExpQ8-OutQ8-chat-v2-imatrix-0731.gguf \
      --dspark-model /models/deepseek-v4-flash/DeepSeek-V4-Flash-DSpark-support-0731.gguf ;;
    *) return 1 ;;
  esac
}

# In a distrobox the box has its own /var and reads the host's under $HOSTFS,
# while podman here is the host's over its socket - so paths get checked through
# $HOSTFS and handed to podman unchanged. Set HOSTFS= (empty) where podman is
# nested in the box rather than the host's.
HOSTFS=${HOSTFS-/run/host}
IN_TOOLBOX=0
[[ -n $HOSTFS && -d $HOSTFS/var/lib ]] && IN_TOOLBOX=1
# the way to a host shell from a box, for the hints that need root there
HOSTEXEC=${HOSTEXEC-$( ((IN_TOOLBOX)) && command -v distrobox-host-exec || true )}

# a host path as seen from here
view() {
  (( IN_TOOLBOX )) && [[ ! -e $1 && -e "$HOSTFS$1" ]] \
    && printf '%s' "$HOSTFS$1" || printf '%s' "$1"
}

# A directory podman needs on the host, made where it can be made. Inside a box
# only the host copy counts: the box's own /var is a dead end there (its root can
# write it, and podman on the host would just create a root-owned one). The hint
# needs a host shell since sudo on the host asks for a password.
require_dir() {
  local p=$1
  if (( IN_TOOLBOX )); then p=$HOSTFS$p; fi
  { mkdir -p "$p" 2>/dev/null || [[ -d $p ]]; } && [[ -w $p ]] && return 0
  echo "needs a host shell: sudo mkdir -p '${p#"$HOSTFS"}' && sudo chown $(id -u):$(id -g) '${p#"$HOSTFS"}'" >&2
  [[ -n $HOSTEXEC ]] && echo "                  or: $HOSTEXEC sudo mkdir -p '${p#"$HOSTFS"}'" >&2
  return 1
}

usage() {
  echo "usage: $0 [preset] [gufo serve flags...]" >&2
  echo "       $0 ext <gufo extension args...>   # list | install | update | remove" >&2
  echo "presets: ${PRESETS[*]}   (see --list)" >&2
}

# host path of an in-container /models path
host_path() { view "${MODELS}${1#/models}"; }

if [[ ${1:-} == --list ]]; then
  for p in "${PRESETS[@]}"; do
    printf '%s\n' "$p"
    mapfile -t f < <(preset_flags "$p")
    for ((i = 0; i < ${#f[@]}; i++)); do
      case ${f[i]} in
        --model|--mtp-model|--mmproj|--dflash-model|--dspark-model) ;;
        *) continue ;;
      esac
      h=$(host_path "${f[i + 1]}")
      [[ -e $h ]] && printf '    %s\n' "$h" || printf '    %s  MISSING\n' "$h"
    done
  done
  printf 'extensions: %s -> %s  (%s ext list)\n' "$EXT_DIR" "$EXT_STORE" "$0"
  exit 0
fi

# ext|extension -> straight to `gufo extension ...`, no model and no port, so it
# also runs beside a live server (container $NAME-ext, never $NAME)
if [[ ${1:-} == ext || ${1:-} == extension || ${1:-} == --ext ]]; then
  shift
  # the store takes writes from uid 1000, the keep-id mapping, or `install`
  # fails halfway through its build
  require_dir "$EXT_DIR" || exit 1
  RUN=(-e SSL_CERT_FILE="$CA" -e GUFO_EXTENSIONS_DIR="$EXT_STORE")
  # the registry index override, if the caller points at a fork or a file
  [[ -n ${GUFO_EXTENSION_REGISTRY:-} ]] \
    && RUN+=(-e GUFO_EXTENSION_REGISTRY="$GUFO_EXTENSION_REGISTRY")
  # and the prefix of a library the image ships, for modules that link one
  # (loom - see the CMAKE_PREFIX_PATH note at the top)
  [[ -n ${CMAKE_PREFIX_PATH:-} ]] \
    && RUN+=(-e CMAKE_PREFIX_PATH="$CMAKE_PREFIX_PATH")
  MNT=()
  # an install source that exists on this host has to be visible in the
  # container: mount it at itself (ro - gufo copies it into the store to build)
  # and hand gufo the absolute path, so `install ./dir` works from any cwd.
  # Only `install` takes a source, and only a bare word is one (not --yes).
  if [[ ${1:-} == install ]]; then
    args=()
    src=
    for a in "$@"; do
      if [[ -z $src && $a != -* && -e $a ]]; then
        src=$(realpath -- "$a")
        a=$src
      fi
      args+=("$a")
    done
    [[ -n $src ]] && MNT+=(--volume "$src:$src:ro,z")
    set -- "${args[@]}"
  fi
  if [[ -n $SRC ]]; then
    src=$(realpath -- "$SRC")
    MNT+=(--volume "$src:$src:ro,z")
  fi
  # `install` asks before building code no maintainer reviewed. -t on its own
  # hands that prompt a terminal with nothing behind it, so it blocks unreadable
  # - -i is what feeds it. With no terminal gufo wants --yes instead.
  TTY=()
  [[ -t 0 ]] && TTY+=(-i)
  [[ -t 1 ]] && TTY+=(-t)
  exec podman run \
    --name "$NAME-ext" --replace --rm \
    --userns keep-id:uid=1000,gid=1000 \
    --volume "$EXT_DIR:$EXT_STORE:rw,z" \
    ${MNT[@]+"${MNT[@]}"} "${RUN[@]}" ${TTY[@]+"${TTY[@]}"} \
    "$IMAGE" gufo extension ${@+"$@"}
fi

# first bare arg = the preset, everything after it goes to `gufo serve` as-is
# (a `--flag value` pair must not have its value read as a preset name)
MODEL=${MODEL:-flash-next}
if (( $# > 0 )) && [[ $1 != -* ]]; then MODEL=$1; shift; fi
EXTRA=("$@")
mapfile -t PRESET < <(preset_flags "$MODEL") || true
if (( ${#PRESET[@]} == 0 )); then usage; exit 1; fi

# fail here rather than after a registry pull and a multi-minute load
for ((i = 0; i < ${#PRESET[@]}; i++)); do
  [[ ${PRESET[i]} == --model ]] || continue
  h=$(host_path "${PRESET[i + 1]}")
  [[ -e $h ]] || { echo "missing model: $h" >&2; exit 1; }
done

# the disk cache is written by uid 1000 inside, so it has to exist and be ours
require_dir "$CACHE" || exit 1
require_dir "$EXT_DIR" || exit 1

# /health answers for both of the usual squatters: the quadlet and llama-swap
if timeout 3 curl -fsS -o /dev/null "http://127.0.0.1:$PORT/health" 2>/dev/null; then
  echo "warning: :$PORT answers already (gufo quadlet or llama-swap) - ${HOSTEXEC:+$HOSTEXEC }sudo systemctl disable --now gufo; ${HOSTEXEC:+$HOSTEXEC }systemctl stop llama-swap; or PORT=8090" >&2
fi

echo "model: $MODEL  image: $IMAGE  models: $MODELS  cache: $CACHE  http://$PUB:$PORT" >&2

# SELinux: the model tree is shared by several engines and already
# container_file_t, so it is mounted plain :ro - ':Z' would stamp an exclusive
# MCS category and lock the other containers out. The cache is ours: ':z'.
exec podman run \
  --name "$NAME" --replace --rm \
  --device /dev/dri --device /dev/kfd \
  --group-add keep-groups \
  --ulimit memlock=-1:-1 \
  --userns keep-id:uid=1000,gid=1000 \
  --volume "$MODELS:/models:ro" \
  --volume "$CACHE:/gufo_cache:rw,z" \
  --volume "$EXT_DIR:$EXT_STORE:rw,z" \
  --publish "$PUB:$PORT:8080" \
  -e GUFO_EXTENSIONS_DIR="$EXT_STORE" \
  "$IMAGE" \
  gufo serve --host 0.0.0.0 --port 8080 llm \
  "${SERVE[@]}" "${PRESET[@]}" ${EXTRA[@]+"${EXTRA[@]}"}
