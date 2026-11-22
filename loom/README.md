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
into this gufo (extension API 0.3.35); the toolbox image is still on 0.3.20,
which is why these models do not use `gufo_pod`.
