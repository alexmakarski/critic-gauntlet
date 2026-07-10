#!/usr/bin/env bash
# Grok adversarial critic invocation for the critic-gauntlet skill.
#
# Usage: grok-critic.sh <work-folder> <round-number> [--mode architecture|science|editorial]
# Example: grok-critic.sh /path/to/decisions/ADR-002-bar 1
# Example: grok-critic.sh /path/to/critic-runs/spec-001 1 --mode editorial
#
# Reads brief-v<N>.md, proposal-v<N>.md, and any prior round critiques + syntheses
# from the work folder. The --mode flag selects the system-prompt rubric from
# modes/<mode>.system.txt (default: architecture). Builds the prompt, calls the
# xAI API, writes critique-v<N>-grok.md.

set -euo pipefail

# --- Model pin ---------------------------------------------------------------
# Verified current 2026-07-10. Override per-run with GROK_MODEL=... in the env.
# Note: older slugs (grok-4, grok-4.3) are silently rerouted by xAI after
# deprecation. Update this line when xAI ships a newer flagship.
MODEL="${GROK_MODEL:-grok-4.5}"
# -----------------------------------------------------------------------------

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <work-folder> <round-number> [--mode architecture|science|editorial]" >&2
    exit 1
fi

DIR="$1"
ROUND="$2"
shift 2

MODE="architecture"
while [ "$#" -gt 0 ]; do
    case "$1" in
        --mode) MODE="$2"; shift 2 ;;
        *) echo "ERROR: unknown argument: $1" >&2; exit 1 ;;
    esac
done

# Locate the modes dir. Works whether the script sits alongside modes/ (skill folder)
# or in a sibling tools/ dir (plugin layout).
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODES_DIR=""
for cand in "$SELF_DIR/modes" "$SELF_DIR/../skills/critic-gauntlet/modes" "$SELF_DIR/../modes"; do
    [ -d "$cand" ] && { MODES_DIR="$(cd "$cand" && pwd)"; break; }
done
if [ -z "$MODES_DIR" ]; then
    echo "ERROR: modes/ dir not found near $SELF_DIR" >&2
    exit 1
fi
SYSTEM_FILE="$MODES_DIR/${MODE}.system.txt"
if [ ! -f "$SYSTEM_FILE" ]; then
    echo "ERROR: unknown mode '$MODE' (no $SYSTEM_FILE)" >&2
    exit 1
fi

if [ ! -d "$DIR" ]; then
    echo "ERROR: work folder not found: $DIR" >&2
    exit 1
fi

BRIEF="$DIR/brief-v${ROUND}.md"
PROPOSAL="$DIR/proposal-v${ROUND}.md"
OUTPUT="$DIR/critique-v${ROUND}-grok.md"

if [ ! -f "$BRIEF" ]; then
    echo "ERROR: brief not found: $BRIEF" >&2
    exit 1
fi
if [ ! -f "$PROPOSAL" ]; then
    echo "ERROR: proposal not found: $PROPOSAL" >&2
    exit 1
fi

# Resolve a named API key from env, a repo/home .env, or common shell rc files.
resolve_key() {
    local var="$1"
    local val="${!var:-}"
    if [ -n "$val" ]; then printf '%s' "$val"; return 0; fi
    local candidates=(
        "$(cd "$(dirname "$0")" && pwd)/.env"
        "$HOME/.env"
        "$HOME/.zshrc"
        "$HOME/.bashrc"
        "$HOME/.bash_profile"
        "$HOME/.profile"
    )
    for f in "${candidates[@]}"; do
        [ -f "$f" ] || continue
        val=$(grep -E "^(export[[:space:]]+)?${var}=" "$f" 2>/dev/null | tail -1 \
            | sed -E "s/^(export[[:space:]]+)?${var}=//" | tr -d '"' | tr -d "'")
        if [ -n "$val" ]; then printf '%s' "$val"; return 0; fi
    done
    return 1
}

if ! XAI_API_KEY="$(resolve_key XAI_API_KEY)"; then
    echo "ERROR: XAI_API_KEY not found in env, .env, or shell rc files (.zshrc/.bashrc/.bash_profile/.profile)" >&2
    echo "Set it with: export XAI_API_KEY=your-key" >&2
    exit 1
fi
export XAI_API_KEY

# Collect prior-round artifacts if this is round 2+
PRIOR_CONTEXT=""
if [ "$ROUND" -gt 1 ]; then
    PRIOR_ROUND=$((ROUND - 1))
    for f in "$DIR/synthesis-v${PRIOR_ROUND}.md" "$DIR/critique-v${PRIOR_ROUND}-claude.md" "$DIR/critique-v${PRIOR_ROUND}-codex.md" "$DIR/critique-v${PRIOR_ROUND}-grok.md" "$DIR/critique-v${PRIOR_ROUND}-gemini.md" "$DIR/critique-v${PRIOR_ROUND}-deepseek.md"; do
        if [ -f "$f" ]; then
            PRIOR_CONTEXT="$PRIOR_CONTEXT

