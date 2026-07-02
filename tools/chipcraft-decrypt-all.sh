#!/bin/bash
# ChipCraft Lab — decrypt every *.enc under ~/lab into ~/lab/build once at
# container startup, preserving directory structure, and leave it there for
# the whole session. No shred, no session boundary.
#
# DELIBERATE TRADEOFF, not an oversight: this restores the original
# always-decrypted model (the same shape as the old decrypt_watch.sh this
# project moved away from earlier), just targeting ~/lab/build instead of
# the old sibling ~/labs. Plaintext source sits on disk for the entire
# container lifetime once this runs — docker cp, the terminal, or any other
# filesystem access can read it at any time, not just during a narrow
# compile window. This was chosen explicitly in place of the session-scoped
# chipcraft-tree model for projects like tarang2_dp1, to remove the
# start/work/exit friction of that workflow.
#
# Editing still goes through gvim (chipcraft-crypt.vim) when working
# directly on .enc files in ~/lab — this script only affects the bulk
# decrypted copy in build, which is read/write but not re-encrypted on
# change. Edit the real .enc source in ~/lab itself for changes to persist.

set -uo pipefail

WORK="${WORK:-/workspaces/projects/.build.enc}"
BUILD="${BUILD:-/workspaces/projects/build}"
KEYFILE="$HOME/.rbk_state"

# Wait for the key — chipcraft-key-init.sh may still be fetching it,
# especially in Server Mode where it depends on BOOTSTRAP_TOKEN being
# exchanged after this container starts.
tries=0
while [[ ! -f "$KEYFILE" && $tries -lt 60 ]]; do
    sleep 1
    tries=$((tries + 1))
done
if [[ ! -f "$KEYFILE" ]]; then
    echo "[decrypt-all] ERROR: no key available after 60s — skipping bulk decrypt." >&2
    exit 1
fi

mkdir -p "$BUILD"

# Remove top-level ghost directories in BUILD that have no matching project
# directory in WORK (e.g. "workspaces/" from a stray commit in lab-files repo).
find "$BUILD" -mindepth 1 -maxdepth 1 -type d | while IFS= read -r d; do
    base="$(basename "$d")"
    if [[ ! -d "$WORK/$base" ]]; then
        rm -rf "$d"
        echo "[decrypt-all] Removed ghost directory: $d"
    fi
done

KEY=$(cat "$KEYFILE")
count=0
while IFS= read -r enc; do
    case "$enc" in
        *.swp.enc|*.swo.enc) continue ;;
    esac
    rel="${enc#"$WORK"/}"
    # Skip any .enc file whose relative path starts with workspaces/ — these
    # are stray commits from the lab-files repo that mirror the host path and
    # would create a nested workspaces/ tree inside BUILD.
    case "$rel" in
        workspaces/*|.build.enc/*) continue ;;
    esac
    out="$BUILD/${rel%.enc}"
    mkdir -p "$(dirname "$out")"
    if openssl enc -d -aes-256-cbc -pbkdf2 -k "$KEY" -in "$enc" -out "$out" 2>/dev/null; then
        count=$((count + 1))
    fi
done < <(find "$WORK" -path "$BUILD" -prune -o -path "$WORK/.git" -prune -o -name '*.enc' -print)
unset KEY

echo "[decrypt-all] Decrypted $count file(s) into $BUILD"

# Lock only the decrypted .v source files read-only so students cannot edit
# them directly. Directories and compiled output (obj_dir/, Vtb_*, .vvp, .vcd)
# must remain writable/executable — Verilator and iverilog need to create and
# run binaries in the same BUILD tree.
find "$BUILD" -name "*.v" -exec chmod a-w {} \; 2>/dev/null || true
