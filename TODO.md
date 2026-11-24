# TODO

Open decisions on the strix launchers. `AGENTS.md` holds the standing rules: how
to apply a config change without taking the agent's own model down, how to
measure what a model really costs, and what belongs to the distro package rather
than to this tree.

Measured 2026-11-22 through 2026-11-24. Three entries were already declared from
a load before this week: gufo-flash-next 112000 (111.8 GiB), gufo-inkling and
gufo-ds41 122000, measured 122002 - the first entry found claiming less than it
costs, and it now declares the measurement (§2). Four more - the `hipfire-*` set
- are composed from the engine's own load lines, which is a different method and
says so in the entry (section 5). The other ten were claims, and flash-next was
3.3x under-declared until someone measured it; §1 has the figures. gufo-inkling
has since moved off the host delta, because on a unified box the host number is
not the bigger one (§4).

A fourth measurement deleted an entry rather than changing a number:
`loom-inkling` measured 52867 on a path that turned out to serve the same GGUF
`gufo-inkling` already serves, and 70000 for a second copy of a 47000 model went
back into the pool (§6, §7).

## 1. The ten entries that were guesses, measured

Measured on 2026-11-24, swap pinned to loopback for the whole window (AGENTS.md,
*Measuring without other clients in the sample*). Sweep one 10:05-10:21, sweep
two 10:35-10:37, the laya re-run 10:46. One llama.cpp request per entry, then a
220-token decode, `host_available_mib` sampled from `/run/host/proc/meminfo`
every 0.4 s.

    entry                was    measured  how
    qwen3.6-27b-q8      45000      70726  trough, settled 70662
    qwen3.8-27b-q8      45000      67818  trough, settled 67803
    qwen3.8-27b         30000      54883  repeat 54674, 0.4% apart
    gufo-27b            30000      44288  trough; engine's own delta 42834
    ornith-35b-a3b      34000      32229  trough, settled 32189
    qwen3.8-35b-a3b     34000      31713  trough, settled 31691
    openjev-q4          26000      28046  trough, settled 27989
    laya                40000       1130  loaded, never driven
    gufo-deepseek       26000     112863  settled host figure; engine 101145
    deepseek-v4-flash   26000      87970  trough, run without its draft

Seven were under-claimed, by 1.08x (openjev-q4) up to 4.3x (gufo-deepseek); two
came in just under what they claimed (the two MoE entries, 0.93x and 0.95x); and
laya was 35x over-claimed - its file is 429 MiB. The config now carries these
figures, each with the method beside it.

