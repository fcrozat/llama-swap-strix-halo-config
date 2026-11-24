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
reference, and `run-*.sh` (each documents itself in its header),
`README.md`, `TODO.md` and `PUBLISHING.md` are ours; `README.md` is the
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
audit found and how the first push went; `PUBLISHING.md` ends with the
`gh repo create` line for a box that has no remote yet.

## Memory: measured, not guessed

The pool is the binding constraint, not the GPU -
`routing.router.settings.capacity.pools.mem: 124000` MiB allowed resident at
once, `evict_cost` decides who leaves, `globalTTL: 900` reclaims after idle, and
`npu: 1` keeps a single hipfire container on `/dev/accel/accel0`. That ceiling
was raised to its current value rather than tightened: 124000 is 97.3% of the
box, because the largest measured model costs 122002 and a ceiling below a model
means llama-swap refuses to start it. Nothing protects the machine except that
the top two claims cannot coexist with much of anything.

Why a model vanished is one grep, and it is also the check on the measurement
below: `journalctl --user -u llama-swap | grep 'capacity: model='` prints
`capacity: model=gufo-flash-next evict=[loom-inkling] pools=map[mem:118000 ...]`
and names the model someone asked for and who was stopped to make room. Read it
as an observation, not a schema: the pool value is what the config held that day
and `loom-inkling` is an entry this file no longer has. The `model=` / `evict=`
pair is the answer; the numbers beside it are not.

Read `host_available_mib` from the engine's own `load_started` / `load_completed`
lines (`podman logs ls-<id>`) and use the delta, but only from a load that
loaded alone: a load that evicted something reports the evicted container's
memory coming back while its own goes out, so the delta is wrong in whichever
direction the churn went. RSS lies: flash-next reports 6.4 GiB of RSS while
holding 111.8 GiB, `Mlocked` stays 0, and the rest is kfd device memory no
container stat shows. Every `capacities: {mem:}` is a claim
about physical RAM; a guessed one is how two models get loaded that do not fit.
An engine's delta is what that engine counts, which is not always what the host
is short: gufo-deepseek reports 101145 while the host gave up 112863, the gap
being expert staging and its component cache. Take both and claim the larger.

For a gufo entry a third figure has to be weighed: the same load that moved
MemAvailable by 41208 reported `gpu_device_used_mib=56348`. Two instruments 15
GiB apart on a box with one pool of RAM, and which one is physically right is
not settled here - that the host reading is not safe alone is. So a gufo row is
the larger of the two at `load_completed`. Settling is worse still: the host
residue fell to 7696 once the weights were uploaded, so a settled reading is the
staging buffers rather than the model and under-states the load 7x. What would
settle the device figure is a second model loaded beside it with /proc/meminfo
watched the whole way, not a third reading of the same load.

llama.cpp logs no `host_available_mib` at all, so for its entries the method is
to sample `/run/host/proc/meminfo` every half second across the load and take
the trough. Two things make that trustworthy. Empty the pool first and verify it
empty: this box answers from one of its own models, so a request you did not
plan for reloads 112 GiB between two entries and the baseline becomes the model
being evicted - two rows of the first sweep were void that way. And take a
repeat: qwen3.8-27b measured 54883, then 54674 with its 17 GiB of weights
already in the page cache, 0.4% apart, which is what shows the trough is the
resident set and not cached file reads. Settled and trough agreed on every row
of that sweep, so llama.cpp commits KV at init and `--ctx-size` - 131072 in the
run macro - sets the bill before a token is read. `TODO.md` §1 has the table.

Read the label though: hipfire's `free_after_weights=` is memory still free, not
a weight size. Its KV is `vmm` - the load says `0 MiB committed at load` and
commits per token as context grows - so what is resident after a short probe
says nothing about a long prompt, and a resident-set delta taken then
under-claims. For hipfire the claim is the full-context worst case, built from
its own lines: weights + `kv_bytes_per_token` x `max_seq` + prefill scratch +
draft/vision. That is a second method beside the delta, and it is worth saying
which one a number came from.

## Measuring without other clients in the sample

`:8080` on the wildcard address means the LAN and the tailscale interface share
the engine mid-measurement, so a delta or a tok/s figure can carry someone
else's queue - `gufo_sessions` batches four of them together. Pin the swap to
loopback for the window with a drop-in nothing tracks. It has to be a drop-in:
the unit's own `Environment=LISTEN=:8080` beats the manager environment, so
`systemctl --user set-environment` changes nothing.

```sh
D=${XDG_RUNTIME_DIR}/systemd/user/llama-swap.service.d/loopback.conf
mkdir -p "${D%/*}"
printf '[Service]\nEnvironment=LISTEN=127.0.0.1:8080\n' > "$D"
systemctl --user daemon-reload && systemctl --user restart llama-swap
# afterwards, for everyone again:
rm "$D" && systemctl --user daemon-reload && systemctl --user restart llama-swap
```

Under `$XDG_RUNTIME_DIR` on purpose: a reboot clears it, so a forgotten lock
cannot outlive the window. Prove it took twice - `systemctl --user show
llama-swap -p Environment` prints the loopback value, and a request to any other
address of the box, its LAN one or its tailscale one, refuses while
`localhost:8080/health` answers 200. A distrobox keeps working, because pasta
forwards the container's localhost to the host loopback; that is what lets a
shell in here measure a box shut to everything else.

