# TODO

Open decisions on the strix launchers. `AGENTS.md` holds the standing rules: how
to apply a config change without taking the agent's own model down, how to
measure what a model really costs, and what belongs to the distro package rather
than to this tree.

Measured 2026-11-22. Of the eighteen entries, three carry a number from the host
delta: gufo-flash-next 112000 (111.8 GiB), loom-inkling 70000 (69.9 GiB),
gufo-inkling 47000 (40864 MiB, with its projector). Four - the `hipfire-*`
set - are composed from the engine's own load lines, which is a different method
and says so in the entry (section 5). The other eleven are still claims, and
flash-next was 3.3x under-declared until someone measured it, so assume the
eleven are too.

## 1. Measure the eleven entries that are still guesses

gufo-ds41 114000, qwen3.6-27b-q8 45000, qwen3.8-27b-q8 45000, laya 40000,
ornith-35b-a3b 34000, qwen3.8-35b-a3b 34000, gufo-27b 30000, qwen3.8-27b 30000,
gufo-deepseek 26000, deepseek-v4-flash 26000, openjev-q4 26000.

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
`loom/README.md` exist on one disk. The publish decision is made and so is the
name: `llama-swap-strix-halo-config`, engine first, then AMD's name for this
silicon - plain "Strix" is a pentesting tool and a different APU family than
the gfx1151 here. Only the remote itself is missing.

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

## 5. What the hipfire image switch measured, and what it left open

The four `hipfire-*` entries now run upstream's `ghcr.io/warpfront/hipfire:0.4.7`
in place of a local build of 0.4.2+patch.1. Verified without loading a model,
because the box had 8.7 GiB free and gufo-flash-next resident as every switch's
eviction candidate: the store reads, all four served tags resolve to files
already on disk (`fit` calls flash-next "installed, 116.7 GiB" - 0.4.7 still
honours the monolithic files the older build pulled), gfx1151 kernel packs are
baked in, and `serve <tag> 0.0.0.0:11435` still parses.

All four have since been loaded through the swap: `hipfire-4b` first, three
cycles, then 27b, 35b-a3b and flash-next. Each pass runs in one shell call -
spread across turns and the testing session's own flash-next traffic evicts the
model under test between them, which is what the first attempt did.

- They serve. `/ready` 5-15 s from an idle box (95 s for flash-next), streaming
  intact. hipfire's `usage` carries no per-second fields and its stream carries
  no `usage` at all, so the gufo trick in AGENTS.md does not transfer - but
  hipfire logs its own rate, and that is the better figure: `drafter=dflash
  tau=1.29 tok/s=19.7` on 27b, `drafter=mtp tau=0.85 tok/s=36.9` on flash-next.
  Wall
  divided by `completion_tokens` gave 66.7 tok/s on 4b and 89.0 on 35b-a3b (a
  2 s sample, so treat it as an order of magnitude).
- `podman stats` reads `0B` for these containers, so the accounting comes from
  the engine's own lines. Correction to what an earlier pass of this section
  said: 4101 MiB was never 4b's weight figure - `free_after_weights=` is memory
  still free, and differencing it against a remembered baseline invented a
  number. `fit` says 4b is 2.4 GiB installed (2468 MiB on disk) and plans 3.2
  GiB of it device-side.
- KV is `vmm`: `0 MiB committed at load`, then `kv_mapped_growth_per_token` as
  context is used. So a resident-set delta after a short probe under-claims, and
  each entry now holds the full-context worst case built as weights +
  `kv_bytes_per_token` x 262144 + prefill scratch + draft/vision:
  - `hipfire-4b` 8000 -> 9000: 3277 + 17408 B/tok (4352) + 1251 = 8973.
  - `hipfire-27b` 28000 -> 29000: 14937 + 34816 B/tok (8704) + 1746 transient +
    1810 dflash draft + ~420 vision staging and activation reserve.
  - `hipfire-35b-a3b` 32000 -> 25000: 18139 + 10880 B/tok (2720) + 2793 = 23652.
    Its 462 MiB `.mtp` sits on disk unclaimed - the load says spec off - so the
    old number spent 7 GiB of pool on a buffer that never loads.
  - `hipfire-flash-next` 32000 -> 95000: 62475 routed experts + 5115
    non-expert + 15045 reserve (its own census, which beats its 12126
    historical floor), plus the 6747 it commits at 262144 (5408 QSA context +
    512 gather + 827 MTP). `MemAvailable` fell from ~121 GiB to 33 with only it
    resident, ~88 GiB, so the composed figure and the host agree within a few.
