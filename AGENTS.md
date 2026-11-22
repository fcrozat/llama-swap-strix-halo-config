# strix launchers

llama-swap routing config plus container launchers for one AMD Strix Halo box
(gfx1151, 124.4 GiB of unified CPU/GPU memory). Clients call llama-swap on
:8080 and name a model; llama-swap starts and stops every engine container
itself, rootless as uid 1000, each published on 127.0.0.1 so nothing bypasses it.

## Applying a change

**A save restarts the resident engine.** `-watch-config` is on by default
(`WATCH_CONFIG=false` in `run-llama-swap.sh` turns it off) and polls every 2 s.
When the config changes, llama-swap stops the running model container and starts
it again - any save, even one that edits only a comment, and even for a model
whose entry did not change. Observed: a save recreated `ls-gufo-flash-next` and
the cold reload took 61 s, and every client that wanted that model waited with
it. So a save is a service action: announced, done between requests, and never
while a person or another agent session could be mid-request. That is the same
care as `systemctl --user restart llama-swap` needs, which is heavier only
because the proxy goes down too.

`systemctl --user stop llama-swap` stays off the table outright: it takes away the
model this agent answers from and nothing returns it until the unit starts again.
To free memory with no config change, unload one model instead -
`podman stop ls-<model_id>` or `curl -X POST localhost:8080/api/models/unload/<model_id>`.

1. Look at what is warm first: `podman ps --format '{{.Names}}' | grep '^ls-'`.
   Anything resident is what the save will interrupt.
2. Edit `capacity-ttl.yaml` (`config.yaml` is a symlink to it; keep it one), then
   `./llama-swap -config config.yaml -validate` - done when it prints
   `config is valid: N model(s)` with N moved by exactly what was added.
3. Save, then wait for `configuration reloaded` followed by `Health check passed`
   in `curl -s localhost:8080/logs`; the box is not usable before that.
4. Confirm the id and its alias in `/v1/models`, and commit - the history is this
   file's changelog, one commit per behaviour change, explaining the number rather
   than just the edit.

Health is `/health` (swap) and `/ready` (a loaded engine). `/v1/models/{id}` is
not implemented - it 404s for good ids too, so never treat it as a health check.

## Ours vs vendored

`capacity-ttl.yaml` is the live config (`config.yaml` is a symlink to it),
`capacity-old.yaml` and `simple-routing.yaml` are earlier layouts kept for
reference, and `run-*.sh` (each documents itself in its header), `nix-loom-*.sh`,
`loom/` and `TODO.md` are ours.

Nothing upstream is tracked. A release tarball drops `README.md`, `CHANGELOG.md`
and a `changelog/` tree; `.gitignore` keeps those out beside the `llama-swap` /
`llama-swap.v*` pins and `*.tar.gz` - downloads, not source. `LICENSE.md` stays.
Upstream's config documentation is its own repo README. The live config and
`simple-routing.yaml` carry the schema modeline an editor resolves keys and pool
names against (`capacity-old.yaml` is a superseded snapshot, left as it was):

    # yaml-language-server: $schema=https://raw.githubusercontent.com/mostlygeek/llama-swap/refs/heads/main/config-schema.json

## Memory: measured, not guessed

The pool is the binding constraint, not the GPU -
`routing.router.settings.capacity.pools.mem: 118000` MiB allowed resident at
once, `evict_cost` decides who leaves, `globalTTL: 900` reclaims after idle, and
`npu: 1` keeps a single hipfire container on `/dev/accel/accel0`.

Read `host_available_mib` from the engine's own `load_started` / `load_completed`
lines (`podman logs ls-<id>`) and use the delta. RSS lies: flash-next reports
6.4 GiB of RSS while holding 111.8 GiB, `Mlocked` stays 0, and the rest is kfd
device memory no container stat shows. Every `capacities: {mem:}` is a claim
about physical RAM; a guessed one is how two models get loaded that do not fit.
`TODO.md` lists the entries still resting on a guess.

## Engines and their flag sets

Four run macro families (`run`, `gufo_run` / `gufo_ds41_run`, `hipfire_run`,
`loom_pod` + `loom_serve_llm`) with ports and mount sets that differ enough that
a new entry must copy its engine's macros rather than the nearest neighbour's.
llama-swap expands macros in file order, so the `gufo_*` fragments stay above the
run macros that use them.

Two traps around gufo:

- After `podman pull`, run `./run-gufo.sh ext update`. A module compiled for
  another gufo build shows `needs update` and is skipped, so `gufo-ds41` fails
  to load. `run-gufo.sh` documents the extension workflow.
- Loom (Inkling) is not in the extension registry and needs extension API
  0.3.35 while the toolbox image is on 0.3.20 - hence the Nix-built gufo in the
  `gufo-nix` volume and `${loom_serve_llm}` naming `/loom/gufo` (bare `gufo` is
  not on that image's PATH). `loom/README.md` rebuilds it in ~3 minutes and
  re-points the symlinks; the config needs no change.

## Testing a model

Request it through llama-swap so the swap is exercised too, and take throughput
from gufo's `usage` fields (`completion_tokens_per_second`, `prefill_ms`), not
from curl's wall time: the first request includes the container start and load
(10-20 s for the big ones).

Give thinking models headroom - `max_tokens` near 1000 or more. Asked for 220,
Inkling spent 218 of them on reasoning and returned empty `content`.

Names have three meanings: the `gufo model install` id (`inkling-2-mini-loom`),
`useModelName` sent upstream (`Inkling-2-Mini`), and `aliases` clients may send.
Request the alias, not the install id.

## Paths

A `-v` argument resolves in podman's mount namespace: `/var/lib/models/llama`.
From this shell the same files appear as `/run/host/var/lib/models/llama`, and
passing that to `-v` fails with `statfs ... no such file or directory`.
`run-llama-swap.sh` makes the host path exist inside a distrobox once, so the
config says `/var/lib/models` and works in both places.
