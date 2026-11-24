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

**What is left.** Four questions were decided on the afternoon of 2026-11-24 and
all four are now in the config or parked with their precondition: §2's footprint
lever (the `run` macro asks 65536, tiered by role), §4's inkling trio (prefill
measured at 19k, thinking-off confirmed, effort left alone), §5's two hipfire
questions (no `$HIPFIRE_HOME` volume, no symtrunk pull), and §1's duplicate
DeepSeek (`deepseek-v4-flash` is out of the file). So were the two follow-through
items that survived them: the six `${run}` claims were re-swept at the 65536 the
macro actually asks (§1, 17:41-17:51, 51000 of claim back out of the pool), and
both decision models have answered through `/v1/systemone`. The gufo side of the
same lever was then looked at and deliberately left alone, and so was the last
question on this list:

1. §2's resident-set question, answered as asked: flash-next stays the warm
   default and ds41 stays exclusive. Traffic settled it rather than arithmetic -
   72 h of journal, 8302 requests to flash-next, exactly one load of ds41, and
   that load was the measurement that wrote ds41's number. The exclusivity has
   no victim yet.

`--context` on the gufo side is no longer an open item and the reason is written
where a reader will meet it - the `gufo_serve_tail` comment - rather than left as
an unclaimed lever: this is the family with long-context traffic (the 108k prompt
in §1 is gufo, and the journal in §2 found no `${run}` load at all), so the
window that was cheap to cut over there has a buyer here. It costs ds41's
exclusivity and that cost is accepted, not ignored. Reopen it with a measurement,
not with the number.

The window itself stopped being an improvisation today: `./run-mem-sweep.sh` now
carries the whole method - pin, prove the pin, watchdog, refuse a non-empty pool,
void a row on a foreign `capacity:` line, unpin on a trap even if the sweep is
killed - and defaults to a dry run that loads nothing. That makes the next window
a decision about cost rather than an hour of care.

Nothing is blocked. §4's device-versus-host question was closed by decision
rather than by a root read, and §4 says so plainly rather than leaving a note
that somebody with root ought to look.

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
macro asked 131072 when these were measured and llama.cpp commits the KV at init
- settled and trough agree on every row - so a dense 27B pays ~36 GiB of context
state whatever it is asked to read: 17 GiB of weights measured 54883, 30 GiB
measured 67818. The sparse-attention MoE pays ~10 GiB for the same context.
laya gets clamped to `n_ctx_slot 8192` ("the slot context ... exceeds the
context the model can serve" - the parenthetical names whatever the macro asks
for, which is 65536 since 2026-11-24) and so costs about a gigabyte. The clamp
is on the slot only: `llama_context` still reports `n_ctx 65536` for it (§2), so
what a gigabyte says is what that container touches, not what it reserves.
openjev-q4 held 28046 without ever running a token, because it was never asked
one (below). Reduction is the lever, and the llama.cpp half of it is pulled
*and* re-measured: the macro went to 65536 and the six `${run}` rows were
re-swept against an empty pool at 17:41-17:51, which takes 51000 of claim out of
a 124000 pool. The gufo side, where `gufo_serve_tail` still carries `--context
131072`, was weighed against that and left alone - which is why the two largest
claims on the box, ds41's 122000 and inkling's 57000, are untouched by any of
today's arithmetic, and why that is a decision rather than a leftover (the
`gufo_serve_tail` comment carries the reason).

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

### Re-swept at 65536, 17:41-17:51

The window AGENTS.md prescribes was taken once, in one synchronous call: pin
`:8080` to loopback with a watchdog, unload flash-next, measure six entries on a
verified-empty pool, unpin, leave the box answering. 609 s, zero voided rows.
The cost is on the record too: 37 `refused` lines while pinned, and no 500 and
no engine error, because refusing a connect cannot kill a generation in flight
the way an eviction can.

    entry                morning(131072)    peak   settled    back
    qwen3.6-27b-q8                70726    57670    57602   13056
    qwen3.8-27b-q8                67818    55526    55136   12292
    qwen3.8-27b                   54883    41824    41680   13059
    ornith-35b-a3b                32229    28855    28816    3374
    qwen3.8-35b-a3b               31713    27798    27748    3915
    openjev-q4                    28046    23717    23701    4329

