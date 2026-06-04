#!/usr/bin/env bash
# Grok adversarial critic invocation for the critic-gauntlet skill.
#
# Usage: grok-critic.sh <decisions-folder> <round-number>
# Example: grok-critic.sh /path/to/decisions/ADR-002-bar 1
#
# Reads brief-v<N>.md, proposal-v<N>.md, and any prior round critiques + syntheses
# from the decisions folder. Builds the prompt, calls the xAI API, writes critique-v<N>-grok.md.

set -euo pipefail

# --- Model pin ---------------------------------------------------------------
# Verified current 2026-06-03. Override per-run with GROK_MODEL=... in the env.
# Note: grok-4 was deprecated 2026-05-15 and silently reroutes to grok-4.3.
# Update this line when xAI ships a newer flagship.
MODEL="${GROK_MODEL:-grok-4.3}"
# -----------------------------------------------------------------------------

if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <decisions-folder> <round-number>" >&2
    exit 1
fi

DIR="$1"
ROUND="$2"

if [ ! -d "$DIR" ]; then
    echo "ERROR: decisions folder not found: $DIR" >&2
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
    for f in "$DIR/synthesis-v${PRIOR_ROUND}.md" "$DIR/critique-v${PRIOR_ROUND}-claude.md" "$DIR/critique-v${PRIOR_ROUND}-codex.md" "$DIR/critique-v${PRIOR_ROUND}-grok.md"; do
        if [ -f "$f" ]; then
            PRIOR_CONTEXT="$PRIOR_CONTEXT

===== $(basename "$f") =====
$(cat "$f")"
        fi
    done
fi

DATE=$(date +%Y-%m-%d)

SYSTEM_PROMPT="You are an adversarial architecture critic for round ${ROUND}. Find what is wrong with the proposal. Lead with the strongest objection. No sympathetic openers. No em-dashes. No double-dashes. Match the rigor of prior-round critiques if present. Do NOT re-litigate convergent decisions from prior rounds unless you find new evidence against them. Push on what this version introduces or leaves underspecified. Produce a structured critique in markdown with these 5 sections in order: 1) Three biggest holes, 2) Steel-manned alternatives (80% and 110%), 3) Unstated assumptions (at least 4), 4) Consequences for ADR, 5) Recommendation (ship-as-is, ship-with-amendments, or kill-reformulate) plus confidence level. Begin with the heading '# Critique v${ROUND}: Grok (xAI API direct) ${DATE}' followed by 'Model: ${MODEL} via xAI API direct, adversarial brief.' on its own line."

USER_PROMPT="Read everything below, then produce the critique.

===== BRIEF =====
$(cat "$BRIEF")

===== PROPOSAL (the target of critique) =====
$(cat "$PROPOSAL")
${PRIOR_CONTEXT}

===== TASK =====
Produce the adversarial critique now. Markdown format. No preamble. Start with the heading and metadata, then the 5 sections."

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
        max_tokens: 8000
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
RECOMMENDATION=$(echo "$CONTENT" | grep -iE '(ship.with.amendments|kill.*reformulate|ship.as.is)' | head -1 | tr -d '*' | head -c 80)

echo "Grok critique written to $OUTPUT"
echo "Words: $WORDS"
echo "Recommendation snippet: $RECOMMENDATION"
