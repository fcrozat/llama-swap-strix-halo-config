#!/usr/bin/env bash
# run-mem-sweep.sh - measure what these entries really cost the host, and what
# the router should therefore be told they cost.
#
# Produces the numbers that go into each entry's `capacities: {mem: }`. It never
# edits the config; it prints suggested claims and you write them by hand with a
# sentence about where the figure came from.
#
# WHY THE SHAPE IS THIS SHAPE (AGENTS.md, "Measuring without other clients in
# the sample"). Read this before changing anything here:
#
#   * The host is the only honest instrument. RSS and `podman stats` lie: a
#     model reporting 6.4 GiB of RSS was holding 111.8 GiB, the rest being kfd
#     device memory no container stat shows. So this samples MemAvailable and
#     takes peak = baseline - trough.
#   * A baseline is only good if the pool was empty when it was taken. This box
#     answers from one of its own models, so any request made between two
#     entries reloads the resident one and the baseline becomes the model being
#     evicted. Hence the guard: refuse to start unless `ls-*` is empty.
#   * A row is void, not conservative, if the journal shows a
#     `capacity: model=... evict=...` line dated inside that entry's window -
#     something else wanted a model while we were measuring.
#   * The whole window has to be ONE synchronous call. Returning from a wait is
#     itself a request to the model serving the session that runs this, which
#     reloads ~112 GiB inside the window. Do not detach this and poll it.
#   * Port 8080 is on the wildcard address, so the LAN and tailscale share the
#     engine. The window pins the unit to loopback with a systemd drop-in under
#     $XDG_RUNTIME_DIR (a reboot clears it, so a forgotten lock cannot outlive
#     the window), proves the pin by probing every non-loopback address, and
#     runs a watchdog that removes the pin if loopback itself stops answering.
#
# WHAT IT COSTS: the resident model is unloaded for the duration and every
# client gets connection-refused while pinned - about 1.5-2.5 min per entry,
# plus a cold reload of the restore model on the way out (61 s observed). That
# is a 500-free interruption (refusing a connect cannot kill a generation in
# flight, an eviction can) but it is still an interruption: announce it, and run
# it between requests, per AGENTS.md "Applying a change".
#
# Usage:
#   ./run-mem-sweep.sh                 # dry run: plan + guard, loads nothing
#   ./run-mem-sweep.sh --run           # the window, over every ${run} entry
#   ./run-mem-sweep.sh --run qwen3.8-27b openjev-q4
#   ./run-mem-sweep.sh --run --restore=hipfire-4b    # warm something else going
#   ./run-mem-sweep.sh --run --keep-open             # leave the pin in (debug)
#
# Decision models (`/v1/chat/completions` -> 501) are detected from that 501 and
# driven through /v1/systemone instead; the schema is in TODO.md §1.
set -uo pipefail

CONFIG=${CONFIG:-$(cd "$(dirname "$0")" && pwd)/capacity-ttl.yaml}
RUN=""
RESTORE=""
KEEP_OPEN=""
ENTRIES=()
for a in "$@"; do
  case "$a" in
    --run) RUN=1 ;;
    --restore=*) RESTORE=${a#*=} ;;
    --keep-open) KEEP_OPEN=1 ;;
    -*) echo "unknown flag: $a" >&2; exit 2 ;;
    *) ENTRIES+=("$a") ;;
  esac
done
[ -f "$CONFIG" ] || { echo "no config at $CONFIG (set CONFIG=)" >&2; exit 2; }

DROPIN=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/systemd/user/llama-swap.service.d/loopback.conf
PIN=${PIN_LISTEN:-127.0.0.1:8080}   # what the pinned unit listens on, and what we probe
MEM=${MEM:-}
[ -n "$MEM" ] || for m in /run/host/proc/meminfo /proc/meminfo; do
  [ -r "$m" ] && { MEM=$m; break; }
done
WATCH_PID=""

free_mib() { awk '/MemAvailable/ {printf "%d", $2 / 1024}' "$MEM"; }
resident() { podman ps --format '{{.Names}}' 2>/dev/null | grep '^ls-' | tr '\n' ' '; }

