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

# ── Build + run each fuzz target ─────────────────────────────────────────────
OVERALL_EXIT=0

for T in "${TARGETS[@]}"; do
    echo ""
    echo "── $T ──────────────────────────────────────────────────────────────────"

    OUTDIR="$ARTIFACT_DIR/$T"
    mkdir -p "$OUTDIR"

    echo "==> Compiling $T with libFuzzer + ASan..."

    # Collect all static archives produced by SPM so transitive deps are linked.
    ARCHIVES=()
    while IFS= read -r f; do ARCHIVES+=("$f"); done \
        < <(find "$BIN_PATH" -maxdepth 1 -name "*.a" 2>/dev/null)

    swiftc \
        -parse-as-library \
        -sanitize=address,fuzzer \
        -O \
        -I "$BIN_PATH" \
        -L "$BIN_PATH" \
        -module-name "$T" \
        "$SCRIPT_DIR/Sources/$T/$T.swift" \
        "${ARCHIVES[@]}" \
        -lxml2 \
        -o "$OUTDIR/$T"

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
