---
name: critic-gauntlet
version: 2.1.0
description: Run an adversarial critic gauntlet on an architectural proposal. Spawns a Claude general-purpose subagent plus optional Codex CLI, Grok (xAI API), and Gemini (Google AI Studio API) critics in parallel, surfaces raw critic outputs verbatim, then synthesizes. Use for architectural decisions (system shape, delivery mechanism, multi-tenancy model, new critical-path dependency, repo structure).
---

# Critic Gauntlet

For architectural decisions where the cost of being wrong is high. Forces independent adversarial critics against a proposal, surfaces raw output verbatim before synthesis, and iterates until convergence or specification-level findings emerge.

The value is cross-model disagreement: different model families share different blind spots, so a hole one misses another tends to catch. Convergence across independent models is a strong signal; a lone-critic finding is sometimes the most valuable thing in the round.

## Roster

The full roster is four critics:

1. **Claude general-purpose subagent** (baseline, always available, no API key, included with Claude Code)
2. **Codex CLI** (requires the `codex` CLI installed and authenticated)
3. **Grok via the xAI API** (requires `XAI_API_KEY`)
4. **Gemini via the Google AI Studio API** (requires `GEMINI_API_KEY`)

Only critic 1 is required. The other three are bolt-ons you enable when you have the credentials. Running with just the Claude subagent is valid but weak: you lose the cross-model diversity that is the whole point. Two or three models arguing is materially better; four is the recommended bar for a decision you cannot cheaply reverse.

If you have all four configured, run all four by default. Drop a critic on a given round only when speed matters more than coverage. Grok and Gemini carry higher noise floors than Claude and Codex, so if you are trimming, drop one of those two first.

## When to invoke

Architectural decisions: system shape, delivery mechanism, multi-tenancy model, a new critical-path dependency, repo structure. Anything where the shape, once shipped, is expensive to change.

Non-architectural changes (bug fixes, refactors, feature additions inside an existing shape) do NOT need this. The gauntlet is expensive in attention and time. Do not run it on small decisions.

## What you need before invoking

1. **A written proposal** at a known file path. Markdown. Should include: status, context, proposal (what you are proposing), what it trades, open questions.
2. **A decisions folder** to hold artifacts. Suggested convention: `<your-repo>/decisions/ADR-NNN-<topic>/`. The proposal, brief, critiques, and synthesis all live together.
3. **Optional context files** the critics should read (an existing ARCHITECTURE.md, contributor/AI guidelines, prior critiques if this is round 2+).

## The flow

### Step 1: Probe the roster

Before doing anything else, determine which critics are available on this machine and announce the roster to the user.

```bash
# Probe each critic. Print "available" or "skipped: <reason>".
echo "Critic roster:"

# Claude (always available)
echo "  Claude general-purpose subagent: available"

# Codex CLI
if command -v codex &>/dev/null; then
    echo "  Codex CLI: available"
else
    echo "  Codex CLI: skipped (codex not on PATH)"
fi

# Grok via xAI
if [ -n "${XAI_API_KEY:-}" ]; then
    echo "  Grok-4 (xAI): available"
else
    echo "  Grok-4 (xAI): skipped (XAI_API_KEY not set)"
fi

# Gemini via Google AI Studio
if [ -n "${GEMINI_API_KEY:-}" ]; then
    echo "  Gemini 3.1 Pro Preview (Google AI Studio): available"
else
    echo "  Gemini 3.1 Pro Preview (Google AI Studio): skipped (GEMINI_API_KEY not set)"
fi
```

If only Claude is available, warn the user that this is a degenerate run and ask whether to proceed. Otherwise proceed without prompting.

### Step 2: Write the adversarial brief

Save to `<decisions-folder>/brief-v<N>.md` where N is the round number.

Template:

