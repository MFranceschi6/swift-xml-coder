#!/usr/bin/env bash
# Build and run SwiftXMLCoder fuzz targets using libFuzzer + AddressSanitizer.
#
# Requirements:
#   - Swift 5.9+ with LLVM-based toolchain (linux or macOS with Xcode 15+)
#   - libxml2-dev (Linux) or Xcode command-line tools (macOS)
#   - ASAN/libFuzzer support in the active Swift toolchain
#
# Usage:
#   ./run_fuzzer.sh                   # run all targets
#   ./run_fuzzer.sh FuzzXMLParser     # run a single target
#   FUZZ_TIME=300 ./run_fuzzer.sh     # run for 5 minutes each
#
# Environment:
#   FUZZ_TIME    — seconds per target (default: 60)
#   ARTIFACT_DIR — directory for crash reproducers (default: /tmp/fuzz-output)

set -euo pipefail

TARGET="${1:-}"
FUZZ_TIME="${FUZZ_TIME:-60}"
ARTIFACT_DIR="${ARTIFACT_DIR:-/tmp/fuzz-output}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ALL_TARGETS=(FuzzXMLParser FuzzXMLDecoder)

if [ -n "$TARGET" ] && [[ ! " ${ALL_TARGETS[*]} " =~ " $TARGET " ]]; then
    echo "error: unknown target '$TARGET'. Available: ${ALL_TARGETS[*]}" >&2
    exit 1
fi

TARGETS=("${TARGET:-${ALL_TARGETS[@]}}")

cd "$REPO_ROOT"

# ── Build SwiftXMLCoder with ASan instrumentation ────────────────────────────
echo "==> Building SwiftXMLCoder with AddressSanitizer..."
swift build -c release -Xswiftc -sanitize=address

BIN_PATH=$(swift build -c release --show-bin-path)
echo "    BIN_PATH: $BIN_PATH"

MODULE_DIR="$BIN_PATH/Modules"
CSHIM_MODULE_DIR="$BIN_PATH/SwiftXMLCoderCShim.build"
OWNERSHIP_MODULE_DIR="$BIN_PATH/SwiftXMLCoderOwnership6.build"

if [ ! -d "$MODULE_DIR" ]; then
    echo "error: expected Swift module directory at '$MODULE_DIR'" >&2
    exit 1
fi

if [ ! -f "$MODULE_DIR/SwiftXMLCoder.swiftmodule" ]; then
    echo "error: expected SwiftXMLCoder.swiftmodule at '$MODULE_DIR/SwiftXMLCoder.swiftmodule'" >&2
    exit 1
fi

if [ ! -f "$CSHIM_MODULE_DIR/module.modulemap" ]; then
    echo "error: expected SwiftXMLCoderCShim module map at '$CSHIM_MODULE_DIR/module.modulemap'" >&2
    exit 1
fi

LIBXML2_SWIFTC_FLAGS=()
if command -v pkg-config >/dev/null 2>&1; then
    read -r -a LIBXML2_CFLAGS <<< "$(pkg-config --cflags libxml-2.0 2>/dev/null)"
    for flag in "${LIBXML2_CFLAGS[@]}"; do
        LIBXML2_SWIFTC_FLAGS+=(-Xcc "$flag")
    done
fi

if [ ${#LIBXML2_SWIFTC_FLAGS[@]} -eq 0 ] && [ -d "/usr/include/libxml2" ]; then
    LIBXML2_SWIFTC_FLAGS+=(-Xcc -I/usr/include/libxml2)
fi

# ── Build + run each fuzz target ─────────────────────────────────────────────
OVERALL_EXIT=0

for T in "${TARGETS[@]}"; do
    echo ""
    echo "── $T ──────────────────────────────────────────────────────────────────"

    OUTDIR="$ARTIFACT_DIR/$T"
    mkdir -p "$OUTDIR"

    echo "==> Compiling $T with libFuzzer + ASan..."

    # Prefer static archives (Linux CI). Fall back to SPM-produced object files on
    # platforms like macOS where release library builds may not emit .a archives.
    LINK_INPUTS=()
    while IFS= read -r f; do LINK_INPUTS+=("$f"); done \
        < <(find "$BIN_PATH" -maxdepth 1 -name "*.a" 2>/dev/null)

    if [ ${#LINK_INPUTS[@]} -eq 0 ]; then
        while IFS= read -r f; do LINK_INPUTS+=("$f"); done \
            < <(find \
                "$BIN_PATH/SwiftXMLCoder.build" \
                "$BIN_PATH/SwiftXMLCoderCShim.build" \
                "$BIN_PATH/SwiftXMLCoderOwnership6.build" \
                "$BIN_PATH/XMLCoderCompatibility.build" \
                "$BIN_PATH/Logging.build" \
                -name "*.o" 2>/dev/null)
    fi

    if [ ${#LINK_INPUTS[@]} -eq 0 ]; then
        echo "error: could not find link inputs under '$BIN_PATH'" >&2
        exit 1
    fi

    SWIFTC_ARGS=(
        -parse-as-library
        -sanitize=address,fuzzer
        -O
        -I "$MODULE_DIR"
        -I "$CSHIM_MODULE_DIR"
        -I "$OWNERSHIP_MODULE_DIR"
        -L "$BIN_PATH"
        -module-name "$T"
        "${LIBXML2_SWIFTC_FLAGS[@]}"
        "$SCRIPT_DIR/Sources/$T/$T.swift"
        -lxml2
        -o "$OUTDIR/$T"
    )
    SWIFTC_ARGS+=("${LINK_INPUTS[@]}")

    swiftc "${SWIFTC_ARGS[@]}"

    echo "==> Running $T for ${FUZZ_TIME}s (crash artifacts → $OUTDIR)..."
    "$OUTDIR/$T" \
        "$SCRIPT_DIR/corpus/xml" \
        -artifact_prefix="$OUTDIR/" \
        -max_total_time="$FUZZ_TIME" \
        -max_len=65536 \
        -print_final_stats=1 \
        && echo "    ✓ $T: no crashes found." \
        || { echo "    ✗ $T: crash detected — reproducer saved to $OUTDIR"; OVERALL_EXIT=1; }
done

echo ""
exit "$OVERALL_EXIT"