take_window() {
  echo "=== taking the window at $(date +%H:%M:%S) ==="
  echo "resident before: [$(resident)]  $(free_mib) MiB free"

  mkdir -p "$(dirname "$DROPIN")"
  printf '[Service]\nEnvironment=LISTEN=%s\n' "$PIN" > "$DROPIN"
  systemctl --user daemon-reload && systemctl --user restart llama-swap
  for _ in $(seq 1 60); do
    [ "$(curl -s -m 3 -o /dev/null -w '%{http_code}' "http://$PIN/health")" = 200 ] && break
    sleep 1
  done

  # Prove it: any other address of this box must refuse, or a foreign request
  # lands mid-sweep and voids the rows. `ip` is not always in the container.
  local leak=0 addrs=""
  addrs=$( (hostname -I 2>/dev/null || true
            awk '/32 host/ {print $1}' /proc/net/fib_trie 2>/dev/null) |
           tr ' ' '\n' | grep -vE '^127\.|^$|^0\.0\.0\.0$' | sort -u | head -3)
  if [ -z "$addrs" ]; then
    echo "  pin: no non-loopback address visible here - cannot prove it externally"
  fi
  for a in $addrs; do
    code=$(curl -s -m 4 -o /dev/null -w '%{http_code}' "http://$a:8080/health" 2>/dev/null \
           || echo refused)
    printf '  pin %-16s %s\n' "$a" "${code:-refused}"
    [ "$code" = 200 ] && leak=1
  done
  printf '  pin %-16s %s\n' "localhost" \
    "$(curl -s -m 4 -o /dev/null -w '%{http_code}' "http://$PIN/health")"
  [ "$leak" = 1 ] && { echo "ABORT: the pin leaked"; exit 1; }

  # Watchdog: if loopback itself dies, unpin first and die second. Kill this by
  # PID later - `pkill -f` matches the command line of the shell doing the
  # killing, which is this script.
  ( while sleep 5; do
      curl -s -m 4 -o /dev/null "http://$PIN/health" || {
        echo "watchdog: loopback stopped answering, releasing the pin"; drop_pin; exit 0; }
    done ) &
  WATCH_PID=$!

  echo "=== emptying the pool (the eviction everyone pays for) ==="
  for n in $(resident); do
    curl -s -m 90 -o /dev/null -w "unload ${n}: %{http_code}\n" \
      -X POST "http://$PIN/api/models/unload/${n#ls-}"
  done
  for _ in $(seq 1 90); do [ -z "$(resident)" ] && break; sleep 2; done
  echo "resident now: [$(resident)]  $(free_mib) MiB free"
  if [ -n "$(resident)" ]; then
    echo "ABORT: pool would not empty - a load now would evict it"
    exit 1
  fi
}

drop_pin() {
  [ -n "$KEEP_OPEN" ] && { echo "--keep-open: leaving the pin in place"; return; }
  [ -f "$DROPIN" ] || return
  rm -f "$DROPIN" && systemctl --user daemon-reload && systemctl --user restart llama-swap
  for _ in $(seq 1 60); do
    [ "$(curl -s -m 3 -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/health)" = 200 ] && break
    sleep 1
  done
  curl -s -m 5 -o /dev/null -w 'after unpin, localhost/health: %{http_code}\n' \
    http://127.0.0.1:8080/health
}

cleanup() {
  rc=$?
  echo "--- cleanup at $(date +%H:%M:%S) (rc $rc) ---"
  [ -n "$WATCH_PID" ] && kill "$WATCH_PID" 2>/dev/null
  drop_pin
  echo "resident: [$(resident)]  $(free_mib) MiB free"
  exit $rc
}
trap cleanup EXIT INT TERM

if [ -n "$RUN" ]; then
  take_window
else
  echo "dry run: not pinning, not unloading, not loading"
fi

CONFIG="$CONFIG" MEM="$MEM" RUN="$RUN" RESTORE="$RESTORE" \
  python3 - ${ENTRIES[@]+"${ENTRIES[@]}"} <<'PY'
"""The measuring half of run-mem-sweep.sh. Entries and live claims are read out
of the config, so this cannot go stale against it the way a hardcoded list does.
"""
import json, os, re, subprocess, sys, time, urllib.error, urllib.request

SWAP = "http://127.0.0.1:8080"
MEM = os.environ["MEM"]
CONFIG = os.environ["CONFIG"]
RUN = os.environ.get("RUN") == "1"
RESTORE = os.environ.get("RESTORE") or "gufo-flash-next"
DECODE_TOKENS = 220          # enough to be a real decode; KV is committed at init
SETTLE_S = 45
LOAD_BUDGET_S = 300
argv = sys.argv[1:]


def sh(cmd):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True).stdout.strip()


def parse(path):
    """{entry: {"claim": MiB|None, "family": "run"}} from the config's own text.

    Text, not YAML: this wants the same two facts a reader greps for, and it must
    not disagree with what llama-swap loads. Scoped to the `models:` block so
    `hooks: on_startup:` is not mistaken for an entry.
    """
    out, cur, in_models = {}, None, False
    for line in open(path):
        if line[:1] not in (" ", "#", "\n"):      # top-level key
            in_models = line.startswith("models:")
            continue
        if not in_models:
            continue
        m = re.match(r"^  ([A-Za-z0-9._-]+):\s*$", line)
        if m:
            cur = m.group(1)
            out[cur] = {"claim": None, "family": None}
            continue
        if cur and "${run}" in line:
            out[cur]["family"] = "run"
        m = re.search(r"capacities:\s*\{[^}]*mem:\s*(\d+)", line)
        if m and out[cur]["claim"] is None:
            out[cur]["claim"] = int(m.group(1))
    return out


def mem_avail():
    """MiB. meminfo counts KiB - reading it as MiB is a 1024x claim."""
    for line in open(MEM):
        if line.startswith("MemAvailable:"):
            return int(line.split()[1]) // 1024
    raise RuntimeError("no MemAvailable in " + MEM)