`openjev-q4` is the first driven figure of the six: `/v1/systemone` answered it,
so that row is a load that was asked something, which no earlier row for it
could say. Peak and settled agree within 470 MiB on every row - the same
agreement the morning sweep found, and the reason a trough can be trusted here.
The six peaks are 50025 MiB below the morning's; the claims come down 51000 once
each is rounded up to the nearest 500: 58000, 56000, 42000, 29000, 28000, 24000.

What the six settle is §2's fit, and what they correct is its use. The dense 27Bs
gave up 12292 and 13056 where the fit predicted 13.2 GiB - to the gigabyte. The
MoE pair gave up 3374 and 3915, because sparse attention had spent a quarter of
what dense pays for the same window, so halving it halves a small term. And the
pair this whole section turns on, `qwen3.6-27b-q8` with `qwen3.8-27b-q8`, is
114000 of claim: refused under the measured 131072 figures, admitted again now.

`deepseek-v4-flash` does not load at all. llama-server exits while opening the
5.6 GiB draft: `failed to load model: unknown model architecture:
'deepseek4-dspark'`, so every request to it is a 500 after a 36 s wait. The
image is 33 h old and its digest matches the registry, so this is the current
llama.cpp build not knowing the arch, not a stale container or a bad file - the
main GGUF loads and serves fine, measured at 87970 with `--spec-type` and
`--spec-draft-model` dropped and a 200 back from a real request. gufo has the
same weights as a built-in (`deepseek_v4_flash`) and serves them as
`gufo-deepseek`, which is the entry that works.

