---
name: critic-gauntlet
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

### Step 1: Write the adversarial brief

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

### Step 2: Spawn the critics in parallel

In a single message, fire all enabled critic tool calls.

**Critic 1: Claude general-purpose subagent.** Use the Agent tool with `subagent_type: "general-purpose"`. Tell the agent to read the brief, read the required files, write its critique to `<decisions-folder>/critique-v<N>-claude.md`, and confirm with a one-line output. Run in background.

**Critic 2: Codex CLI.** Use Bash with `codex exec --sandbox workspace-write --skip-git-repo-check --cd <decisions-folder> "<inline prompt>"`. The prompt mirrors the Claude one. Pipe `</dev/null` to close stdin (Codex hangs on stdin otherwise). Pipe stdout through `tail -30` to keep the bash output bounded. Run in background.

**Critic 3: Grok via the xAI API.** Use the helper script `grok-critic.sh` from this skill folder. It reads `XAI_API_KEY` from env (or a `.env` / shell rc fallback), concatenates brief + proposal + prior critiques, calls the xAI API, and writes `critique-v<N>-grok.md`. Run via Bash in background.

**Critic 4: Gemini via the Google AI Studio API.** Use the helper script `gemini-critic.sh` from this skill folder. Same shape as Grok. Reads `GEMINI_API_KEY`, calls the Google AI Studio API, writes `critique-v<N>-gemini.md`. Run via Bash in background.

The helper scripts take two arguments: the decisions folder path and the round number. Both auto-pick up prior-round critiques when N > 1.

### Step 3: Wait for all enabled critics to complete

Each critic notifies on completion. The Claude subagent typically takes 2-3 minutes. Codex CLI 5-10 minutes. Grok and Gemini both return in under a minute and never gate completion.

Do not synthesize until all enabled critics return.

### Step 4: Surface raw critic outputs verbatim

Read each critique file and present its content to the user verbatim. Do not summarize before the user has seen the raw text. A one-line preamble per critique is fine ("Claude returned. Recommends X."), but the actual critique content goes through verbatim. The point of independent critics is defeated if a synthesizer filters them before the human sees them.

### Step 5: Synthesize to `<decisions-folder>/synthesis-v<N>.md`

The synthesis identifies:

- **All-critic convergence.** Strongest possible signal. Treat as binding for the next iteration.
- **Majority convergence.** Strong signal. Worth incorporating.
- **Split convergence.** Evaluate by which critics converged. The two lowest-noise models agreeing (Claude + Codex) is high signal. The two noisier models agreeing (Grok + Gemini) should be treated as one combined noisy vote: verify the finding before incorporating. A mixed pair is case-by-case.
- **Single-critic novel findings.** Sometimes the most valuable. Codex tends to catch specification bugs others miss. Claude tends to catch operational nuance. Grok tends to catch privacy/policy/jurisdictional angles. Gemini catches things shaped by a different training distribution.
- **Recommendation split.** Models differ systematically in how readily they recommend killing vs. amending. Track each critic's calibration over several decisions. Do not over-weight any single critic's kill recommendation when the majority amends.

Then surface the decision question to the user. Two paths:
- **Path A: another round.** Write proposal-v<N+1> incorporating the convergent amendments, run the gauntlet again.
- **Path B: amend in place.** Write `decision.md` (the actual ADR) with the convergent amendments as load-bearing fixes and the lone-critic novel findings as documented limitations.

The bar for stopping: the pattern of findings has shifted from architecture ("the shape is wrong") to specification ("the shape is right, but the spec is imprecise in N places"). Architecture findings require iteration. Specification findings can be amended in place.

### Step 6: After the user picks a path

If Path A: draft proposal-v<N+1>, repeat from Step 1.
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