def resident():
    return [n for n in sh("podman ps --format '{{.Names}}'").split() if n.startswith("ls-")]


def post(path, obj, timeout=300):
    req = urllib.request.Request(SWAP + path, data=json.dumps(obj).encode(),
                                 headers={"Content-Type": "application/json"},
                                 method="POST")
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read())


def evictions(since):
    out = sh(f'journalctl --user -u llama-swap --no-pager --since "@{int(since)}" 2>/dev/null')
    return [l for l in out.splitlines() if "capacity: model=" in l and "evict=" in l]


def drive(entry, deadline):
    """Trigger the load plus one request. Returns how it was driven, or None."""
    while time.time() < deadline:
        try:
            post("/v1/chat/completions", {
                "model": entry, "max_tokens": DECODE_TOKENS,
                "messages": [{"role": "user", "content": "Reply with exactly: sweep"}]})
            return "chat"
        except urllib.error.HTTPError as e:
            body = ""
            try:
                body = e.read().decode(errors="replace")
            except Exception:
                pass
            if e.code == 501 and "systemone" in body:
                try:                      # decision model, by design (TODO §1)
                    post("/v1/systemone", {
                        "model": entry, "state": "sweep baseline for measurement",
                        "questions": {"q": {"type": "noul",
                                            "instructions": "Report the load."}}})
                    return "systemone"
                except Exception:
                    pass
            return None
        except Exception:
            time.sleep(2)                 # container starting, or queued behind us
    return None


def measure(entry):
    base = mem_avail()                    # pool verified empty before this ran
    trough = base
    deadline = time.time() + LOAD_BUDGET_S
    t0 = time.time()
    how = drive(entry, deadline)
    answered = round(time.time() - t0, 1)
    plateau, stable, until = mem_avail(), 0, min(deadline, time.time() + SETTLE_S)
    while time.time() < until:
        time.sleep(1)
        a = mem_avail()
        trough = min(trough, a)
        if a == plateau:
            stable += 1
            if stable >= 3:
                break
        else:
            plateau, stable = a, 0
    settled = max(plateau, trough)
    sh(f"curl -s -m 90 -o /dev/null -X POST {SWAP}/api/models/unload/{entry}")
    return {"base": base, "trough": trough, "settled": settled, "peak": base - trough,
            "resid": base - settled, "answered": answered, "how": how}


CFG = parse(CONFIG)
plan = argv or [k for k, v in CFG.items() if v["family"] == "run"]
unknown = [e for e in plan if e not in CFG]
if unknown:
    sys.exit(f"not entries in {os.path.basename(CONFIG)}: {', '.join(unknown)}")

t0 = time.time()
print(f"mode: {'MEASURE' if RUN else 'DRY RUN - loads nothing'}   config: {CONFIG}")
print(f"meminfo: {MEM}  ({mem_avail()} MiB free now)")
print(f"resident: {resident() or '[]'}")
for e in plan:
    print(f"  {e:20} live claim {CFG[e]['claim']}  family {CFG[e]['family']}")
if not RUN:
    print(f"~1.5-2.5 min per entry, so about {len(plan) * 2.5:.0f} min window; "
          f"{RESTORE} is unloaded for it and warmed again on the way out")
    if resident():
        print(f"REFUSE: pool not empty ({resident()}) - run it inside the window")
    sys.exit(0)

rows = []
for e in plan:
    since = time.time()
    if resident():
        print(f"  {e}: pool is not empty ({resident()}), stopping the sweep")
        break
    m = measure(e)
    void = evictions(since)
    rows.append((e, m, f"VOID ({len(void)} eviction line(s))" if void else "ok"))
    print(f"  {e:20} claim {CFG[e]['claim'] or 0:>6}  base {m['base']:>6}  "
          f"trough {m['trough']:>6}  settled {m['settled']:>6}  peak {m['peak']:>6}  "
          f"resid {m['resid']:>6}  {m['answered']}s via {m['how'] or 'UNDROVE'}  "
          f"{rows[-1][2]}")

print(f"restoring {RESTORE} ...")
try:
    post("/v1/chat/completions", {"model": RESTORE, "max_tokens": 8,
                                  "messages": [{"role": "user", "content": "ping"}]})
except Exception as ex:
    print(f"  restore failed ({type(ex).__name__}: {ex}) - the next request pays the "
          "cold load")
keep = [r for r in rows if r[2] == "ok" and r[1]["how"]]
if keep:
    print("\nentry                 live    peak   resid   suggested")
    for e, m, _ in keep:
        best = max(m["peak"], m["resid"])
        sug = int(round(best / 500) * 500)
        print(f"{e:20} {CFG[e]['claim'] or 0:>6}  {m['peak']:>6}  {m['resid']:>6}"
              f"   {sug:>6}  {sug - (CFG[e]['claim'] or 0):+}")
print(f"window: {int(time.time() - t0)} s over {len(rows)} entries, "
      f"{len(rows) - len(keep)} voided or undriven - write the kept ones into the "
      "config by hand, each with its method beside it")
PY
