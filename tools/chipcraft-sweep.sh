#!/bin/bash
# ChipCraft Lab — sweep watcher for WORK (.build.enc) and BUILD (build).
#
# WORK (.build.enc):
#   - Plaintext .v files  → encrypt to .enc in WORK, copy .v to BUILD read-only, shred tmp
#   - New .enc files       → lock read-only, decrypt copy into BUILD/
#
# BUILD (build):
#   - .enc files dropped here → decrypt to .v in same location,
#                               move .enc to matching path in WORK,
#                               lock both read-only
#   - .v files (user-created, no matching .enc in WORK)
#                           → encrypt to .enc in WORK, lock .v in BUILD read-only
#   - .v files (legitimate decrypt copy, matching .enc exists in WORK)
#                           → re-lock read-only (no re-encrypt needed)
#
# Two layers: inotify for fast response + periodic poll as backstop.

set -uo pipefail

WORK="${WORK:-/workspaces/projects/.build.enc}"
BUILD="${BUILD:-/workspaces/projects/build}"
KEYFILE="$HOME/.chipcraft_key"
SCRATCH="$BUILD/.sweep-tmp"
ALLOWLIST=("Makefile" ".gitignore" ".gitattributes" "README.md")

mkdir -p "$SCRATCH"

_is_allowed() {
    local base
    base="$(basename "$1")"
    for a in "${ALLOWLIST[@]}"; do
        [[ "$base" == "$a" ]] && return 0
    done
    return 1
}

_wait_for_key() {
    local tries=0
    while [[ ! -f "$KEYFILE" && $tries -lt 30 ]]; do
        sleep 1; tries=$((tries + 1))
    done
    [[ -f "$KEYFILE" ]]
}

# .enc dropped into BUILD:
#   1. Decrypt → .v in same BUILD location (read-only)
#   2. Move .enc → WORK at same relative path (read-only)
_handle_build_enc() {
    local path="$1"
    local rel="${path#"$BUILD"/}"
    local plain="${path%.enc}"
    local enc_in_work="$WORK/$rel"

    _wait_for_key || { echo "[sweep] ERROR: no key — cannot process build/$rel" >&2; return 0; }

    local key
    key=$(cat "$KEYFILE")

    chmod u+w "$plain" 2>/dev/null || true
    if openssl enc -d -aes-256-cbc -pbkdf2 -k "$key" -in "$path" -out "$plain" 2>/dev/null; then
        chmod a-w "$plain" 2>/dev/null || true
        echo "[sweep] Decrypted build/$rel -> build/${rel%.enc}"
    else
        echo "[sweep] ERROR: decrypt failed for build/$rel" >&2
    fi
    unset key

    mkdir -p "$(dirname "$enc_in_work")"
    mv -f "$path" "$enc_in_work"
    chmod a-w "$enc_in_work" 2>/dev/null || true
    echo "[sweep] Moved build/$rel -> .build.enc/$rel"
}

# .v dropped into BUILD (user-created, no matching .enc in WORK):
#   1. Encrypt .v → .enc in WORK
#   2. Lock .v in BUILD read-only (it becomes the legitimate decrypted copy)
_handle_build_v() {
    local path="$1"
    local rel="${path#"$BUILD"/}"
    local enc_in_work="$WORK/${rel}.enc"

    _wait_for_key || { echo "[sweep] ERROR: no key — cannot encrypt build/$rel" >&2; return 0; }

    local key tmp
    key=$(cat "$KEYFILE")
    tmp="$SCRATCH/sweep.$$.$RANDOM"
    mkdir -p "$(dirname "$enc_in_work")"

    if openssl enc -aes-256-cbc -pbkdf2 -salt -k "$key" -in "$path" -out "$tmp" 2>/dev/null; then
        mv -f "$tmp" "$enc_in_work"
        chmod a-w "$enc_in_work" 2>/dev/null || true
        chmod a-w "$path"        2>/dev/null || true
        echo "[sweep] Encrypted build/$rel -> .build.enc/${rel}.enc"
    else
        rm -f "$tmp"
        echo "[sweep] ERROR: could not encrypt build/$rel" >&2
    fi
    unset key
}