It costs both monitoring jobs, not one. The `llama-swap` job (the `/metrics`
scrape of `host.containers.internal:8080`) goes `up == 0` straight away. The
`llama-swap-activity` exporter polls the same address, so it keeps serving its
last state, logs `poll failed ... Connection refused` every 10 s, and trips its
`last_poll_timestamp > 180` rule - which is expected for the window, not a
fault. If an agent runs this while it is served by the box itself, a detached
watchdog that probes `127.0.0.1:8080` and removes the drop-in on failure is
cheap insurance: the same forwarding that lets it measure is the only thing
keeping its own session alive. Clear the lock by hand when the window closes,
though: `pkill -f loopback-watchdog` matches the command line of the shell that
runs it and kills that shell before its `rm`.

Serving yourself is the harder half, and the only shape that survives it is one
synchronous tool call per sweep. A detached batch with its wait in a separate
call cannot work: returning from the wait is itself a request to your own model,
so the box reloads its 112 GiB engine inside the window and the baseline becomes
that eviction - that voided rows twice on 2026-11-24.

Nor is your session the only one. Ninety idle seconds logged six
`/v1/chat/completions` against the preload model, one of them a 108114-token
prompt, so a live agent works on these models and stopping its engine answers
the in-flight request with a 500. Unload what you are served by, keep every
model request out of the window, and read a `capacity: model=... evict=[...]`
line dated inside that window as grounds to void the row: something else wanted
a model while you were measuring.

An unmanaged probe container is worse than inaccurate, it is unsafe: the router's
pool arithmetic cannot see what a container it did not start is holding, so it
will load 112000 of managed pool onto a box where a probe has already taken
88 GiB. So a probe measures only from a pool verified empty, and the sweep says
so out loud when it refuses one (`24753 MiB free at 13:33`), with a guard that
stops a reloaded `ls-*` container for the length of the probe rather than letting
both land.

## Engines and their flag sets

Three run macro families (`run`, `gufo_run` / `gufo_ds41_run`, `hipfire_run`)
with ports and mount sets that differ enough that
a new entry must copy its engine's macros rather than the nearest neighbour's.
llama-swap expands macros in file order, so the `gufo_*` fragments stay above the
run macros that use them. `${env.VAR}` is its own syntax for its process
environment, substituted before macro expansion; an unknown `${MACRO}` or an
unset `${env.VAR}` is a load error rather than an empty string, which is why the
account path is a `home` macro and not a bare `${HOME}`.

Traps around gufo:

- After `podman pull`, run `./run-gufo.sh ext update`. A module compiled for
  another gufo build shows `needs update` and is skipped, so `gufo-ds41` fails
  to load. Nothing announces the skip to a client: `/ready` still answers 200
  and the server only logs `extension <name> is not built for this gufo`, so
  read that log after a pull rather than trusting the health check. The update
  needs no window - store only, no GPU, no port, and a running server keeps the
  set it already loaded. `gufo --version` names the build and the extension API
  it speaks; read both before trusting a module list.
- A module the image cannot build at all is worse than a stale one, and
  `ext list` says so in its own words ("no reviewed release supports linux and
  extension API x.y.z") rather than as `needs update`. Read the whole list after
  an upgrade, not just the rows belonging to installed modules.
- Loom is not an engine on this box. A loom *package* is a directory whose
  `llm_config.json` names an arch and a GGUF (`inkling-2-mini-loom`: arch
  `inkling2`, `Inkling-2-Mini-UD-Q4_K_XL.gguf`, vocab 200058), and gufo 0.36.0
  resolves `--model <package id>` to that GGUF and serves it on its own arch
  support. So `gufo model list` saying `installed, no loaded extension offers
  it` about a package id, while `serve llm --model <that id>` answers 200, is
  two different questions - the first is which extension advertises the id, the
  second is what the loader can read. Only `GUFO_MODELS_DIR` is needed to point
  at the store; `${gufo_pod}` mounts it without naming it.
  The `loom` module itself was tried and is gone: it builds against the image's
  `libloom_text_embed.so` and seats over the built-in, then dies at
  `load_started` with `fatal_signal signal=11` some 230 ms into the container,
  pool free and `seccomp=unconfined` both on and off. It is not in the reviewed
  registry (so `ext update` would rebuild it but never move it), it is removed
  from the live store, and `TODO.md` §6 keeps the numbers in case it is ever
  revisited. Nothing installed here needs Loom's kernels. What survives is the
  recipe: `--env GUFO_MODELS_DIR=/models` (which `${gufo_pod}` mounts but does
  not set) plus `--model inkling-2-mini-loom` runs the same weights through the
  core loader with no module, the fix for the stale-module trap above.
  `gufo-inkling` itself keeps the two paths, because the module route is the one
  that carries `--mmproj` and so vision. A second entry ran the module-free form
  until 2026-11-24, when one set of weights costing 70000 as two entries was
  folded into it; a month of journal held no request for the removed alias.

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