===== $(basename "$f") =====
$(cat "$f")"
        fi
    done
fi

DATE=$(date +%Y-%m-%d)

# --- Editorial mode: real cold read (two-call protocol) -----------------------
# The editorial brief requires a first pass over the article WITHOUT the brief
# or atoms; a single stuffed prompt cannot deliver that. In editorial mode,
# call 1 sees the article alone and returns the cold-read log; call 2 gets the
# full materials plus those notes.
COLD_BLOCK=""
if [ "$MODE" = "editorial" ]; then
    COLD_SYSTEM="You are an independent editorial critic on your FIRST pass over an article. You have not seen the brief or source materials yet; that is deliberate. Read the article cold, top to bottom. Produce ONLY your cold-read log: where your attention flagged, where you got confused, where you stopped believing, whether you would have kept reading if it landed in your inbox. Quote the exact passages. No em-dashes. No double hyphens. No preamble, no summary of the article, no verdict."
    COLD_PAYLOAD=$(jq -n \
        --arg model "$MODEL" \
        --arg system "$COLD_SYSTEM" \
        --arg user "$(cat "$PROPOSAL")" \
        '{
            model: $model,
            messages: [
                {role: "system", content: $system},
                {role: "user", content: $user}
            ],
            temperature: 0.3,
            max_tokens: 8000
        }')
    COLD_RESPONSE=$(curl -sS https://api.x.ai/v1/chat/completions \
        -H "Authorization: Bearer $XAI_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$COLD_PAYLOAD")
    COLD_NOTES=$(echo "$COLD_RESPONSE" | jq -r '.choices[0].message.content // empty')
    if [ -z "$COLD_NOTES" ]; then
        echo "ERROR: empty cold-read response from xAI API (editorial two-call, call 1)" >&2
        echo "$COLD_RESPONSE" >&2
        exit 1
    fi
    COLD_BLOCK="

===== YOUR COLD-READ NOTES (your own first pass, article only; reproduce verbatim as your cold-read log) =====
$COLD_NOTES"
fi
# -----------------------------------------------------------------------------

# System prompt = mode rubric with placeholders substituted. This critic's identity.
SYSTEM_PROMPT=$(cat "$SYSTEM_FILE")
SYSTEM_PROMPT="${SYSTEM_PROMPT//\{\{ROUND\}\}/$ROUND}"
SYSTEM_PROMPT="${SYSTEM_PROMPT//\{\{DATE\}\}/$DATE}"
SYSTEM_PROMPT="${SYSTEM_PROMPT//\{\{CRITIC\}\}/Grok (xAI API direct)}"
SYSTEM_PROMPT="${SYSTEM_PROMPT//\{\{MODEL\}\}/$MODEL via xAI API direct}"

USER_PROMPT="Read everything below, then produce the critique.

===== BRIEF =====
$(cat "$BRIEF")

===== MATERIAL UNDER REVIEW (the target of critique) =====
$(cat "$PROPOSAL")
${PRIOR_CONTEXT}${COLD_BLOCK}

===== TASK =====
Produce the adversarial critique now. Markdown format. No preamble. Start with the heading and metadata, then follow the brief's output format."

PAYLOAD=$(jq -n \
    --arg model "$MODEL" \
    --arg system "$SYSTEM_PROMPT" \
    --arg user "$USER_PROMPT" \
    '{
        model: $model,
        messages: [
            {role: "system", content: $system},
            {role: "user", content: $user}
        ],
        temperature: 0.3,
        max_tokens: 16000
    }')

RESPONSE=$(curl -sS https://api.x.ai/v1/chat/completions \
    -H "Authorization: Bearer $XAI_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")

CONTENT=$(echo "$RESPONSE" | jq -r '.choices[0].message.content // .error // "ERROR: no content"')

if [ -z "$CONTENT" ] || [ "$CONTENT" = "null" ]; then
    echo "ERROR: empty response from xAI API" >&2
    echo "Full response:" >&2
    echo "$RESPONSE" >&2
    exit 1
fi

echo "$CONTENT" > "$OUTPUT"

WORDS=$(echo "$CONTENT" | wc -w | tr -d ' ')
RECOMMENDATION=$( (echo "$CONTENT" | grep -iE '(ship.with.amendments|kill.{0,3}re.?formulate|ship.as.is)' || true) | head -1 | tr -d '*' | head -c 80)

echo "Grok critique written to $OUTPUT"
echo "Words: $WORDS"
echo "Recommendation snippet: $RECOMMENDATION"