_sweep_file() {
    local path="$1"
    [[ -f "$path" ]] || return 0

    # Editor temp files — skip everywhere
    case "$path" in
        *.swp|*.swo|*~) return 0 ;;
    esac

    # ── BUILD directory ───────────────────────────────────────────────────────
    if [[ "$path" == "$BUILD"/* ]]; then
        case "$path" in
            "$BUILD"/.sweep-tmp/*) return 0 ;;
            "$BUILD"/.git/*)       return 0 ;;
        esac

        # .enc in BUILD → decrypt + move to WORK
        if [[ "$path" == *.enc ]]; then
            _handle_build_enc "$path"
            return 0
        fi

        # .v in BUILD
        if [[ "$path" == *.v ]]; then
            _is_allowed "$path" && return 0
            local rel="${path#"$BUILD"/}"
            if [[ -f "$WORK/${rel}.enc" ]]; then
                # Legitimate decrypted copy — just re-lock
                chmod a-w "$path" 2>/dev/null || true
            else
                # User-created with no matching .enc — encrypt to WORK, lock here
                _handle_build_v "$path"
            fi
            return 0
        fi

        # Everything else in BUILD (Makefile, .vcd, .vh, etc.) — exempt
        return 0
    fi

    # ── WORK directory ────────────────────────────────────────────────────────
    case "$path" in
        "$WORK"/.git/*) return 0 ;;
    esac

    # .enc in WORK → lock read-only + sync decrypted .v to BUILD
    if [[ "$path" == *.enc ]]; then
        chmod a-w "$path" 2>/dev/null || true
        if [[ -f "$KEYFILE" ]]; then
            local rel out key
            rel="${path#"$WORK"/}"
            out="$BUILD/${rel%.enc}"
            mkdir -p "$(dirname "$out")"
            key=$(cat "$KEYFILE")
            chmod u+w "$out" 2>/dev/null || true
            if openssl enc -d -aes-256-cbc -pbkdf2 -k "$key" -in "$path" -out "$out" 2>/dev/null; then
                chmod a-w "$out" 2>/dev/null || true
                echo "[sweep] Synced $rel -> build/${rel%.enc}"
            fi
            unset key
        fi
        return 0
    fi

    _is_allowed "$path" && return 0

    # Plaintext .v in WORK → encrypt to .enc, copy .v to BUILD, shred
    local rel tmp enc
    rel="${path#"$WORK"/}"
    enc="${path}.enc"

    tmp="$SCRATCH/sweep.$$.$RANDOM"
    mv -f "$path" "$tmp" 2>/dev/null || return 0

    _wait_for_key || {
        echo "[sweep] ERROR: no key — restoring $rel as plaintext" >&2
        mv -f "$tmp" "$path" 2>/dev/null
        return 0
    }

    local key
    key=$(cat "$KEYFILE")
    if openssl enc -aes-256-cbc -pbkdf2 -salt -k "$key" -in "$tmp" -out "$enc" 2>/dev/null; then
        chmod a-w "$enc" 2>/dev/null || true
        echo "[sweep] Encrypted stray plaintext: $rel -> ${rel}.enc"

        # Copy .v to BUILD so user can see it there (read-only)
        local build_out="$BUILD/$rel"
        mkdir -p "$(dirname "$build_out")"
        chmod u+w "$build_out" 2>/dev/null || true
        cp "$tmp" "$build_out" 2>/dev/null && chmod a-w "$build_out" 2>/dev/null || true
        echo "[sweep] Copied to build/$rel (read-only)"
    else
        echo "[sweep] ERROR: could not encrypt $rel — restoring as plaintext" >&2
        unset key
        mv -f "$tmp" "$path" 2>/dev/null
        return 0
    fi
    unset key

    shred -u "$tmp" 2>/dev/null || rm -f "$tmp"
}

_poll_loop() {
    while true; do
        sleep 5
        find "$WORK" "$BUILD" -type f 2>/dev/null | while IFS= read -r f; do
            _sweep_file "$f"
        done
    done
}

mkdir -p "$WORK"
echo "[sweep] Watching $WORK and $BUILD …"

_poll_loop &

inotifywait -m -r -e close_write,moved_to \
    --exclude '/\.git/' \
    --format '%w%f' "$WORK" "$BUILD" 2>/dev/null \
| while IFS= read -r changed; do
    _sweep_file "$changed"
done