```markdown
# Adversarial Critic Brief: <ADR title> Round <N>

You are an adversarial architecture critic. Your job is NOT to help, validate, or improve this proposal sympathetically. Your job is to find what is wrong with it, what it glosses over, and what it would cost if shipped.

This is round <N>. <Summarize what prior rounds killed, if applicable. Tell critics not to re-litigate already-converged decisions.>

## Required reading

1. <path to proposal-vN.md>
2. <path to prior synthesis if round 2+>
3. <paths to prior critiques if round 2+>

Optional context:
- <path to ARCHITECTURE.md>
- <path to contributor or AI guidelines>
- <any schema or related code>

## What you must produce

A structured critique with these sections in this order:

### 0. The boring baseline (answer this first)
State the most standard, well-understood, right-fit way to solve THIS specific job. "Boring" means standard and right-fit, NOT fewest new parts: reusing an existing wrong-fit tool to avoid building anything is not the boring baseline, it is a trap. The boring baseline is often a recomposition of parts already in use, or one small standard service on infrastructure already run. Then state why the proposal is not just that. Resist new dependencies, platforms, and novel patterns, not new parts per se. A proposal that cannot beat the boring baseline on a demonstrated (not hypothetical) benefit should lose to it.

### 0.5 The blank-sheet design (diagnostic, answer right after the baseline)
State what you would build for this job from a blank sheet, with NO existing code, infrastructure, or product, ignoring all sunk cost. Then state the delta from current reality. This is a MIRROR, not a migration mandate: a large delta is a prompt to ask why the system drifted and whether the gap is worth any migration cost, never an instruction to rebuild. If the blank-sheet design and the boring baseline agree, say so plainly (the current shape is a defensible choice, not an accident). If they diverge, the gap is the path-dependence cost the ADR must price explicitly, separating the deltas worth a cutover from the ones to simply keep.

### 1. Three biggest holes
Specific architectural or operational problems. Concrete failure modes or real costs the proposer is glossing over.

### 2. Steel-manned alternatives
- 80% alternative: a simpler version that gets most of the value with less change. Name specifically.
- 110% alternative: a more rigorous end state the proposer is dismissing. Name specifically.

### 3. Unstated assumptions
At least 4. For each, state why it might be wrong.

### 4. Consequences for ADR
If this ships as-is, what will the team regret in 6 months?

### 5. Recommendation
- Ship as-is, OR
- Ship with named amendments (list them), OR
- Kill, re-formulate (with what to re-formulate around)

State confidence level: high / moderate / low / unknown.

## Adversarial posture

- No sympathetic openers ("great proposal", "well thought out", "you're right")
- No balanced view; surface the strongest case against
- Lead with the strongest objection
- Read prior critiques if any to calibrate rigor
- No em-dashes or double-dashes anywhere in output
- Markdown. No introduction. No closing pleasantry.
```

### Step 3: Spawn the critics in parallel

In a single message, fire all enabled critic tool calls.

**Critic 1: Claude general-purpose subagent.** Use the Agent tool with `subagent_type: "general-purpose"`. Tell the agent to read the brief, read the required files, write its critique to `<decisions-folder>/critique-v<N>-claude.md`, and confirm with a one-line output. Run in background.

**Critic 2: Codex CLI.** Use Bash with `codex exec --sandbox workspace-write --skip-git-repo-check --cd <decisions-folder> "<inline prompt>"`. The prompt mirrors the Claude one. Pipe `</dev/null` to close stdin (Codex hangs on stdin otherwise). Pipe stdout through `tail -30` to keep the bash output bounded. Run in background.

**Critic 3: Grok via the xAI API.** Use the helper script `grok-critic.sh` from this skill folder. It reads `XAI_API_KEY` from env (or a `.env` / shell rc fallback), concatenates brief + proposal + prior critiques, calls the xAI API, and writes `critique-v<N>-grok.md`. Run via Bash in background.

**Critic 4: Gemini via the Google AI Studio API.** Use the helper script `gemini-critic.sh` from this skill folder. Same shape as Grok. Reads `GEMINI_API_KEY`, calls the Google AI Studio API, writes `critique-v<N>-gemini.md`. Run via Bash in background.

The helper scripts take two arguments: the decisions folder path and the round number. Both auto-pick up prior-round critiques when N > 1.

### Step 4: Verify every critic returned a real critique (liveness gate)

Do not synthesize until every enabled critic has either produced a valid critique or been explicitly dropped by the user. A missing critic must never be silently absorbed: a degraded roster is a decision, not a default. The most common way a gauntlet quietly loses signal is a critic that erred without anyone noticing, and the synthesis treating three-of-an-intended-four as if four had agreed.

