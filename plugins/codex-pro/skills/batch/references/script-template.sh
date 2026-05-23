#!/usr/bin/env bash
# generate.sh — Batch content generation using Codex CLI
#
# Usage:
#   ./generate.sh              # Process all chunks
#   ./generate.sh 2 3 5        # Process specific chunks
#   FORCE=1 ./generate.sh 2    # Force re-generate
#
# Prerequisites:
#   - /opt/homebrew/bin/codex installed and authenticated
#   - Reference file exists at REF_FILE path

set -euo pipefail

# ── Configuration (CUSTOMIZE THESE) ──────────────────────────────
CODEX="/opt/homebrew/bin/codex"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REF_FILE="__REF_FILE__"                    # Path to reference document
OUTPUT_DIR="$SCRIPT_DIR"
LOG_FILE="$SCRIPT_DIR/progress.log"
MODEL="__MODEL__"                          # e.g., gpt-5.5
REASONING="__REASONING__"                  # e.g., xhigh
OUTPUT_PATTERN="__OUTPUT_PATTERN__"        # e.g., ch${ch}_solutions.tex

# Chunk definitions
ALL_CHUNKS=(__ALL_CHUNKS__)                # e.g., (2 3 4 5 6 7 8 9 10 13)

# Chunk name mapping (optional)
declare -A CHUNK_NAMES=(
__CHUNK_NAMES__
)

# ── Helper functions ─────────────────────────────────────────────
elapsed_since() {
    local start="$1"
    local now
    now=$(date +%s)
    local diff=$(( now - start ))
    printf "%dm%02ds" $(( diff / 60 )) $(( diff % 60 ))
}

log() {
    local msg="[$(date '+%H:%M:%S')] $*"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE"
}

# ── Validation ───────────────────────────────────────────────────
if [[ ! -x "$CODEX" ]]; then
    echo "ERROR: codex not found at $CODEX" >&2
    exit 1
fi

if [[ ! -f "$REF_FILE" ]]; then
    echo "ERROR: Reference file not found at $REF_FILE" >&2
    exit 1
fi

# Determine which chunks to process
if [[ $# -gt 0 ]]; then
    CHUNKS=("$@")
else
    CHUNKS=("${ALL_CHUNKS[@]}")
fi

# ── Generate function ────────────────────────────────────────────
generate_chunk() {
    local ch="$1"
    local output_file
    output_file=$(eval echo "$OUTPUT_DIR/$OUTPUT_PATTERN")
    local chunk_name="${CHUNK_NAMES[$ch]:-Chunk $ch}"

    # Skip if already exists
    if [[ -f "$output_file" && "${FORCE:-}" != "1" ]]; then
        log "  SKIP Chunk $ch: $(basename "$output_file") already exists (FORCE=1 to overwrite)"
        return
    fi

    log "────────────────────────────────────────"
    log "▶ Chunk $ch: $chunk_name"
    log "  Sending reference document as context..."
    log "  Calling codex exec ($MODEL, $REASONING)..."
    local ch_start
    ch_start=$(date +%s)

    # ── PROMPT (CUSTOMIZE THIS) ──────────────────────────────────
    cat <<PROMPT_EOF | "$CODEX" exec \
        -m "$MODEL" \
        -c "model_reasoning_effort=\"$REASONING\"" \
        --skip-git-repo-check \
        --full-auto \
        -o "$output_file" \
        -
__PROMPT_TEMPLATE__
PROMPT_EOF

    local duration
    duration=$(elapsed_since "$ch_start")

    if [[ -f "$output_file" && -s "$output_file" ]]; then
        local lines bytes
        lines=$(wc -l < "$output_file")
        bytes=$(wc -c < "$output_file")
        log "  ✓ Chunk $ch done in $duration → $(basename "$output_file") ($lines lines, $((bytes/1024))KB)"
    else
        log "  ✗ Chunk $ch FAILED after $duration" >&2
    fi
}

# ── Main ─────────────────────────────────────────────────────────
TOTAL_START=$(date +%s)

echo "" >> "$LOG_FILE"
log "════════════════════════════════════════════════════════"
log "Codex Batch Generator"
log "Model: $MODEL | Reasoning: $REASONING"
log "Chunks: ${CHUNKS[*]} (${#CHUNKS[@]} chunks)"
log "Reference: $(wc -l < "$REF_FILE") lines, $(du -h "$REF_FILE" | cut -f1)"
log "════════════════════════════════════════════════════════"

# ── Parallel execution ───────────────────────────────────────────
# Launch all chunks in parallel
for ch in "${CHUNKS[@]}"; do
    generate_chunk "$ch" &
done

# Wait for all to complete
wait

# ── Final report ─────────────────────────────────────────────────
log ""
log "════════════════════════════════════════════════════════"
log "Done! Total time: $(elapsed_since "$TOTAL_START")"
log "Output: $OUTPUT_DIR/"
# Use eval to expand the output pattern for ls
for ch in "${ALL_CHUNKS[@]}"; do
    local_file=$(eval echo "$OUTPUT_DIR/$OUTPUT_PATTERN")
    if [[ -f "$local_file" ]]; then
        log "  $(ls -lh "$local_file")"
    fi
done
log "════════════════════════════════════════════════════════"