- Two of those were wrong in opposite directions and the dangerous one was the
  small one. At 32000 the router would seat hipfire-flash-next beside
  loom-inkling (70000) because 102000 < 118000, while the pair would hold
  ~165000 of a 124.4 GiB box. With 95000 it says so before starting:
  `capacity: model=hipfire-flash-next evict=[gufo-flash-next] pools=map[mem:
  118000 npu:1]`. The eviction that used to happen physically is now a routing
  decision. It is exclusive by arithmetic too, not just `npu: 1`: the smallest
  claim that is not another hipfire entry is 26000, and 95000 + 26000 is 121000.
- `kernels: no closed route plan` on every tag, for four different reasons: arch
  5 (4b) and arch 6 (35b-a3b) both `UnsupportedRoute`, 27b because of its DFlash
  draft, flash-next because of the trunk overlay. All four then ran `predicted
  fallback ready, open (never sealed)` with unplanned kernels bound lazily after
  ready. The gfx1151 packs ship and verify; nothing on this card gets a sealed
  plan, so a hipfire throughput figure is measured-here, not
  guaranteed-by-upstream. Read the load lines of any tag before trusting its
  speed.
- Host deltas across time are worthless on this engine: with hipfire-4b
  resident, avail read 121001/121002/121003 MiB across three runs, while
  flash-next resident read 17159, 22002 and 25893 in the same state. The weights
  are read-only and file-backed, so they sit in reclaimable cache that
  `MemAvailable` counts as free. Use the engine's own logged figures.
- Thinking is the trap on all four entries, and upstream documents it: 64
  tokens and 400 both came back `content: ""`, `finish_reason: length`, all
  budget spent in `reasoning_content`. `chat_template_kwargs:
  {"enable_thinking": false}` fixed it end to end through llama-swap (295 chars
  of content, reasoning empty); `reasoning_effort: "low"` did not, as upstream
  says it would not - effort is prompt strength, never a think-token budget -
  and the `"thinking": "off"` form it also lists did not take on this tag.
  gufo's inkling2 extension ignored the same switch (section 4), so engine by
  engine, not by analogy.
- The NPU trunk engages and then takes nothing. For flash-next it packed 2.0 GiB
  of panels (`resident_bytes=2113536000`, `pack_ms=809`) against a built-in
  calibration measured on kernel `7.3.0-rc7-perfopt+`, GPU `0000:c0:00.0`, build
  `hipfire-0.4.2:npu-trunk-bf16-rowmajor-v1` - this host is `7.3.5-1-default` on
  `0000:c5:00.0` - and returned `rows=20 families=none plan=[gpu 0..20]
  predicted=+0.0%`. Whether a many-thousand-row prefill routes differently is
  unmeasured; the container claims `/dev/accel/accel0` either way, so `npu: 1`
  is not the thing at issue.
- The restart that applied these numbers took ~180 s to report the preload
  ready, against the 63 s measured an hour earlier on the same config. The
  difference: a 116.7 GiB model had just been through the page cache. Budget the
  long number after a big-model pass.

Also open on this engine:

- `${env.HOME}/hipfire-kcache` is mounted but `$HIPFIRE_HOME` is not, and the
  containers are `--rm`, so hipfire rebuilds its own state at every start - a
  `fit` of flash-next wrote a 429 MiB PLE hot-store index under it. Upstream
  mounts a `hipfire-config` volume for exactly that. Worth a bind only if the
  rebuild shows up in the cold-start time; measure before adding a mount.
- `qwen3.8:flash-next-mq4-xts-symtrunk`, 66.0 GiB per `fit`, is a rung 0.4.2 did
  not offer. At 66000 it is the first flash-next that could share the 118000
  pool with anything, which is the question section 2 asks about the gufo entry.

## 6. Serve Inkling on Loom from the toolbox image, without Nix

`ghcr.io/gufo-org/toolboxes/gufo-runtime:latest` is gufo 0.36.0 (`4a7d8c6`) on
extension API 0.3.42. Both installed modules had been skipped since that pull:
`gufo serve` logged `extension deepseek41flash is not built for this gufo` and
the same for `inkling2` while `/ready` kept answering 200.
`./run-gufo.sh ext update` rebuilt both (`Updated deepseek41flash 0.3.0`,
`Updated inkling2 0.1.2`) and neither offered a newer reviewed release. Every
`gufo serve` flag the six gufo entries pass still parses - the misses against
`serve llm --help` were podman flags plus `--stream-experts`, which is a
`deepseek41flash` option rather than a core one.

The Nix build (the 5.9 GiB `gufo-nix` volume, `nix-loom-build.sh`,
`nix-loom-gufo.sh` and the two `loom/` symlinks) exists because loom wanted API
0.3.35 and the image had 0.3.20. Measured against a scratch store
(`EXT_DIR=/tmp/gufo-ext-probe`, so the live store never saw it):