What the numbers say is that `--ctx-size` is the bill, not the weights. The run
macro asks for 131072 tokens and llama.cpp commits the KV at init - settled and
trough agree on every row - so a dense 27B pays ~36 GiB of KV whatever it is
asked to read: 17 GiB of weights measured 54883, 30 GiB measured 67818. The
sparse-attention MoE pays ~10 GiB for the same context. laya gets clamped to
`n_ctx_slot 8192` ("the slot context (131072) exceeds the context the model can
serve") and so costs about a gigabyte. openjev-q4 holds 28046 without ever
running a token, because it refuses the request (below). Reduction is the lever:
`gufo_serve_tail` already carries `--context 131072` for the gufo side and
lowering either one buys back a model's worth of pool per entry.

Two rows came from a load that evicted something and are void - openjev-q4 at
10:10 (delta 46, one eviction) and laya's baseline in between sweeps - because
this box answers from one of its own models: any request made between two
entries reloads flash-next and the baseline becomes the model being evicted.
Sweep two retook both on a verified-empty pool.

An empty pool is also not something this box can be handed. Ninety idle seconds
on 2026-11-24 logged six `/v1/chat/completions` against flash-next, one of them
a 108114-token prompt: another agent session works on these models. Every time a
sweep stopped flash-next that traffic brought it back inside twenty seconds,
which is three `capacity: model=gufo-flash-next evict=[gufo-inkling]` lines
taken inside measurement windows and one 502 for a request that was in flight.
It follows that a batch script which detaches and is waited on by a separate
tool call cannot measure anything here - returning from the wait is itself a
model request - so a sweep has to be one synchronous call, and a row is only
good while the journal shows no foreign `capacity:` line. Even synchronous is not
enough when that session is busy: the 13:28 window was clean of our own requests
and still voided both rows, twice evicted by traffic that wanted the preload
model back. A probe is the dangerous case rather than the merely inaccurate one,
because llama-swap does not know what an unmanaged container holds and will
happily load 112000 of pool onto a box where a probe already took 88 GiB - the
sweep therefore stops its own probe attempt and says so when the pool is not
empty (24753 MiB free at 13:33), rather than double-booking the machine.

`deepseek-v4-flash` does not load at all. llama-server exits while opening the
5.6 GiB draft: `failed to load model: unknown model architecture:
'deepseek4-dspark'`, so every request to it is a 500 after a 36 s wait. The
image is 33 h old and its digest matches the registry, so this is the current
llama.cpp build not knowing the arch, not a stale container or a bad file - the
main GGUF loads and serves fine, measured at 87970 with `--spec-type` and
`--spec-draft-model` dropped and a 200 back from a real request. gufo has the
same weights as a built-in (`deepseek_v4_flash`) and serves them as
`gufo-deepseek`, which is the entry that works.

Asked whether the draft could be fixed rather than dropped: no flag can, on this
engine. `--spec-type` lists `draft-dspark`, so the mechanism is compiled in, but
the arch string the draft file names is not - `libllama.so.1` in build 13600
(403dfcb03, the newest the registry has) carries `deepseek4` 148 times, plus
`deepseek2`, `dspark` and `dflash`, and `deepseek4-dspark` zero times. A flag
naming a mechanism and a file naming an arch the loader has never heard of is
not a misuse of the flag. Nor does the main file draft for itself: it declares
`deepseek4.nextn_predict_layers` and no `nextn.*` or `mtp.*` tensor, so
`draft-mtp` has nothing to read. `ngram-cache` is the one draft-free mode left, and it is measured: slower, and
out of the config again. Tested on the entry itself through the swap at 14:08 -
the only shape that is safe while another session is live, because the router
serialises memory and an unmanaged probe does not - it loaded, served two 200s,
and decoded worse than plain: 15.02 t/s on a novel 266-token completion against
17.08 t/s for the same weights undrafted, and 16.22 t/s on a prompt built to feed
it (one sentence repeated ten times) that reached 0.446 acceptance, 144 drafts
accepted of 323 generated. Those are llama.cpp's own numbers, not curl's wall
clock:

    slot print_timing: eval time = 17647.60 ms / 266 tokens (66.59 ms per token, 15.02 tokens per second)
    slot print_timing: draft acceptance = 0.16304 (15 accepted / 92 generated), mean len = 2.25

Verifying a drafted block costs this model more than its acceptance buys, at
least until something raises the hit rate far past 45%. Speculation is therefore
closed for this entry on evidence rather than by omission.
The entry now runs the main model alone at 89000; whether it earns its place
beside gufo-deepseek is still the open question, and it is a judgement about
87970 against 112863 rather than about a broken draft.

`laya` and `openjev-q4` are decision models and nothing here can drive them:
`/v1/chat/completions` answers 501 "This model is a decision model without text
generation, use /v1/systemone", and `/v1/systemone` wants a `state` object plus
a non-empty `questions` object. So laya's 1130 is a load that was never asked
anything, and its claim is weights plus its own 8192-token context with
headroom, not a driven figure. Worth one client that speaks that schema before
trusting either number - and worth knowing that any plain OpenAI client pointed
at these two entries gets a 501.

The ceiling those ten are measured against was settled on 2026-11-24, and not in
the direction the config comment asked for. It was 118000, a placeholder at
92.6% of the 127386 MiB this box has with a note to retighten it to ~90%; it is
now 124000, because gufo-ds41 measured 122002 and a ceiling below a model means
llama-swap declines to start it (§2). So the pool is 97.3% of physical RAM and
there is no headroom left in the arithmetic - what protects the box is that the
top two claims (122000, 112000) cannot fit much of anything beside them, the
cheapest claim being 9000. That arithmetic was only as good as the ten guesses,
and it was not good: under the old claims llama-swap would happily run
qwen3.6-27b-q8 and qwen3.8-27b-q8 together for 90000 of pool while the pair
actually wanted 138544 - 14 GiB more than the box has, and more than the
124000 ceiling was ever meant to allow. With the measured figures the same pair
claims 139000 and is refused, which is the whole point of the sweep. What is
left to earn is headroom, not accuracy: cut the context these entries ask for
and the pairs come back.

## 2. Decide whether flash-next exclusivity is acceptable

With its measured 112000 it could not share the old 118000 pool with anything,
so every model switch evicted it and the next request paid a 10-20 s cold load.
It is also the preload model and the one interactive sessions run on, so the
switch cost was paid by whoever typed next. At 124000 it can share with the
cheapest claim (9000) and nothing else - one step, not a fix, and the question
below still stands.

That is what already happened physically; the number only says so out loud. If
the cost is unwanted, bound the footprint instead of reflating the number back to
34000:

- `--sessions 4` -> 2 (state and KV per session)
- `--context 131072` -> whatever the clients actually use
- `--cache-ram-bytes N` (default is auto: half of free RAM, capped at 32 GiB)

Rough targets, measured the same way as the baseline: under 48000 lets it
coexist with a 27b, under 30000 with two of them. Write the chosen tradeoff into
the entry's comment so the next reader does not undo it.

Open question for the same pass: which models do we actually want resident at
the same time? gufo-ds41 (122000) is exclusive by construction now, and preload
says flash-next should be the warm default - which means ds41 is the one that
eats the warm default whenever anyone asks for it, at 133.9 s to come back.

### gufo-ds41 decided this section, 2026-11-24

Its first load here, on a pool that was free, took host available
124455 -> 2453 = 122002 MiB: 2 sessions, 131072 context, `--stream-experts`,
dspark draft, disk cache enabled, 133.9 s to `load_completed`, and
`gpu_device_used_mib` 120143 of 122880. Three things follow.

- The declared 114000 was 8002 MiB under what the model takes, and the pool
  allowed 118000, so llama-swap was permitted to start a model this box cannot
  hold. 2453 MiB left is not a margin, and the expert cache grows with use
  rather than stopping at the number.
- Writing the true figure alone is not the fix. At `mem: 122000` with the pool
  still at 118000 the entry exceeds it outright and llama-swap refuses to load
  it, which trades a near-OOM for a model nobody can ask for. The digit had to
  move together with the ceiling.
- Ceiling: holding ds41 alone means `pools.mem` above 122000, past 95% of the
  127386 MiB this box has, with the monitoring containers and page cache living
  in the remainder. Footprint: `--sessions 2` is already the small set, so what
  is left is `--context` and whatever `--stream-experts` sizes its cache from -
  measure the delta after changing one of them rather than predicting it, and
  note that 122002 at 131072 x 2 is roughly 46 GiB per session of context state,
  which says the context is where the memory is.

**Chosen 2026-11-24: the ceiling.** `pools.mem` is 124000 and the entry declares
122000, so the model stays askable-for and the pool states the truth. The cost
is accepted knowingly: the box runs at about 2.4 GiB spare with ds41 resident,
and 122000 of 124000 leaves less than the cheapest claim, so it loads alone and
every other model is evicted to make room - including the flash-next the preload
keeps warm. What was written down instead of measured is nothing: both numbers
are the load's own.

The footprint lever stays available and is the better half if that exclusivity
stops being acceptable: cut `--context` from 131072 and re-measure the delta,
and the claim comes down with it. That is a second window, and it is the same
restart as §1's list.

### What the raise admitted, and why §1 got more important

A ceiling is a permission slip, so 118000 -> 124000 let in pairs that used to be
refused before start. Two of them are worth naming, because each is a measured
number leaning on a guess:

- `gufo-flash-next` (112000, measured) with `hipfire-4b` (9000) at 121000.
- `hipfire-flash-next` (95000, composed worst case, `npu: 1`) with the cheapest
  non-hipfire claim, 26000, also at 121000. That one was exclusive by arithmetic
  at 118000 (see §5's eviction record) and it is not any more.

Neither is wrong yet; both are unproven, because the small half of each pair is
one of §1's ten. That is the real cost of the raise and the reason the list
moved up the queue: two guesses now get to be co-resident with measured worst
cases, and the router will only refuse what its own numbers say does not fit.

## 3. Give the repo a remote

Done 2026-11-24: `origin` is
`https://github.com/fcrozat/llama-swap-strix-halo-config` and `main` is pushed.
What remains of this section is the tail of it - the two safety bundles below,
and re-auditing before any force-push, since the first push closed that door.
The name was chosen as recorded here: `llama-swap-strix-halo-config`, engine
first, then AMD's name for this silicon - plain "Strix" is a pentesting tool and
a different APU family than the gfx1151 here.

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
output, which is a build id and not a secret, and the files themselves are gone
from the tip now (§6). A second pass then rewrote the
local account name out of every blob and every commit message: config paths read
`${env.HOME}`, which llama-swap substitutes for real, and the comments address
the reader as `$USER`.

What a clone gets is 16 files and 111 KiB (the `config.yaml` symlink counted as
a link, not twice as its target): no binaries, no weights, no upstream
docs, and no local account name anywhere in the object store. Two safety bundles
sit in the home directory, both taken before the scrub, so both still carry the
name - `launchers-pre-rewrite.bundle` additionally carries the upstream docs.
Both are still on disk as of 2026-11-24 and go once the published history has
been read back from the remote and confirmed good.

## 4. What the first inkling2 load left open

gufo-inkling was declared from the host delta (124441 -> 83577 = 40864 MiB with
the projector, 39972 without, at 4 sessions / 131072) while the same
`load_completed` line reported `gpu_device_used_mib=56150` (55250 without it),
and the question was which of the two the pool owes. Settled on the second load,
12:09 on inkling2 0.1.3 with the pool verified empty: host trough 41208, engine
`host_available_mib` delta 41064 - 0.3% apart, so both instruments agree - and
`gpu_device_used_mib=56348`. 57000 is now declared, on the device figure.

Which of the two is physically right is still not known - this box has one pool
of RAM, so 41208 and 56348 cannot both be the whole story, and the difference
has not been pinned to kfd pages being invisible to `MemAvailable` rather than
to gufo reserving device address space it has not committed yet. What is settled
is that the host delta is not safe on its own: at 47000 llama-swap would run
another 77000 of pool beside a model that may already be 55 GiB in. The other
half of the trap is timing: the residue fell to 7696 MiB once the weights were
uploaded, so a gufo entry measured after it settles under-reads 7x - the host
figure at that point is the staging buffers, not the model. Hence the rule for
this family: the larger of the two figures at `load_completed`, never a settled
one. What would actually close it is a second model loaded beside inkling with
/proc/meminfo watched the whole way - and exclusivity, or the answer never
arrives. The attempt at 13:28 was clean of our own requests and still voided both
rows: `capacity: model=gufo-flash-next evict=[gufo-inkling]` inside the inkling
window, `evict=[qwen3.8-27b]` inside the second-model window. Both measure an
eviction of the thing being measured, and a model that survives about 45 seconds
under that traffic cannot be made co-resident on demand.

Reading the pages instead of arguing about them does not work from inside a
container either. A watcher caught the gufo pid on the host six seconds into a
load and then found `smaps_rollup: Permission denied` (uid 1000 in here is not
uid 1000 out there), `0::/../libpod-<id>.scope` as the cgroup - unreadable at that
path - and `podman stats --no-stream` reporting `0B / 133.6GB` for a process
holding 41 GiB. That is the RSS blind spot from AGENTS.md confirmed for cgroups
and podman stats too: MemAvailable is the only instrument here that sees this
memory, and it disagrees with the engine by 15 GiB.

So 57000 stays, chosen because the other choice admits neighbours onto memory
that may already be gone. Three loads agree with each other (41208, 41064 and
41038 MiB of host against 56348 device, every time), so the gap is a property of
the accounting rather than of a lucky run.

Also open on that entry:

- decode was 43.4 tok/s on one 48-token completion, and 43.5 on a 74-token one
  after the 0.1.3 bump, so the figure reproduces even though it is still not the
  head-to-head against the Loom engine it replaced as the `Inkling-2-Mini` name.
  Prefill measured 172.7 tok/s at 22 prompt tokens, which is too short to mean
  anything: a 108k-token request is what these sessions actually send.
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
  decision. It was exclusive by arithmetic too, not just `npu: 1`: the smallest
  claim that is not another hipfire entry was 26000 and 95000 + 26000 is 121000,
  over the 118000 of that day. The ceiling is 124000 now, so that pair is
  admissible - §2 records what the raise let in.
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
  not offer. At 66000 it would be the first flash-next that could share a pool
  with anything - 66000 plus gufo-inkling's 57000 is 123000, inside the 124000
  of today with 1 GiB to spare - which is the question section 2 asks about the
  gufo entry.

## 6. Inkling on Loom: closed, the package never needed Loom

Closed 2026-11-24, and not the way this section was written. The image serves
`inkling-2-mini-loom` with no loom module at all: `serve llm --model
inkling-2-mini-loom` resolves the package directory, reads its
`llm_config.json` (arch `inkling2`, `Inkling-2-Mini-UD-Q4_K_XL.gguf`, vocab
200058) and loads that GGUF on gufo's own inkling2 support - which is the arch
`gufo-inkling` reaches through its module. The load line says so
(`kind=text artifact=/models/inkling-2-mini-loom`, `vocabulary_tokens=200058`)
while `model list` still calls the same id `installed, no loaded extension
offers it`: that line answers "which extension advertises this id", and it was
never the reason a second binary was in use.

Measured through llama-swap, pool free both times, 4 sessions at 131072:
124109 -> 71242 = 52867 MiB and 124146 -> 71235 = 52911 MiB, 10.7 s and 8.3 s to
`load_completed`, 45.7 tok/s. Two things the Nix binary did differently, both
visible in one line: it took 71509 MiB because Loom sized the package's own
1048576-token pool, and it ran with a draft (`draft acceptance 74.6%`) where
this path reports `speculative=off`. Decode measured the same either way (45.7
against 45.2 tok/s on a 20-token completion), so the draft is not worth its
18 GiB at that length - whether a long generation separates them is unmeasured.
Neither the sandbox nor a missing symbol was ever the question the bullets below
were circling.

What went: `loom_pod`, `loom_image`, `loom_dir`, `loom_serve_llm` from the
macros, and `nix-loom-build.sh`, `nix-loom-gufo.sh`, `loom/README.md` plus the
`loom/` symlinks with them. Engines are three families now (AGENTS.md). The
5.9 GiB `gufo-nix` volume went too, on 2026-11-24: it was kept as the one thing
that could bring the Nix binary back, and once the image's own loader proved it
could serve the same weights for 52867 MiB against that binary's 71509,
rollback meant going back to a worse version of a path that already works. The
scripts are in this repo's history if a future module needs the build again.
`--replace-builtin` is still untested and moot while the core loader answers.

The record of the module attempt, kept because the health-check trap in it is
not about Loom at all:

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
`nix-loom-gufo.sh` and the two `loom/` symlinks) existed because loom wanted API
0.3.35 and the image then had 0.3.20. Measured against a scratch store
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

Then the load test with the module seated, which answered the question as it was
posed then: no. `loom-inkling` was repointed at
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
  crash is before any device work. Nothing passes it now: `loom_pod` went with
  the rest of the Nix path.
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
- The intermediate state, back on the Nix binary, measured
  `load_started 124602 -> load_completed 53093` = 71509 MiB at 4 sessions /
  131072, within 61 MiB of the `124910 -> 53340` already recorded above the
  entry, so `mem: 70000` was twice-measured when it was set - of that binary,
  which is why §1 wants it lowered for the path running today. 11.2 s to
  `load_completed`, then 45.2 tok/s decode, ttft 208.7 ms, draft acceptance
  74.6%.
- What adopted instead, with no module involved: an entry running
  `${gufo_pod} --env GUFO_MODELS_DIR=/models ${gufo_image} ${gufo_serve_llm}
  ${gufo_sessions} --context 131072 --max-tokens 4096 --model
  inkling-2-mini-loom` - the ordinary `${gufo_serve_llm}`, the same one the
  other gufo entries use. That entry existed for one day and §7 is why it does
  not any more.

## 7. `loom-inkling` is gone: one Inkling, and the recipe instead

Its name and its alias (`Inkling-2-Mini-Loom`) both promised Loom; what ran was
gufo's own inkling2 support over the GGUF `gufo-inkling` already serves. Same
weights loaded twice under two claims, 70000 for the second copy of a 47000
model - 18 GiB of the box spent on a name, in the same pool that §1 and §2 are
arguing over. Folded into `gufo-inkling` on 2026-11-24; 17 entries validate.

What the fold keeps is the part that was actually new knowledge, written into
`gufo-inkling`'s comment rather than left as an engine: the module-free route to
these weights is `--env GUFO_MODELS_DIR=/models` plus `--model
inkling-2-mini-loom` in place of the two `--model`/`--mmproj` paths, which is
the fix for the documented trap where a `podman pull` leaves the `inkling2`
module stale, skipped, and `/ready` still answering 200. One line edit, not a
second binary.

Nothing had to be migrated. A month of the unit's journal (from 2026-10-25)
holds no request for `Inkling-2-Mini-Loom` - the fourteen grep hits that looked
like traffic were `/models/inkling-2-mini-loom` paths in the container's own
load lines, matched case-insensitively - and `Inkling-2-Mini`, the alias
`gufo-inkling` serves, is untouched.

What the fold gives up is the pair of shapes that §6 left open: this entry was
text-only at an explicit 131072 with no projector and no RAM-cache cap, while
`gufo-inkling` is image-capable with `--cache-ram-bytes 8589934592` pinned.
Nobody has tried whether the core loader takes a projector at all, so "text-only
without the module" is still the unproven half rather than a lost capability. If
a second context shape is genuinely wanted, it should be a second entry over
`gufo_run` with its own honest `mem:` - which is a different thing from a second
engine, and different from this: an entry whose name described a loader it no
longer used.
