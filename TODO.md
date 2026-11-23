# TODO

Open decisions on the strix launchers. `AGENTS.md` holds the standing rules: how
to apply a config change without taking the agent's own model down, how to
measure what a model really costs, and what belongs to the distro package rather
than to this tree.

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

`main` is local-only with no remote configured, so the recovery notes in
`loom/README.md` exist on one disk. The publish decision is made; only the
remote is missing.

Audited before publishing, every blob in the history rather than just HEAD (the
procedure and the checks are `PUBLISHING.md`): no credentials, no emails, no
`user:pass@` URLs, no private key material, and the only addresses anywhere are
`0.0.0.0` and `127.0.0.1`. Nothing names private
infrastructure either - `ghcr.io/gufo-org/toolboxes/gufo-runtime`,
`ghcr.io/yamz-labs/kyojin-glm` and the `kyuz0` toolbox all pull anonymously and
this box holds no registry credentials at all. Publishing with the real author
identity, deliberately.

History rewritten first, with every commit kept: llama-swap's own `README.md`,
`CHANGELOG.md` and `LICENSE.md` are out of it, the first two because they were
tracked before being gitignored and the third because its MIT text carries
upstream's copyright, not this tree's. Every hash changed. The `loom/gufo`
symlinks still appear in the older commits - they point at a `/nix/store`
output, which is a build id and not a secret. A second pass then rewrote the
local account name out of every blob and every commit message: config paths read
`${env.HOME}`, which llama-swap substitutes for real, and the comments address
the reader as `$USER`.

What a clone gets is 18 files and 95 KiB (the `config.yaml` symlink counted as
a link, not twice as its target): no binaries, no weights, no upstream
docs, and no local account name anywhere in the object store. Two safety bundles
sit in the home directory, both taken before the scrub, so both still carry the
name - `launchers-pre-rewrite.bundle` additionally carries the upstream docs.
Both go once this history is confirmed good.

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

## 5. What the hipfire image switch left open

The four `hipfire-*` entries now run upstream's `ghcr.io/warpfront/hipfire:0.4.7`
in place of a local build of 0.4.2+patch.1. Verified without loading a model,
because the box had 8.7 GiB free and gufo-flash-next resident as every switch's
eviction candidate: the store reads, all four served tags resolve to files
already on disk (`fit` calls flash-next "installed, 116.7 GiB" - 0.4.7 still
honours the monolithic files the older build pulled), gfx1151 kernel packs are
baked in, and `serve <tag> 0.0.0.0:11435` still parses.

Not verified: a completion, the NPU trunk route, and what 0.4.7 actually holds.
`hipfire-4b` at 8000 is the cheapest way to find out, and 8000 is a guess like
the rest of section 1.

Also open on this engine:

- `${env.HOME}/hipfire-kcache` is mounted but `$HIPFIRE_HOME` is not, and the
  containers are `--rm`, so hipfire rebuilds its own state at every start - a
  `fit` of flash-next wrote a 429 MiB PLE hot-store index under it. Upstream
  mounts a `hipfire-config` volume for exactly that. Worth a bind only if the
  rebuild shows up in the cold-start time; measure before adding a mount.
- `qwen3.8:flash-next-mq4-xts-symtrunk`, 66.0 GiB per `fit`, is a rung 0.4.2 did
  not offer. At 66000 it is the first flash-next that could share the 118000
  pool with anything, which is the question section 2 asks about the gufo entry.