Typical timing: Claude subagent 2-3 min, Codex CLI 5-10 min, Grok and Gemini under a minute.

**Success condition (same gate for all critics).** A critic passed only if ALL hold:
1. Its `critique-v<N>-<critic>.md` file exists and is at least ~500 bytes. Real critiques run 3 KB and up; anything smaller is a stub or error.
2. The file is the actual 5-section critique, not an error payload. Reject if it leads with `ERROR:` or contains raw API error JSON.
3. For the Bash critics (Codex, Grok, Gemini): the process exit code was 0. The helper scripts `set -euo pipefail` and exit non-zero on any missing-key / API / empty-response failure. Capture the last stderr line as the failure reason.
4. For the Claude subagent: the Agent tool returned success and the file was written. A subagent that erred without writing the file is a fail even if it returned some text.

**On any critic failing: retry once, then halt.**
1. Retry the failed critic exactly once. Transient infrastructure, rate-limit, and spawn errors usually clear on the second attempt.
2. If it fails the second time, STOP. Do not synthesize. Tell the user, in plain language: which critic is down, the captured failure reason, the role lost (roster below), the surviving roster, and the choice: proceed with the reduced roster / pause and fix / abort the round.
3. The default recommendation depends on WHICH critic died:
   - Lost an ANCHOR (Claude or Codex, the two low-noise models): default to PAUSE. The synthesis leans on anchor agreement; losing one materially degrades signal.
   - Lost a NOISE-FLOOR critic (Grok or Gemini): a reduced run is acceptable. Default to proceed; note the loss in the synthesis roster line.

**Billing note for the Claude critic.** The Claude critic runs as a Claude Code subagent on your existing subscription, not as a metered API call, and it requires no `ANTHROPIC_API_KEY`. Do not "fix" a Claude failure by setting one: in Claude Code, setting `ANTHROPIC_API_KEY` anywhere in the environment routes the entire app to API billing instead of your subscription. If the subagent fails, retry it (above); never reach for a key.

**Roster roles (so a loss is costed correctly):**
- Claude subagent: operational-nuance anchor, low noise, no API key.
- Codex CLI: specification-bug anchor, low noise.
- Grok: privacy / policy / jurisdictional angles. Higher noise.
- Gemini: catches blind spots shaped by a different training distribution than the other three. Highest noise.

Whatever the outcome, the synthesis roster line must name every critic that was attempted and its status (returned / dropped-after-2-fails / user-skipped), so the degraded-roster fact survives into the record.

### Step 5: Surface raw critic outputs verbatim

Read each critique file and present its content to the user verbatim. Do not summarize before the user has seen the raw text. A one-line preamble per critique is fine ("Claude returned. Recommends X."), but the actual critique content goes through verbatim. The point of independent critics is defeated if a synthesizer filters them before the human sees them.

### Step 5.5: Decision discipline (non-negotiable; this is where ADR-002 failed)

The critique stage is not the weak point of this gauntlet; synthesis is. The classic failure: critics unanimously reject an approach and converge on a simpler alternative, then the synthesis (written by the same agent that wrote the proposal) overrides all of them with one persuasive sentence and ships the exact architecture the gauntlet was run to prevent. These rules bind the synthesis so the producer can no longer grade the critics:

