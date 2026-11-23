# strix launchers

llama-swap routing config plus container launchers for one AMD Strix Halo box
(gfx1151, 124.4 GiB of unified CPU/GPU memory). Clients call llama-swap on
:8080 and name a model; llama-swap starts and stops every engine container
itself, rootless as uid 1000, each published on 127.0.0.1 so nothing bypasses it.

## Applying a change

**A save restarts the resident engine, so this unit ignores saves.**
`-watch-config` polls every 2 s and, when the config changes, stops the running
model container and starts it again - any save, even one that edits only a
comment, even for a model whose entry did not change. Observed: a save recreated
`ls-gufo-flash-next` and the cold reload took 61 s, with every client that wanted
that model waiting behind it. `run-llama-swap.sh` defaults it on, so `llama-swap.service` sets
`Environment=WATCH_CONFIG=false`. That file is tracked here and symlinked to
`~/.config/systemd/user/llama-swap.service`, so editing it edits the service -
`systemd-analyze --user verify llama-swap.service` checks it and `daemon-reload`
makes systemd read it, though the running unit keeps its old settings until it
restarts. Applying `capacity-ttl.yaml` is an explicit restart, never a file write.

Which leaves the etiquette the same either way: announced, between requests,
never while a person or another agent session could be mid-request.

`systemctl --user stop llama-swap` stays off the table outright: it takes away the
model this agent answers from and nothing returns it until the unit starts again.
To free memory with no config change, unload one model instead -
`podman stop ls-<model_id>` or `curl -X POST localhost:8080/api/models/unload/<model_id>`.

1. Look at what is warm first: `podman ps --format '{{.Names}}' | grep '^ls-'`.
   Anything resident is what the restart will interrupt.
2. Edit `capacity-ttl.yaml` (`config.yaml` is a symlink to it; keep it one), then
   validate with the package binary - `/usr/bin/llama-swap` on the host,
   `/run/host/usr/bin/llama-swap` inside a distrobox - done when it prints
   `config is valid: N model(s)` with N moved by exactly what was added.
3. `systemctl --user daemon-reload && systemctl --user restart llama-swap`, then
   wait for the preload's `Health check passed` in `curl -s localhost:8080/logs`;
   the box is not usable before that.
4. Confirm the id and its alias in `/v1/models`, and commit - the history is this
   file's changelog, one commit per behaviour change, explaining the number rather
   than just the edit.

Health is `/health` (swap) and `/ready` (a loaded engine). `/api/version` gives
the build actually running - `version`, `commit`, `build_date` - which is how a
package upgrade is confirmed. `/v1/models/{id}` is not implemented - it 404s for
good ids too, so never treat it as a health check.

## Ours vs vendored

`capacity-ttl.yaml` is the live config (`config.yaml` is a symlink to it),
`capacity-old.yaml` and `simple-routing.yaml` are earlier layouts kept for
reference, and `run-*.sh` (each documents itself in its header), `nix-loom-*.sh`,
`loom/`, `README.md`, `TODO.md` and `PUBLISHING.md` are ours; `README.md` is the
public intro the front page renders.

Nothing upstream is vendored, because nothing upstream arrives here: llama-swap
is a distro package. An engine upgrade is a package
transaction plus the announced restart above, rollback is the distro's own
snapshot tool, and neither is this repo's business - neither leaves a file in
this directory for `.gitignore` to mind. This tree publishes no license file:
upstream's MIT text was never ours to claim.
Upstream's config documentation is its own repo README. The live config and
`simple-routing.yaml` carry the schema modeline an editor resolves keys and pool
names against (`capacity-old.yaml` is a superseded snapshot, left as it was):

    # yaml-language-server: $schema=https://raw.githubusercontent.com/mostlygeek/llama-swap/refs/heads/main/config-schema.json

## Publishable history

This tree and its whole history are meant to be cloned by strangers, so write
every commit for that reader. Config paths take `${env.HOME}` (or the `home`
macro built on it) and prose takes `$USER` or `~`, which keeps the local account
name out of every blob. A commit message names a thing rather than quoting it -
"the literal absolute path", and a probe's output as the claim it supported.
The author identity is the one personal thing kept deliberately, on every
commit: it is a decision, so it stays.

Anything already committed is a history problem rather than an edit: audit the
object store, then rewrite it. `PUBLISHING.md` is that runbook - what clean
means, the five surfaces to grep, the `filter-repo` traps (`--replace-text`
reaches blobs only; binaries are skipped whole), and why the tip needs
hand-writing after a substitution. Every hash changes, so a first push is a
one-way door, so audit again before pushing. `TODO.md` §3 records what the last
audit found and that no remote is configured yet; `PUBLISHING.md` ends with the
`gh repo create` line.

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

Read the label though: hipfire's `free_after_weights=` is memory still free, not
a weight size. Its KV is `vmm` - the load says `0 MiB committed at load` and
commits per token as context grows - so what is resident after a short probe
says nothing about a long prompt, and a resident-set delta taken then
under-claims. For hipfire the claim is the full-context worst case, built from
its own lines: weights + `kv_bytes_per_token` x `max_seq` + prefill scratch +
draft/vision. That is a second method beside the delta, and it is worth saying
which one a number came from.

## Engines and their flag sets

