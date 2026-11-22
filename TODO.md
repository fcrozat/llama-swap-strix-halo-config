# TODO

Open decisions on the strix launchers. `AGENTS.md` holds the standing rules: how
to apply a config change without taking the agent's own model down, how to
measure what a model really costs, what is ours and what came out of the
llama-swap tarball.

Measured 2026-11-22, with 122.0 GiB available and no model container running (the
2.4 GiB is grafana, prometheus, tumbleweed): gufo-flash-next 111.8 GiB against a
declared 34000, loom-inkling 69.9 GiB against 70000, gufo-ds41 114000 chosen but
never measured.

## 1. Measure the five entries that are still guesses

hipfire-4b 8000, gufo-deepseek 26000, deepseek-v4-flash 26000, hipfire-27b 28000,
gufo-27b 30000. flash-next was 3.3x under-declared, so assume the others are too
until shown otherwise.

For each: the `load_started` -> `load_completed` delta (AGENTS.md, Memory), noted
against the sessions and context it was loaded with. Then re-check the 118000
pool ceiling against 124.4 GiB of physical RAM.

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

Options: one private remote for everything, or split the reusable Nix/Loom part
into a public repo and keep the sizing file private. Either way, re-read the diff
for anything sensitive first - nothing was added deliberately, but the config is
host-specific by nature.
