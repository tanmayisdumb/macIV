#!/bin/bash
# downgrade.sh - Convert Steam Complete Edition GTAIV.exe to clean v1.0.8.0
# Part of macIV (https://github.com/tanmayisdumb/macIV)
set -euo pipefail

TARGET_SHA="3d90e7c516fa450ca002e5031e62c0f66b404590f33e6cc9793b0da4fffbfd0f"
STEAM_CE_SHA="08759a5516f9837920ea504436236bbab89d0826a8e4d04ff106345177b5345d"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_FILE="$SCRIPT_DIR/ce_to_1080.patch"

# Color helpers
if [ -t 1 ]; then
    CYAN='\033[0;36m'
    GREEN='\033[0;32m'
    GOLD='\033[0;33m'
    RED='\033[0;31m'
    RESET='\033[0m'
else
    CYAN='' GREEN='' GOLD='' RED='' RESET=''
fi

info()  { printf "%s==>%s %s\n" "$CYAN" "$RESET" "$*"; }
ok()    { printf "%s✔%s %s\n" "$GREEN" "$RESET" "$*"; }
warn()  { printf "%s⚠ Notice:%s %s\n" "$GOLD" "$RESET" "$*"; }
die()   { printf "%s✖ Error:%s %s\n" "$RED" "$RESET" "$*" >&2; exit 1; }

# Find bspatch (built into all macOS installations)
BSPATCH="/usr/bin/bspatch"
if [ ! -x "$BSPATCH" ]; then
    BSPATCH="$(command -v bspatch 2>/dev/null || true)"
fi
[ -n "$BSPATCH" ] && [ -x "$BSPATCH" ] || die "bspatch not found. Required to apply binary delta."

# Determine input executable
INPUT_EXE="${1:-}"

if [ -z "$INPUT_EXE" ]; then
    # Try looking in common places
    if [ -f "GTAIV.exe" ]; then
        INPUT_EXE="GTAIV.exe"
    elif [ -f "GTAIV.exe.original" ]; then
        INPUT_EXE="GTAIV.exe.original"
    else
        STEAM_DEFAULT="$HOME/Library/Application Support/Steam/steamapps/common/Grand Theft Auto IV/GTAIV/GTAIV.exe"
        if [ -f "$STEAM_DEFAULT" ]; then
            INPUT_EXE="$STEAM_DEFAULT"
        fi
    fi
fi

[ -n "$INPUT_EXE" ] || die "Usage: $0 /path/to/GTAIV.exe [output_path]"
[ -f "$INPUT_EXE" ] || die "Input file does not exist: $INPUT_EXE"

OUTPUT_EXE="${2:-$(dirname "$INPUT_EXE")/GTAIV.exe}"

info "Checking GTAIV.exe ($INPUT_EXE)..."
CURRENT_SHA="$(shasum -a 256 "$INPUT_EXE" | awk '{print $1}')"

if [ "$CURRENT_SHA" = "$TARGET_SHA" ]; then
    ok "Executable is already clean v1.0.8.0 (SHA-256: $TARGET_SHA)."
    if [ "$INPUT_EXE" != "$OUTPUT_EXE" ]; then
        cp "$INPUT_EXE" "$OUTPUT_EXE"
        chmod +x "$OUTPUT_EXE"
        ok "Copied to $OUTPUT_EXE"
    fi
    exit 0
fi

# Locate patch file
if [ ! -f "$PATCH_FILE" ]; then
    # Check parent / resources directory
    for candidate in "$SCRIPT_DIR/../ce_to_1080.patch" \
                     "$SCRIPT_DIR/ce_to_1080.patch" \
                     "/tmp/ce_to_1080.patch"; do
        if [ -f "$candidate" ]; then
            PATCH_FILE="$candidate"
            break
        fi
    done
fi

if [ ! -f "$PATCH_FILE" ]; then
    die "Patch file ce_to_1080.patch not found in $SCRIPT_DIR"
fi

info "Detected input version (SHA-256: $CURRENT_SHA)"
if [ "$CURRENT_SHA" = "$STEAM_CE_SHA" ]; then
    info "Recognized standard Steam Complete Edition (v1.2.0.x)."
else
    warn "Unrecognized Complete Edition build, attempting patch conversion..."
fi

TMP_OUT="$(mktemp -t gtaiv_patched.XXXXXX)"
trap 'rm -f "$TMP_OUT"' EXIT

info "Applying binary delta patch using native bspatch..."
"$BSPATCH" "$INPUT_EXE" "$TMP_OUT" "$PATCH_FILE"

RESULT_SHA="$(shasum -a 256 "$TMP_OUT" | awk '{print $1}')"
if [ "$RESULT_SHA" != "$TARGET_SHA" ]; then
    die "Patch verification failed! Resulting SHA-256 was $RESULT_SHA, expected $TARGET_SHA."
fi

# Backup original if writing in place
if [ "$INPUT_EXE" = "$OUTPUT_EXE" ]; then
    BACKUP="${OUTPUT_EXE}.original"
    if [ ! -f "$BACKUP" ]; then
        info "Backing up original executable to ${BACKUP}..."
        mv "$INPUT_EXE" "$BACKUP"
    fi
fi

mv "$TMP_OUT" "$OUTPUT_EXE"
chmod +x "$OUTPUT_EXE"
trap - EXIT

ok "Successfully downgraded to clean v1.0.8.0!"
ok "Output: $OUTPUT_EXE"
ok "Verified SHA-256: $TARGET_SHA"