Four run macro families (`run`, `gufo_run` / `gufo_ds41_run`, `hipfire_run`,
`loom_pod` + `loom_serve_llm`) with ports and mount sets that differ enough that
a new entry must copy its engine's macros rather than the nearest neighbour's.
llama-swap expands macros in file order, so the `gufo_*` fragments stay above the
run macros that use them. `${env.VAR}` is its own syntax for its process
environment, substituted before macro expansion; an unknown `${MACRO}` or an
unset `${env.VAR}` is a load error rather than an empty string, which is why the
account path is a `home` macro and not a bare `${HOME}`.

Two traps around gufo:

- After `podman pull`, run `./run-gufo.sh ext update`. A module compiled for
  another gufo build shows `needs update` and is skipped, so `gufo-ds41` fails
  to load. `run-gufo.sh` documents the extension workflow.
- Loom (Inkling) is not in the extension registry and needs extension API
  0.3.35 while the toolbox image is on 0.3.20 - hence the Nix-built gufo in the
  `gufo-nix` volume and `${loom_serve_llm}` naming `/loom/gufo` (bare `gufo` is
  not on that image's PATH). `loom/README.md` rebuilds it in ~3 minutes and
  re-points the symlinks (local artifacts, not tracked); the
  config needs no change. Only `loom-inkling` runs
  that way: `Inkling-2-Mini` itself is served by the `inkling2` module, which is
  in the registry, built for the toolbox image's API, and needs no Nix.

hipfire runs upstream's own image: `ghcr.io/warpfront/hipfire`, `full` variant
(ROCm 10.1.0-3, kernel packs for gfx1100/gfx1151/gfx1201 baked in), release tag
pinned in `hipfire_image`. A tag does not re-pull itself, so a bump is edit +
`podman pull` + restart. It serves as uid 1000 with `HOME=/home/hipfire`, so the
model store mounts at `/home/hipfire/.hipfire/models` and that bind needs `,z`:
the store is shared, and a `:Z` (private) run labels it with one container's
SELinux MCS categories - every later container then reads `failed to list model
directory: Permission denied (os error 13)` before a model is even chosen.

"Baked in" means the kernels ship, not that a route is chosen: 0.4.7 loads
`qwen3.5-4b` here as `no closed route plan (UnsupportedRoute("model arch 5 on
gfx1151 has no closed route"))` on a predicted fallback plan, with 42 `unplanned
kernel ... bound lazily` warnings after ready. Every tag here took a predicted
plan, for four different reasons; the load lines say which, so read them before
quoting that tag's speed.

`HIPFIRE_QWEN4_NPU_TRUNK=auto` is likewise not a promise of NPU work. It packed
2.0 GiB of panels for flash-next off a built-in calibration taken on kernel
`7.3.0-rc7-perfopt+` and build `hipfire-0.4.2:npu-trunk-bf16-rowmajor-v1` (this
host: `7.3.5-1-default`), then planned `rows=20 families=none plan=[gpu 0..20]
predicted=+0.0%`. It claims `/dev/accel/accel0` whatever it decides, so `npu: 1`
holds either way.

## Testing a model

Request it through llama-swap so the swap is exercised too, and take throughput
from gufo's `usage` fields (`completion_tokens_per_second`, `prefill_ms`), not
from curl's wall time: the first request includes the container start and load
(10-20 s for the big ones).

Ask the engine before paying for a swap. hipfire answers without touching the
pool: `hipfire list` (does the store read, which tag is each file) and
`hipfire fit <tag>` (installed, size, whether it fits, which route) take well
under a minute and load nothing - with 8.7 GiB free, `fit` on flash-next said
"installed, 116.7 GiB" and "DOES NOT FIT", which was the whole answer.

Give thinking models headroom - `max_tokens` near 1000 or more. Asked for 220,
Inkling spent 218 of them on reasoning and returned empty `content`.

Hipfire's Qwen tags are that trap with a documented fix: `max_tokens` covers the
`<think>` span, so 64 and 400 both came back `content: ""`,
`finish_reason: "length"`, budget gone on `reasoning_content`.
`"chat_template_kwargs": {"enable_thinking": false}` answers properly and
llama-swap forwards it unchanged; `reasoning_effort: "low"` does not - upstream
makes it prompt strength, never a think-token budget - and neither did the
`"thinking": "off"` form. hipfire's `usage` has no per-second fields and its
stream carries no `usage` at all, so throughput there is wall-clock divided by
`completion_tokens`, unlike gufo.

Capability fields lie. The inkling2 README says `/v1/models` advertises
`input_modalities: [text, image]` once a projector is loaded; on gufo 0.35.0 no
entry carries that key, and llama-swap strips what it does not know anyway. Prove
a modality by asking for it - a real image request that answers correctly - not
by a field.

Names have three meanings: the `gufo model install` id (`inkling-2-mini-loom`),
`useModelName` sent upstream (`Inkling-2-Mini`), and `aliases` clients may send.
Request the alias, not the install id.

## Paths

A `-v` argument resolves in podman's mount namespace: `/var/lib/models/llama`.
From this shell the same files appear as `/run/host/var/lib/models/llama`, and
passing that to `-v` fails with `statfs ... no such file or directory`.
`run-llama-swap.sh` makes the host path exist inside a distrobox once, so the
config says `/var/lib/models` and works in both places.
