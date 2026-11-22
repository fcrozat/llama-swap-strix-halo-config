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
echo "=== packages of the flake"
nix flake show github:loom-fun/loom-gufo-extension 2>&1 | head -14
echo "=== BUILD #default (gufo with the loom extension)"
nix build github:loom-fun/loom-gufo-extension#default --no-link -L 2>&1 | tail -60
echo "=== OUTPATH"
nix build github:loom-fun/loom-gufo-extension#default --no-link --print-out-paths 2>/dev/null
echo "=== GUFO BUILD COMPLETE"
