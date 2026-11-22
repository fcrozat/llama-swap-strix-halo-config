# TODO

Work items for the strix launchers. `README.md`, `CHANGELOG.md` and `LICENSE.md`
in this directory came out of the llama-swap release tarball and are upstream
files; `capacity-ttl.yaml`, `run-*.sh`, `nix-loom-*.sh`, `loom/` and this file
are ours.

Two things every item here depends on:

- Never `systemctl --user stop llama-swap` from an agent session. The unit serves
  the model the agent itself runs on (`PI_PROVIDER=llama-chooser`), so a stop
  takes the assistant down until something starts it again. A `restart` is brief
  and `-watch-config` (on by default in `run-llama-swap.sh`) applies config edits
  without one. To free memory held by a single model: `podman stop ls-<name>` or
  `curl -X POST localhost:8080/api/models/unload/<model_id>`.
- Size from `host_available_mib`, never from RSS. The gufo loader prints
  `host_available_mib` at `load_started` and `load_completed`; RSS showed 6.4 GiB
  for a model holding 111.8 GiB, and `Mlocked` stayed 0, because the bulk is kfd
  device memory and streaming buffers.

Measured 2026-11-22 on the 124.4 GiB box, baseline 122.0 GiB available with no
model container running (the 2.4 GiB is grafana, prometheus, tumbleweed):

| entry           | declared | really holds       |
|-----------------|----------|--------------------|
| gufo-flash-next | 112000   | 111.8 GiB (was 34000) |
| loom-inkling    | 70000    | 69.9 GiB           |
| gufo-ds41       | 114000   | not measured       |

## 1. Measure the five entries that are still guesses

hipfire-4b 8000, gufo-deepseek 26000, deepseek-v4-flash 26000, hipfire-27b 28000,
gufo-27b 30000. flash-next was 3.3x under-declared, so assume the others are too
until shown otherwise.

For each: `podman logs ls-<name> | grep host_available_mib`, take the
before/after delta, and note the sessions/context it was loaded with. Then
re-check the `globalCapacity` pool ceiling (118000) against 124.4 GiB of RAM.

Why: loom-inkling at 70000 is allowed to share the pool with anything declared
under 48000, which is all five. If any of them holds more than declared, that
co-residency is the same condition that produced the memory spike this config was
meant to prevent.

## 2. Decide whether flash-next exclusivity is acceptable

With its measured 112000 it cannot share the 118000 pool with anything, so every
model switch evicts it and the next request pays a 10-20 s cold load. It is also
the preload model and the one interactive sessions run on, so the switch cost is
paid by whoever types next.

That is what already happened physically; the number only says so out loud. If
the cost is unwanted, bound the footprint instead of reflating the number back to
34000:

- `--sessions 4` -> 2 (state and KV per session)
- `--context 131072` -> whatever the clients actually use
- `--cache-ram-bytes N` (default is auto: half of free RAM, capped at 32 GiB)

Rough targets, measured the same way as the baseline: under 48000 lets it coexist
with loom-inkling, under 4000 also with a 27b. Write the chosen tradeoff into the
entry's comment so the next reader does not undo it.

Open question for the same pass: which models do we actually want resident at the
same time? gufo-ds41 (114000) and loom-inkling (70000) are each exclusive-ish by
design, and preload says flash-next should be the warm default.

## 3. Give the repo a remote

`main` is local-only (`cbb4105`, `1565c9a`, `88dfd1a` and whatever follows) with
no remote configured, so the recovery notes in `loom/README.md` exist on one
disk.

Decide what is publishable before it leaves the box:

- `capacity-ttl.yaml` carries local absolute paths, ports, exact model filenames
  and the strix sizing notes.
- `loom/README.md`, `nix-loom-build.sh` and `nix-loom-gufo.sh` are host-agnostic
  and would be useful to anyone building gufo + Loom on Nix.
- `.gitignore` already keeps out the llama-swap binaries, `*.tar.gz`, the vendored
  `changelog/` tree, `*.log`, `*.pid`, `*.sock`.

Options: one private remote for everything, or split the reusable Nix/Loom part
into a public repo and keep the sizing file private. Either way, re-read the diff
for anything sensitive first - nothing was added deliberately, but the config is
host-specific by nature.
