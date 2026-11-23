# strix launchers

llama-swap routing config plus container launchers for one AMD Strix Halo box
(gfx1151, 124.4 GiB of unified CPU/GPU memory). Clients call llama-swap on
`:8080` and name a model; llama-swap starts and stops every engine container
itself, rootless as uid 1000, each published on `127.0.0.1` so nothing bypasses
it.

Four engines, each with its own flag set and mount list: llama.cpp via the `run`
macros, gufo via `gufo_run` / `gufo_ds41_run`, hipfire via `hipfire_run`, and
Loom via `loom_pod` + `loom_serve_llm`. 18 models route across them.

## Files

| Path | What it is |
|---|---|
| `config.yaml` | symlink to `capacity-ttl.yaml`, the live config - keep it one |
| `capacity-ttl.yaml` | every model entry, macro and capacity pool |
| `run-llama-swap.sh` | what the systemd unit runs |
| `llama-swap.service` | user unit, symlinked into `~/.config/systemd/user/` |
| `run-gufo.sh`, `run-hipfire.sh`, `run-kyojin.sh`, `run-strix-llama.sh` | one per engine; each documents itself in its header |
| `nix-loom-build.sh`, `nix-loom-gufo.sh`, `loom/` | gufo built by Nix, needed only by `loom-inkling` |
| `AGENTS.md` | orientation for an agent working in this tree |
| `TODO.md` | open items, and which capacities still rest on a guess |
| `PUBLISHING.md` | auditing and rewriting history before a repo becomes public |
| `capacity-old.yaml`, `simple-routing.yaml` | earlier layouts, kept for reference |

## Setting it up somewhere else

llama-swap is a distro package, not a file in this tree.

`home: ${env.HOME}` is the only account-dependent value and it reads the process
environment, so there is nothing to edit for a different user - `${dir}`
(`/var/lib/models/llama`) and `/var/cache/gufo` are the paths that stay
host-specific. From inside a distrobox the package is not at `/usr/bin` but the
host's copy is, so name it: `/run/host/usr/bin/llama-swap`.

```sh
llama-swap -config config.yaml -validate            # 18 models, or it refuses
systemctl --user daemon-reload && systemctl --user restart llama-swap
curl -s localhost:8080/logs                         # wait for Health check passed
```

Gufo models need their modules installed (`./run-gufo.sh ext install <name>`).
The Nix-built gufo that `loom-inkling` runs is built by `loom/README.md`, about
three minutes; the `loom/gufo` symlinks are local build artifacts and are not in
this repo.

## Four things to know before changing anything

**A save restarts the resident engine, so this unit ignores saves.**
`-watch-config` polls every 2 s and reloads on any change - even a comment-only
edit, even for a model whose entry did not change - by stopping the running
container and starting it again. A cold reload of the big ones costs a minute,
with every client wanting that model waiting behind it. `run-llama-swap.sh`
defaults it on, so the unit sets `Environment=WATCH_CONFIG=false`. Applying a
config change is an explicit restart, never a file write.

**Memory is measured, not guessed.** The pool is the binding constraint, not the
GPU: `capacity.pools.mem: 118000` MiB resident at once, `evict_cost` decides who
leaves, `globalTTL: 900` reclaims after idle. Take the number from the
`host_available_mib` delta in `podman logs ls-<id>`. RSS lies - a model reporting
6.4 GiB of RSS was holding 111.8 GiB, and the rest is kfd device memory no
container stat shows.

**Capability fields lie.** Prove a modality with a request that exercises it - a
real image that gets answered correctly - not with a field in `/v1/models`.

**Names have three meanings.** The engine's install id, `useModelName` sent
upstream, and the `aliases` clients may send. Request the alias.

Health is `/health` (swap) and `/ready` (a loaded engine). `/api/version` reports
which llama-swap build is live, so it is how a package upgrade is confirmed.
`/v1/models/{id}` is not implemented and 404s for good ids, so never use it as a
health check.

## Not in this repo

llama-swap itself - it is the package above, and nothing unpacks into this
directory. Model weights stay under `${dir}`. `loom/gufo` and `loom/gufo-server`
are local build artifacts: absolute symlinks into a `/nix/store` path that only
exists on this box, which is why `loom/README.md` rebuilds them after a clone.

