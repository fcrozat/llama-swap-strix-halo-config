# TODO

Open decisions on the strix launchers. `AGENTS.md` holds the standing rules: how
to apply a config change without taking the agent's own model down, how to
measure what a model really costs, what is ours and what came out of the
llama-swap tarball.

Measured 2026-11-22. Three of the fourteen entries carry a measured number:
gufo-flash-next 112000 (111.8 GiB), loom-inkling 70000 (69.9 GiB), gufo-inkling
47000 (40864 MiB, vision projector included). The other eleven are still claims,
and flash-next was 3.3x under-declared until someone measured it, so assume the
eleven are too.

## 1. Measure the eleven entries that are still guesses

gufo-ds41 114000, laya 40000, ornith-35b-a3b 34000, hipfire-35b-a3b 32000,
hipfire-flash-next 32000, gufo-27b 30000, hipfire-27b 28000, gufo-deepseek 26000,
deepseek-v4-flash 26000, openjev-q4 26000, hipfire-4b 8000.

gufo-ds41 first: it is the largest single claim on the box and has never been
loaded here at all.

All ten except ds41 sit under 48000, which is the interesting property.

For each: the `load_started` -> `load_completed` delta (AGENTS.md, Memory), noted
against the sessions and context it was loaded with. Then re-check the 118000
pool ceiling against 124.4 GiB of physical RAM.

Why: loom-inkling at 70000 is allowed to share the pool with anything declared
under 48000, which is all ten of them. If any holds more than declared, that
co-residency is the same condition that produced the memory spike this config was
meant to prevent.

The 118000 ceiling is itself still the placeholder the config comment asks to
retighten to ~90% of physical: 118000 MiB is 92.6% of the 124.4 GiB (127386 MiB)
this box has. Settle it against the measured entries, not against the sum of the
guesses.

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

## 4. What the first inkling2 load left open

gufo-inkling is declared from the host delta (124441 -> 83577 = 40864 MiB with
the projector, 39972 without, at 4 sessions / 131072) but the same
`load_completed` line reports `gpu_device_used_mib=56150` (55250 without it). The
host delta is what the pool is about, so that is what was declared; if the device
figure is the real claim then 47000 lets in co-residency the box cannot pay. The
gap moved by 900 MiB with the projector, the same as the host delta did, so the
two figures track each other rather than one of them being wrong about the
projector. Read both again on the next load, and settle it by watching
/proc/meminfo while a second model loads beside it.

Also open on that entry:

- decode was 43.4 tok/s on one 48-token completion - not the head-to-head against
  the Loom engine it replaced as the `Inkling-2-Mini` name, and prefill was never
  measurable at 27 prompt tokens. Both numbers before the fallback is deleted.
- `enable_thinking: false` still returned 41 `reasoning_tokens` (content was
  right). The extension says reasoning-off is its own doing, not the template's,
  so check whether gufo's flag reaches it before clients rely on it.
- the entry inherits `--reasoning-effort xhigh` from `gufo_serve_tail`, which the
  extension maps to 0.99 against its own unset default of 0.9, and its M4 log
  says effort barely moves this model while `high`-to-`max` only lengthens the
  reasoning on some prompts - so Inkling may be paying latency for nothing.
  Unsloth's guide names no effort level, so nothing changed without the
  measurement: same prompt at xhigh and at high, compare reasoning length and
  whether the answer ever differs.