1. **Convergence BINDS the decision, not just the next iteration.** If critics converge against the proposed approach (4-of-4, 3-of-4, 3-of-3, or 2-of-3), you may NOT adopt the rejected approach in `decision.md`. The convergent alternative is the default outcome.
2. **Overriding convergence requires explicit escalation, never prose.** If you believe the converged critics are wrong, you may not bury the reversal in the synthesis or decision. Stop and put it to the user in plain words: "All N critics say X. I am proposing NOT-X. Here is exactly what I am asking you to overrule them on, and why." The user overrides consciously, or the convergent answer stands. A hypothetical objection ("it might not scale") is not grounds; only a demonstrated one is.
3. **The synthesizer is not the proposer (always, no exceptions).** The main session is anchored by the whole discussion, so it never writes the synthesis. Spawn a FRESH general-purpose agent (Agent tool, `subagent_type: "general-purpose"`, `model: "haiku"`, a deliberately small model so the judge cannot out-clever the critics) and hand it the fixed synthesis-agent prompt (see "Synthesis agent invocation" below) verbatim. Do not author findings for it or summarize the critiques for it; it reads the raw critiques and the proposal from files itself. Then surface its `synthesis-v<N>.md` to the user VERBATIM, the same rule as the raw critiques, so the proposer cannot spin the verdict on relay. The thing with ego in the proposal neither writes the synthesis nor narrates it.
4. **Boring-baseline must be answered in the synthesis.** Restate the most standard, right-fit way to do this for the job (reuse, a recomposition of existing parts, or one small standard new service, whichever actually fits; reusing a wrong-fit existing tool is NOT the boring baseline). State why the chosen design is not just that. If "why not the boring way" has no demonstrated answer, the boring way wins.
5. **Proof-of-life before "decided."** No `decision.md` is accepted until one real end-to-end slice runs on real infrastructure. A decision on paper is a hypothesis.

### Step 6: Synthesize to `<decisions-folder>/synthesis-v<N>.md`

The synthesis identifies:

- **All-critic convergence (4-of-4, or 3-of-3 if running three).** Strongest possible signal. Binding for the next iteration AND for the final decision (Step 5.5): you may not ship an architecture the critics converged against without explicit user override.
- **Majority convergence.** Strong signal. Worth incorporating.
- **Split convergence.** Evaluate by which critics converged. The two lowest-noise models agreeing (Claude + Codex) is high signal. The two noisier models agreeing (Grok + Gemini) should be treated as one combined noisy vote: verify the finding before incorporating. A mixed pair is case-by-case.
- **Single-critic novel findings.** Sometimes the most valuable. Codex tends to catch specification bugs others miss. Claude tends to catch operational nuance. Grok tends to catch privacy/policy/jurisdictional angles. Gemini catches things shaped by a different training distribution.
- **Recommendation split.** Models differ systematically in how readily they recommend killing vs. amending. Track each critic's calibration over several decisions. Do not over-weight any single critic's kill recommendation when the majority amends.

Then surface the decision question to the user. Two paths:
- **Path A: another round.** Write proposal-v<N+1> incorporating the convergent amendments, run the gauntlet again.
- **Path B: amend in place.** Write `decision.md` (the actual ADR) with the convergent amendments as load-bearing fixes and the lone-critic novel findings as documented limitations.

The bar for stopping: the pattern of findings has shifted from architecture ("the shape is wrong") to specification ("the shape is right, but the spec is imprecise in N places"). Architecture findings require iteration. Specification findings can be amended in place.

### Step 7: After the user picks a path

If Path A: draft proposal-v<N+1>, repeat from Step 2.
If Path B: write `decision.md` with the chosen architecture, the load-bearing fixes as "Blocking work before code," and the documentable items as "Known limitations." Update the related `ARCHITECTURE.md` if relevant.

## Files this skill writes

Per round:
- `brief-v<N>.md`
- `critique-v<N>-claude.md`
- `critique-v<N>-codex.md`
- `critique-v<N>-grok.md`
- `critique-v<N>-gemini.md` (when Gemini is enabled for the round)
- `synthesis-v<N>.md`

After acceptance:
- `decision.md`
- Updated `ARCHITECTURE.md` if relevant

## Worked example

A four-round run on a real decision (renderer delivery mechanism) is reproduced in `examples/worked-example.md`. It shows how findings shift from architecture to specification across rounds, which is the signal that the gauntlet has done its job and can stop. Read it to calibrate what "good" convergence looks like.

## Critic invocation reference

### Claude general-purpose subagent prompt template

```
You are an adversarial architecture critic for <ADR-title> round <N>.

STEP 1: Read /path/to/brief-v<N>.md in full.

STEP 2: Read required files in the order specified.

STEP 3: Write your critique to /path/to/critique-v<N>-claude.md with this header:

# Critique v<N>: Claude (general-purpose subagent) <date>

Model: Claude via general-purpose subagent type, adversarial brief.
Brief location: brief-v<N>.md in this folder.

---

Then the 5 sections.

STEP 4: After writing, output ONE LINE: 'Critique written to <path>, N words, recommendation: <ship-as-is | amendments | kill>'

POSTURE:
- Adversarial. Find what is wrong.
- Read prior critiques if any (in same folder) to calibrate rigor.
- No em-dashes or double-dashes. Use periods, commas, colons.
- Lead with the strongest objection, no sympathetic opener.
```