Decided 2026-11-24 at 15:40: `deepseek-v4-flash` is out of the config, and the
honest reason is not memory. Its whole case was that 89000 costs 23863 less than
`gufo-deepseek`, but that saving is unspendable - the two can never both be
resident (201863 against a 124000 ceiling), so the row never held pool that the
other entry could use, and dropping it frees nothing. What it removes is a
second, slower, draft-free route to one GGUF (17.08 t/s against gufo's drafting)
and a row that has to be re-validated on every image bump. Because the entry no
longer carries them, this section is where the reasons its flags died now live:
the arch string `deepseek4-dspark` that build 13600 has never heard of, the
absent `nextn.*` tensors, and the `ngram-cache` measurement below.

Asked whether the draft could be fixed rather than dropped: no flag can, on this
engine. `--spec-type` lists `draft-dspark`, so the mechanism is compiled in, but
the arch string the draft file names is not - `libllama.so.1` in build 13600
(403dfcb03, the newest the registry has) carries `deepseek4` 148 times, plus
`deepseek2`, `dspark` and `dflash`, and `deepseek4-dspark` zero times. A flag
naming a mechanism and a file naming an arch the loader has never heard of is
not a misuse of the flag. Nor does the main file draft for itself: it declares
`deepseek4.nextn_predict_layers` and no `nextn.*` or `mtp.*` tensor, so
`draft-mtp` has nothing to read. `ngram-cache` is the one draft-free mode left. It is measured now, and slower,
and out of the config again. Tested on the entry itself through the swap at 14:08 -
the only shape that is safe while another session is live, because the router
serialises memory and an unmanaged probe does not - it loaded, served two 200s,
and decoded worse than plain: 15.02 t/s on a novel 266-token completion against
17.08 t/s for the same weights undrafted, and 16.22 t/s on a prompt built to feed
it (one sentence repeated ten times) that reached 0.446 acceptance, 144 drafts
accepted of 323generated. Those are llama.cpp's own numbers, not curl's wall
clock:

    slot print_timing: eval time = 17647.60 ms / 266 tokens (66.59 ms per token, 15.02 tokens per second)
    slot print_timing: draft acceptance = 0.16304 (15 accepted / 92 generated), mean len = 2.25

Verifying a drafted block costs this model more than its acceptance buys, at
least until something raises the hit rate far past 45%. Speculation is therefore
closed for this entry on evidence rather than by omission.
The entry ran the main model alone at 89000 up to the paragraph above, which is
where the judgement landed: out, on duplication rather than on footprint.

`laya` and `openjev-q4` are decision models, so a text request is refused by
design: `/v1/chat/completions` answers 501 "This model is a decision model
without text generation, use /v1/systemone". That endpoint is forwarded by
llama-swap and the model id comes from the body's `model` field as on any other
route, so both are reachable, and `laya` was driven for the first time on this
box on 2026-11-24 (unloaded again at 17:13). The schema is documented nowhere on
the box; it was read off the engine's own 400s, one field at a time:

    {"model":"laya","state":"...","questions":{"q":{"type":"choice",
      "instructions":"...","criteria":{"keep":"...","drop":"..."}}}}

`state` is required and a bare string is accepted; `questions` must be a
non-empty **object** (an array is refused); each question needs `instructions`
and a `type` of `choice`, `score` or `noul`; `choice` takes `criteria` as an
object, `score` as an array of 2 to 10 levels. The trap is `options`: the engine
accepts it and ignores it - the choice space is the criteria keys and it answers
from their descriptions. Answers are deterministic (0.1013 / 0.8987 to the last
digit across repeats) and `usage.output_tokens` is 0, because nothing here is
generated.

Driven, `laya` troughs at 1006 MiB and settles at 976 after five questions some
of which carried ~750-token states, against 1021 and 1130 from loads nobody
talked to: traffic does not grow it, so its 2500 is headroom over a measured
figure now, not an estimate of one. `openjev-q4` waited for the same admission
reason - 113000 of warm flash-next plus its own claim is over the 124000 ceiling
- and got the same treatment later in the 17:41-17:51 window: `/v1/systemone`
answers it too, peak 23717 and settled 23701. Both decision-model rows are
driven figures now, and neither is an idle load.

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
claims 139000 and is refused, which is the whole point of the sweep. The
headroom that paragraph was asking for is earned rather than predicted now: the
macro asks 65536, the six rows were re-swept at it the same evening, and the pair
is 114000 and fits.

## 2. Decide whether flash-next exclusivity is acceptable

With its measured 112000 it could not share the old 118000 pool with anything,
so every model switch evicted it and the next request paid a 10-20 s cold load.
It is also the preload model and the one interactive sessions run on, so the
switch cost was paid by whoever typed next. At 124000 it can share with the
cheapest claim (9000) and nothing else - one step, not a fix. The resident-set
question below is what this section was for, and it is answered there.

That is what already happened physically; the number only says so out loud. If
the cost is unwanted, bound the footprint instead of reflating the number back to
34000:

- `--sessions 4` -> 2 (state and KV per session)
- `--context 131072` -> whatever the clients actually use
- `--cache-ram-bytes N` (default is auto: half of free RAM, capped at 32 GiB)

Rough targets, measured the same way as the baseline: under 48000 lets it
coexist with a 27b, under 30000 with two of them. Write the chosen tradeoff into
the entry's comment so the next reader does not undo it.

### The slope, measured on qwen3.8-27b at a quarter context

15:03, same entry, same cmd, one flag appended: `--ctx-size 32768` after the one
already in the `run` macro. llama.cpp honours the last occurrence and says so -
`DEPRECATED: argument '--ctx-size' specified multiple times … only last value
will be used` - which is both the proof the override took effect (`n_ctx_slot =
32768` on the load line) and a warning that last-wins is a stopgap: a real change
belongs in the macro, not in a duplicated flag this build has started to
deprecate.

With the pool empty and that model the only thing resident, `MemAvailable` settled
at 88273 against 124752 empty: **36479 MiB**, where the same entry at 131072 took
54883 and 54674 the same morning. Two points make a fit rather than a curve:
**~201 KiB per token of context, and a constant of about 30 GiB** - KiB, not the
`B` this section said until 2026-11-24, when the arithmetic was checked against
the model file: 65536 x 201 KiB is 12.9 GiB, which with the 30 GiB constant
lands on the 43900 the fit was verified against, while 201 *bytes* would leave
the constant doing all the work. Of that constant, weights and the MTP draft are
17.7 GiB (16.45 + 1.28 on disk).

How much of the slope is KV is readable off the GGUF, and it is less than the
slope. `Qwen3.8-27B-UD-Q4_K_XL.gguf` is `qwen35`: `block_count 65`,
`full_attention_interval 4`, `attention.head_count_kv 4`, and `attn_k.weight`
is `[5120, 1024]` - `n_embd` by `n_kv_heads x head_dim`, that is 4 heads of
256 - so attention exists in 17 of the 65 blocks and the other 48 are the linear
path. The macro pins all of it (`--kv-unified`, `--cache-type-k f16`,
`--cache-type-v f16`, `--flash-attn on`, `--fit off`), so:

    2 (K,V) x 17 layers x 1024 x 2 B = 69632 B/token = 68 KiB/token
    -> 4352 MiB of KV at 65536, 8704 at 131072

The fit says 65536 tokens cost about 13.2 GiB. So the geometry is a third of the
ctx term, and what the extra ~9 GiB is got a direct look at on 2026-11-24 at
20:49 (§2's `-lv 4` window, `laya`) and is not what this section guessed:

- There is no KV allocation line. `-lv 4` really was on - the GGUF metadata dump
  (50 keys) only prints at that verbosity - and it produced no debug lines at
  all. The only sizes this build prints are `load_tensors` model buffers, one
  output buffer, and two `sched_reserve` compute buffers.
- Compute scratch is not the culprit either: `laya` at `n_ctx = 65536` reserved
  25.02 MiB (ROCm0) plus 9.01 MiB (ROCm_Host) of compute buffer - 34 MiB, about
  0.5 B per token of context. Its model buffers were 374.62 plus 52.27 MiB,
  exactly the 426.88 MiB file.

So the extra two thirds is not compute scratch, and that leaves the KV
allocation - but not a plain `n_ctx x geometry` reservation either, because
`laya` is a counter-example on this same engine. Its geometry is 120 KiB/token,
7680 MiB at 65536, and §1 measured the whole container at 1130 on load and 976
settled after five questions: about 0.65 GiB of that context is host memory the
engine touches. A `MemAvailable` delta counts touched pages, not reservations,
so the same instrument that produced the fit cannot see a reservation it has not
been made to fault in.

That is why the fit is not retired here. The 27B's 201 KiB/token rests on two
loads of that entry and nothing else; the candidates for the extra two thirds
are named, not proven: per-token cells for the 48 GDN blocks under
`kv_unified`, `context checkpoints enabled, max = 32, min spacing = 8192`, and
`Flash Attention over K/V rows enabled` - the last two read off the same log.
Settling it needs two loads of one qwen35 entry at two `--ctx-size` values with
the pool verified empty, which is the sweep method, not a verbosity flag.

The same three numbers off the other files, because they differ by 3x:

| entry | attention layers of n | KV dim | KiB/token | KV at 65536 |
|---|---|---|---|---|
| `qwen3.8-27b`, both quants | 17 of 65 | 1024 | 68 | 4352 MiB |
| `openjev-q4` | 16 of 64 | 1024 | 64 | 4096 MiB |
| `qwen3.8-35b-a3b` | 11 of 41 | 512 | 22 | 1408 MiB |

The ctx lever is therefore worth very different amounts per entry, which the
tier argued without knowing: halving context costs the 27B four times what it
costs the 35B-A3B. `laya` is a third shape again - `modern-bert`, 30 blocks of
fused QKV (`attn_qkv [1024, 3072]`, so MHA at 1024), no interval, 120 KiB/token
- and the 8192 in its file turned out not to be a clamp on what is allocated:
see the verification below.

What that says about the lever: cutting 131072 to 32768 returns 18.4 GiB - a
third, not three quarters - and 65536 predicts 9 GiB. Two thirds of the footprint
does not move with context, so no context setting makes a dense 27B small. It
does change the arithmetic this section is about: two of them drop from 110000 of
pool to about 74000, which puts inkling's 57000 beside one of them (94000) and
still not beside both (131000 against a 124000 ceiling).

The instrument caveat, because the two figures are not the same kind: the 131072
numbers are load troughs from this morning's sweep, the 32768 number is free
memory settled 30 s after a 154-token generation. What makes them comparable is
§1's own observation that settled and trough agree on every llama.cpp row.

The `-lv 4` window ran 20:49:12-20:52:32 on `laya` (the flag appended to that
entry's cmd, one restart, reverted by the same script afterwards) and its
predicted-versus-printed KV check could not be made: there is no printed KV, as
above. What it did settle is in the paragraph that asked for it - compute
scratch is 34 MiB, not 9 GiB - and one thing nobody expected: **the context is
not clamped.** `llama_context: n_ctx = 65536, n_ctx_seq = 65536` for a model
whose file says `context_length 8192`. The clamp is on the *slot*:
`n_slots = 4, n_ctx_slot = 8192`, preceded by `the slot context (65536) exceeds
the context the model can serve (8192: the training context, or what a linear
--rope-scale ...)`.
So a request cannot use beyond the model's ceiling, but the context was
constructed at 65536 anyway (`sliding_window 128`, `pattern 3`, `causal_attn 0`
are the other shape facts from that dump). What this does *not* do is put the
2500 claim in doubt: §1's laya rows are measurements, 1130 on load and 976 after
five questions, and the claim is the larger plus headroom, which is this file's
rule. What it does mean is that those rows are what the engine touches and not
what it reserves, so `laya` was never going to be the check on a KV size - and
with no KV line to print, that check does not exist on this build at any
verbosity.

The two pairs the raise below admitted are deliberately not in that window: they
stay unproven until something actually fails, which is the only evidence worth
spending a window on here.

Decided 2026-11-24 and applied: the `run` macro asks 65536 now, tiered by role,
and the journal is what said which roles exist - 72 h of it, 8302 requests to
`gufo-flash-next`, 116 to `loom-inkling`, 38 to `gufo-inkling`, and not one load
of any `${run}` model. The long window this macro was buying had no buyer in that
family, while the 108k-token prompt on the record (§1) is gufo traffic and keeps
its window, gufo having its own macros.

The order of the two halves mattered, so only one moved at a time. The pool
admits on claims, so a smaller `--ctx-size` changes what a container holds and
nothing about what the router allows; the entries kept their 131072-era claims
until re-swept, which left the config deliberately stricter than the hardware for
about four hours. §1's 17:41-17:51 re-sweep is where that closed, and it checked
the fit on the way through: 30 GiB + 65536 x 201 KiB says about 43900 for
`qwen3.8-27b` and the entry measured 41824, and the same fit over-predicted the
131072 point by a matching 4-5%. So it is a usable lever and a bad claim, and the
claims now carry measurements instead. Two dense 27Bs are therefore 84000 of pool
rather than the 74000 sketched above - worse coexistence than the fit implied,
still inside the ceiling, and inkling's 57000 sits beside one of them (99000)
but not both (141000). An entry that needs the full window says so itself, with one
`--ctx-size 131072` in its own cmd - not a second one after `${run}`, which
llama.cpp resolves to the last value while warning that it is deprecated.

Verified on the first `${run}` container after the restart, 16:07: `laya` came up
with `--ctx-size 65536` in `podman inspect`'s argv and `n_ctx_slot = 8192`. It
was admitted at 2500 beside a resident flash-next and evicted nothing, then
unloaded. That is also the cheapest way to check a macro change reaches the
family: pick an entry whose claim leaves room, not one that would move the warm
model. What 20:49 corrected is what `n_ctx_slot = 8192` was taken to mean: it is
the per-request ceiling, not the allocation - the context itself ran at 65536.

**Decided 2026-11-24: this is the resident set.** flash-next stays the warm
default and ds41 stays exclusive, and the traffic is what tipped it: 72 h of
journal, 8302 requests to flash-next against one load of ds41, and that load was
the measurement that produced the 122002. Two alternatives were weighed against
leaving it alone, and both cost more than they buy:

- `pools.mem` at 121000 instead of 124000 puts ds41's claim over the pool, so
  llama-swap refuses it rather than evicting flash-next. That protects a warm
  model nobody has complained about by making a measured entry unaskable-for.
- Changing what `hooks.on_startup` preloads (nothing, or the cheap pair) moves
  what is warm after a restart, not who wins the fight - and flash-next is the
  model the sessions actually run on.

So the cost is carried with its size known: one ds41 request makes the next
flash-next request pay 133.9 s. The footprint lever below remains the way out if
that ever stops being acceptable.

Scope, decided with it: **flash-next in this section means `gufo-flash-next`.**
`hipfire-flash-next` is a different quant (`qwen3.8:flash-next-mq4-xts`) on a
second engine, and it is a route rather than a resident-time candidate - its
`npu: 1` and its composed 95000 are there so the router refuses honestly, not so
anyone plans warm time around it. Everything above - who stays warm, who gets
evicted, what a reload costs - is the gufo entry, and the §5 pair involving the
hipfire one is not queued behind it.

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
restart as §1's list. Asked and declined on 2026-11-24: the traffic that wants
131072 on this box is gufo traffic, so the exclusivity stands and the lever is
recorded as deliberately unpulled in `capacity-ttl.yaml` rather than left for the
next reader to discover. If it is ever pulled, `./run-mem-sweep.sh` is the window
and the claims move with the measurement, not with the flag.

### What the raise admitted, and why §1 got more important

A ceiling is a permission slip, so 118000 -> 124000 let in pairs that used to be
refused before start. Two of them are worth naming, because each is a measured
number leaning on a guess:

- `gufo-flash-next` (112000, measured) with `hipfire-4b` (9000) at 121000.
- `hipfire-flash-next` (95000, composed worst case, `npu: 1`) with the cheapest
  non-hipfire claim - `openjev-q4`, re-measured to 24000 the same evening, so
  119000 rather than the 121000 first written here. That pair was exclusive by
  arithmetic at 118000 (see §5's eviction record) and it is not any more. Under
  the scope rule above this is a routing fact, not a pair to plan around:
  nothing is warm because of it and nothing waits on measuring it.

The first is unproven and the second is out of scope. Neither is wrong, and the
router will only refuse what its own numbers say does not fit - which is the real
cost of the raise, and why §1's list moved up the queue while this one did not.

## 3. Give the repo a remote

Done 2026-11-24: `origin` is
`https://github.com/fcrozat/llama-swap-strix-halo-config` and `main` is pushed.
What remains of this section is the tail of it: the three safety bundles below,
and the rule that a force-push here is one-way and needs the whole audit redone.
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

What a clone gets is 16 files and 171 KiB - re-measured on the evening of
2026-11-24, after the day's rewrites and a new sweep script (the `config.yaml`
symlink counted as a link, not twice as its target): no binaries, no weights, no
upstream docs, and no local account name anywhere in the object store. Two
safety bundles sit in the home directory, both taken before the scrub, so both still carry the
name - `launchers-pre-rewrite.bundle` additionally carries the upstream docs.
Both are still on disk as of 2026-11-24. The readback they were kept for has
happened - `origin/main` was fetched and every object in it inspected, with no
account name, hostname, credential or private address in any path or blob. They
are kept a little longer on purpose: until the
SHA-cache probe below stops answering, they are the only way back to the state
before this rewrite. Each holds exactly what a rewrite removed, and the newest
holds the harness state this one took out.

Purged on 2026-11-24, on the owner's word: `.pi/subagentura-state.json` had been
in the tree. 230 bytes of agent-harness bookkeeping - a parent session UUID and
a telemetry correlation id - it arrived with a `git add -A` that only wanted the
config and was refreshed by a later one. Nothing personal was in it; what was
wrong is the category, box-local tool state in a public routing config, and the
live risk was the next `git add -A` after a harness release decides to write a
cwd or a prompt in there. `.pi/` is gitignored and the file is untracked, so it
cannot recur; the rewrite below removes the copies already committed.

`git filter-repo --path .pi --invert-paths` over all 56 commits, with
`--message-callback` rewriting the one commit message that quoted a hash this
rewrite invalidates - quoted hashes die, so it now names that commit by its
subject. `filter-repo` first refused to run: an `already_ran` marker from the
two earlier passes prompted, and with no tty that is an `EOFError` and nothing
happens; answering `n` starts an independent rewrite instead of continuing the
old mapping, which is what a different change wants. Post-rewrite the store is
56 commits, 254 objects, 138 blobs, 16 files, and `git fsck --unreachable` is 0
- the old objects are gone, not merely unreferenced.

Re-audited over that store, per needle and by shape: the account name is 0
whole-word and 0 as a `/home/` path (the only case-insensitive substring hits
are the word "cooperate" inside `PUBLISHING.md`'s own warning about exactly
that), `BEGIN PRIVATE` and `api_key` are the same line naming its needles,
`password` is that line plus the `sudo -n` comments, and the dotted names
anywhere in history are registry URLs, filenames and one hipfire label
(`dev.hipfire.variant`) - no hostname, no `user:pass@`, no key material. The two
UUIDs from the purged file are in 0 blobs, which is the check that the payload
left rather than just its path.

Third bundle in the home directory, `launchers-pre-pi-purge.bundle` (154 KiB),
taken before this rewrite. The push is a `--force-with-lease` naming the
pre-purge tip, so it fails rather than clobbering if anything else moved `main`.
After it every hash here is new, and anyone who cloned must re-clone or reset -
the door this section said was closed, reopened deliberately once.

A rewrite does not reach GitHub's cache of unreferenced commits. The pre-purge
tip still answers at its own SHA URL, and the `.patch` GitHub renders for it
shows the deleted file, so the two session UUIDs are readable there today.
Nothing reachable from a ref carries them - a fresh clone cannot even `cat-file`
that commit - and no machine but this one ever held the SHA. Decided 2026-11-24:
let GitHub's own GC expire it rather than open a support request over two opaque
ids. The probe is a `curl -o /dev/null -w '%{http_code}'` against that commit
URL; when it stops answering, the bundles above have no reason left and go.

Runnable as written, and the SHA comes out of the bundle rather than out of this
file, so the command survives any later rewrite of it:

```sh
OLD=$(git bundle list-heads ~/launchers-pre-pi-purge.bundle |
      awk '/ refs\/heads\/main$/ {print $1}')
curl -s -o /dev/null -w '%{http_code}\n' \
  "https://github.com/fcrozat/llama-swap-strix-halo-config/commit/$OLD"
```

200 twice on 2026-11-24 (20:44, then 21:02, when the page still rendered the
deleted filename six times), so all three bundles stay. Anything else - or a
page that no longer renders the deleted file - ends this section: the bundles go,
along with the paragraph that kept them.

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
  At 19k tokens of context it is 29 tok/s (34.5 ms/token), against 37-38 tok/s on
  the short prompts measured the same afternoon - so long context costs about a
  quarter of the decode as well as the prefill below.
- prefill at a length that means something, 15:04 with the pool empty: **19243
  prompt tokens in 18393 ms = 1046 tok/s**, against 74 tok/s for the same model at
  22 prompt tokens and 237 tok/s at 60. The short figures were fixed cost, not
  speed - roughly 250-300 ms of setup per request, which at 22 tokens is most of
  the request. Extrapolated, the 108114-token shape §1 logged is about a 100 s
  prefill on this entry: a client waiting on a long prompt here is waiting on
  prefill, and the 43 tok/s headline only describes the tail of it.
  Memory is the one thing that did not move: the host trough during that 19k
  prefill was 41989 MiB against the 41208 of its own load, 781 MiB for 19k tokens
  of state. Either `MemAvailable` is still not seeing what the context costs - the
  §4 gap again - or gufo commits context up front and the prefill adds nothing.
  Both readings keep 57000 the conservative claim.
- `enable_thinking: false` works, and the field to read is
  `usage.completion_tokens_details.reasoning_tokens`, not a top-level
  `reasoning_tokens`: with the switch the same prompt came back with
  `reasoning_tokens: 0`, no `reasoning_content`, and 91 completion tokens where
  without it the same prompt spent 143. The "still returned 41 reasoning_tokens"
  recorded here an hour earlier did not reproduce; one of the two is wrong, and
  the field path above is where a future check should look before a client is told
  this is off.
- the entry inherits `--reasoning-effort xhigh` from `gufo_serve_tail`, which the
  extension maps to 0.99 against its own unset default of 0.9, and its M4 log
  says effort barely moves this model while `high`-to-`max` only lengthens the
  reasoning on some prompts - so Inkling may be paying latency for nothing.
  Measured once each at 15:04 on one arithmetic prompt: absent 143 completion
  tokens, `reasoning_effort: high` 226, `xhigh` 169 (160 of them reasoning), every
  answer correct and no ordering to the counts. A per-request effort clearly
  reaches the engine, since the numbers move, but one sample cannot separate
  effort from sampling noise. Thinking-off (91 tokens, zero reasoning) is the only
  lever demonstrated here; retuning effort is not worth a restart until there is a
  fixed seed and a longer generation to compare.

Decided the same afternoon on the accounting gap: **57000 is the permanent claim**
and the discrepancy is documentation, not an open item. Settling it properly needs
root on the host - `smaps_rollup` answers `Permission denied` from here, the
libpod cgroup is unreadable, and `podman stats` reports `0B / 133.6GB` for a
process known to hold 41 GiB - and the prize is roughly 10000 of pool against the
possibility of seating a neighbour on a model already near 55 GiB. The engine's
own larger figure wins on a box where the cheaper instrument is the one in doubt.
Where the other 15 GiB goes is left for someone with root; nothing in the config
now waits on the answer.

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
  admissible - §2 records what the raise let in, and its scope keeps it a
  routing fact rather than a resident pair: flash-next there means gufo.
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

- `$HIPFIRE_HOME` does not want a volume. Measured on the serve path at 15:17:
  `hipfire-4b` cold through the swap - answer in hand 6.0 s after the request,
  its 9000 admitted beside flash-next's resident 112000 with nothing evicted -
  left three things in `/home/hipfire/.hipfire` besides `models`: two pid files
  and a 112 KB `registry.cache.json`. The kernel work that start appears to do is
  reading, not building: `pre-compiled kernels: /var/cache/hipfire/gfx1151`, then
  one `indexed package verified` line per `.hsaco`, every path inside the image.
  The only other writes were a few `~/.cache/comgr/llvmcache-*` blobs, outside
  `$HIPFIRE_HOME` and small. A mount would persist pid files.
  The index this bullet used to cite as "429 MiB" is real but belongs to `fit`,
  and it is two orders of magnitude larger: evaluating a tag it treats as not
  installed wrote `cache/fit-headers/<hash>/` - four files, 93.1 GiB of apparent
  size over 320 MiB of real blocks. With that directory persisted the same probe
  went 7.51 s then 2.88 s, so that ~4.6 s is what a home volume would buy, on a
  diagnostic. Three reasons not to: serving never reads it; `hipfire_dir` is
  mounted `:ro`, so hipfire could not put it beside the weights even if it wanted
  to; and it lands owned by the container's root, so clearing it needs
  `podman unshare rm -rf` rather than a TTL. The flag is the answer - `fit
  --no-fetch` writes nothing (0.30 s, `registry.cache.json` only) and says `fit
  needs the model header` instead of building a replica. Probe with the flag and
  leave `$HIPFIRE_HOME` as `--rm` leaves it.
- `qwen3.8:flash-next-mq4-xts-symtrunk` is not on this box, so the sharing
  question cannot be measured, and the 66000 it rests on was never a measurement.
  The store holds `qwen3.8-flash-next.mq4-xts` at 116.68 GiB, a `gptq3` file at
  the same size and a 0.28 GiB trunk overlay; `-symtrunk` is a registry tag with
  no file behind it here. 66.0 GiB is what its registry header says - the catch is
  that `fit --no-fetch` quotes 66.0 GiB with no store mounted at all, so the
  number describes catalog metadata rather than anything installed. The pair
  arithmetic in the earlier pass of this bullet, 66000 plus gufo-inkling's 57000
  inside a 124000 ceiling, was arithmetic on a catalogue entry.
  What it would take instead: `hipfire pull` of roughly 66 GiB (327 G is free on
  that filesystem, so disk is not the obstacle), then a load that evicts whatever
  is resident, including the model an answering session runs on. And its own
  header-based `fit` at the trained 262144 says `DOES NOT FIT ... 62475 MiB routed
  experts + 5115 MiB non-expert weights`, so the context it would be capped to is
  the first thing to settle, not the last.
  Decided 2026-11-24: **not pulled**, and parked here as its precondition - a
  reason to want flash-next beside inkling, a context cap its own header accepts,
  and a window whose eviction an answering session can spare. A 66 GiB pull is an
  expression of intent rather than a measurement, and none of the three exists
  yet.

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
arguing over. Folded into `gufo-inkling` on 2026-11-24; 16 entries validate.

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
