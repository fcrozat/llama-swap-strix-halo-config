#!/bin/sh
set -eu
mkdir -p /etc/nix
cat > /etc/nix/nix.conf <<'CONF'
experimental-features = nix-command flakes
substituters = https://cache.nixos.org https://gufo.cachix.org
trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= gufo.cachix.org-1:rfZe3n4lHINgyoACKzs5EthIZmBNvEyCCtufUpth0PE=
max-jobs = 4
keep-derivations = false
CONF
echo "=== nix: $(nix --version)"
echo "=== flake metadata"
nix flake metadata github:loom-fun/loom-gufo-extension 2>&1 | head -12
echo "=== BUILD #runtime"
nix build github:loom-fun/loom-gufo-extension#runtime --no-link -L 2>&1 | tail -40
echo "=== OUTPATH"
nix build github:loom-fun/loom-gufo-extension#runtime --no-link --print-out-paths 2>/dev/null
echo "=== BUILD COMPLETE"