- The image ships the dependency: `libloom_text_embed.so`, plus a
  `loom-runtime-0.2.0` store path holding `loom_text_embed.h`,
  `loom_text_embed.cmake` and a pkg-config file - the `CMAKE_PREFIX_PATH`
  upstream asks for.
- `gufo extension install
  https://github.com/loom-fun/loom-gufo-extension@v0.3.7 --replace-builtin
  --yes` built and installed in under 90 s; v0.3.7 resolves to `e98bed99`, the
  `inkling-0.3.7` merge.
- `--version` then reports `loom 0.3.7 (module:....so)` where the built-in
  `0.3.6` was, and `model list` says `inkling-2-mini-loom  18.1 GB  installed
  (package, checkpoint)` - the line the Nix gufo gives, against the image's
  `no loaded extension offers it`. That is the whole remaining gap: upstream
  added Inkling-2-Mini in loom 0.3.7, the image bundles 0.3.6.

Then the load test, which is the answer: no. `loom-inkling` was repointed at
`${gufo_pod} --env GUFO_MODELS_DIR=/models ${gufo_image} ${gufo_serve_llm}
--model inkling-2-mini-loom`, validated (`config is valid: 18 model(s)`) and
asked for through the swap - which evicted `gufo-flash-next` to make room, so
the pool was free when it died:

    [loader] event=load_started kind=text
      artifact=/models/inkling-2-mini-loom host_available_mib=124212
    [ERROR] [server] event=fatal_signal signal=11

Three attempts, identical each time: about 230 ms from `container start` to
`container died`, `upstream command exited prematurely` in the swap log, HTTP
500 to the client. `artifact=` names the package directory, so
`GUFO_MODELS_DIR`, the module's offer and the command line are all fine, and
124212 MiB available rules out memory.

- `seccomp` was the first suspect, because a blocked `mmap` comes back as a
  dereferenced null and `loom_pod` passes `--security-opt seccomp=unconfined`
  for Loom's reservation. Run by hand with that flag on and the pool free it
  segfaulted in the same 227 ms, so the flag is not what the Nix binary
  supplies. Whether a working module would still want it is unknown - the
  crash is before any device work - and `loom_pod` keeps passing it.
- Not a link mismatch: the module wants 42 `loom*` symbols, the image's
  `libloom_text_embed.so` exports 47, and none of the 42 are missing.
- `--replace-builtin` is the variable left untested. It seats the module where
  the built-in `loom-text` provider was, so double registration is the
  remaining suspect. Retry without it and read `gufo --version`: `loom 0.3.7
  (module:....so)` against `loom 0.3.6 (src/models/loom)` tells the two states
  apart.
- `run-gufo.sh` now passes `CMAKE_PREFIX_PATH` through when set, which is what
  let the build above link. The value has to be looked up inside the image
  (`ls -d /nix/store/*loom-runtime*`) because the hash moves with every build.
- Loom is still not in the reviewed registry - nine modules:
  deepseek41flash, diffusion_gemma, flint, gemma4, inkling2, lfm3, nemotron,
  strycast_qwen35moe, upscale - so it stays a git pin and `ext update` will
  rebuild it but never move it forward.
- `strycast_qwen35moe` and `upscale` cannot be installed on this API at all:
  "no reviewed release supports linux and extension API 0.3.42". Nothing here
  uses either; it matters only if the Qwen3.6-35B-A3B / Ornith 1.5 122B
  kernels are ever wanted.
- The module went back out: `./run-gufo.sh ext remove loom`. The live store is
  `deepseek41flash` + `inkling2` again and `--version` reports the built-in for
  every gufo entry, which is how it should stay - a module that segfaults has
  no business shadowing the built-in provider in a store all six gufo entries
  mount. `/tmp/gufo-ext-probe` (8.7 MB) can go too.
- `loom-inkling` is back on the Nix binary and measured on the way back:
  `load_started 124602 -> load_completed 53093` = 71509 MiB at 4 sessions /
  131072, within 61 MiB of the `124910 -> 53340` already recorded above the
  entry, so `mem: 70000` is twice-measured now. 11.2 s to `load_completed`,
  then 45.2 tok/s decode, ttft 208.7 ms, draft acceptance 74.6%.
- If a retry ever serves, adoption is: point `loom-inkling` at `${gufo_pod}
  ${gufo_image} ${gufo_serve_llm}` with `--env GUFO_MODELS_DIR=/models`, then
  drop both nix scripts, `loom_pod`, `loom_serve_llm` and `loom/README.md`.
  The `gufo-nix` volume is the only rollback for a model that has no other
  Loom-capable binary on this box, so it goes last.
