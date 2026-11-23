# Loom-served models (gufo + loom-fun kernels)

`config.yaml` points at `loom/gufo` rather than a Nix store path, so a rebuild
needs no config change: build, re-point the symlinks, restart the containers
that use them.

    ./nix-loom-build.sh   # libloom_text_embed -> the gufo-nix volume (~90 s)
    ./nix-loom-gufo.sh    # gufo main + the loom module (~60 s)
    OUT=$(podman run --rm -v gufo-nix:/nix docker.io/nixos/nix:latest \
            nix build github:loom-fun/loom-gufo-extension#default \
            --no-link --print-out-paths)
    ln -sfn "$OUT/bin/gufo"        loom/gufo
    ln -sfn "$OUT/bin/gufo-server" loom/gufo-server

Both symlinks point into /nix: they dangle on the host and resolve inside the
container, which mounts the gufo-nix volume at /nix. The loom module is compiled
into this gufo (extension API 0.3.35). That is no longer the blocker it was:
the toolbox image now speaks a newer API and ships `libloom_text_embed.so`
itself. It is still what serves these models, though, because its built-in
loom predates Inkling-2-Mini support, and only `loom_pod` passes the
`seccomp=unconfined` the GPU memory reservation is documented to need.
That gap was measured and did not close: the v0.3.7 module builds inside the
toolbox image and its `model list` offers `inkling-2-mini-loom`, but `serve`
dies at `load_started` with `fatal_signal signal=11` about 230 ms in - with
`seccomp=unconfined` on, so this container's flag is not the reason this binary
works and the module does not. `TODO.md` §6 has the log lines and the one
variable left untested.