### Synthesis agent invocation

The synthesis is written by a FRESH general-purpose agent, never the main (proposer) session (Step 5.5 rule 3). Spawn it with the Agent tool, `subagent_type: "general-purpose"`, `model: "haiku"` (a deliberately small model: the synthesis job is near-mechanical, and a less-clever judge cannot rationalize past the critics), and pass this prompt verbatim. Do not summarize the critiques for it; it reads them itself. Surface its output to the user verbatim.

```
You are the neutral synthesizer for <ADR-title> round <N>. You did NOT write the proposal and have no stake in it. Treat the proposal as a hypothesis to disprove.

STEP 1: Read in full: <proposal-vN.md>, and every critique-v<N>-*.md in <decisions-folder>.

STEP 2: Write <decisions-folder>/synthesis-v<N>.md covering:
- Convergence: what 4-of-4 / 3-of-4 / 2-of-4 critics agreed on. Convergence AGAINST the proposed approach is BINDING: you may not recommend an approach the critics converged against.
- The boring baseline: the most standard, right-fit way to do this for the job (reuse OR a small standard new part, whichever fits; reusing a wrong-fit tool is not boring), and whether the proposal beats it on a demonstrated (not hypothetical) benefit. If it does not, recommend the boring baseline.
- The blank-sheet delta: what a from-scratch design (no sunk cost) would be, how far current reality is from it, and which deltas are worth migration cost versus pure path-dependence to keep. Use it as a mirror on the boring baseline, never as a rebuild mandate.
- Single-critic novel findings worth keeping.
- Recommendation: adopt convergent alternative / amend proposal / proceed. If you believe a convergence is wrong, do NOT override it; flag it for explicit human decision.

STEP 3: Output ONE LINE: 'Synthesis written to <path>, recommendation: <...>'

POSTURE: neutral judge, not advocate. No sympathetic opener. Lead with what the critics converged on. No em-dashes or double-dashes.
```

### Codex CLI invocation

```bash
codex exec --sandbox workspace-write --skip-git-repo-check --cd <decisions-folder> "<same prompt template>" </dev/null 2>&1 | tail -30
```

Important: `</dev/null` is required. Without it, `codex exec` waits on stdin and hangs indefinitely.

### Grok invocation

```bash
./grok-critic.sh <decisions-folder> <round-number>
```

Reads `brief-v<N>.md` and `proposal-v<N>.md`, builds the prompt, calls the xAI API, writes `critique-v<N>-grok.md`. Requires `XAI_API_KEY`. The model is pinned at the top of the script (override per run with `GROK_MODEL=...`).

### Gemini invocation

```bash
./gemini-critic.sh <decisions-folder> <round-number>
```

Same shape as Grok. Requires `GEMINI_API_KEY`. The model is pinned at the top of the script (override per run with `GEMINI_MODEL=...`). Free tier covers normal usage; paid tier is sub-penny per critique.

## Models to skip

**Single-shot MCP wrappers** (e.g. a `chatgpt_query` or `gemini_query` MCP tool) without agentic file reading tend to produce generic output. Prefer the direct API path (the helper scripts above), which accepts the full brief + proposal + prior critiques inline. That is functionally equivalent to file reading for this use case and gives much sharper critiques.

## Cost

Per round with the full four-critic roster:
- Claude general-purpose subagent: included in subscription
- Codex CLI: included in subscription
- Grok via xAI API: roughly $0.05
- Gemini via Google AI Studio API: roughly $0.05 (free tier often covers it)

Wall-clock: about 10 minutes if all four run cleanly. Allow up to 30 minutes for slow Codex runs. Grok and Gemini both return in under a minute and never gate completion.

Across a typical 3-4 round decision: roughly $0.20-$0.30 of paid-API cost, 30-60 minutes of total elapsed time spread across the session.
