---
name: critic-gauntlet
version: 2.5.1
description: Run an adversarial critic gauntlet on a proposal. Spawns a sandboxed Claude critic subagent plus optional Codex CLI, Grok (xAI API), Gemini (Google AI Studio API), and DeepSeek (any OpenAI-compatible endpoint) critics in parallel, surfaces raw critic outputs verbatim, then synthesizes. One harness, three rubric modes selected by a flag: architecture (ADR decisions), science (working-paper peer-review desk-screen), editorial (five-lens article review). On ARCHITECTURE decisions, run the `prior-art` skill FIRST and write the proposal against what it finds: the gauntlet judges whether a proposal is wrong, it has no way to tell you the field already solved this differently.
---

# Critic Gauntlet

For high-stakes work where the cost of being wrong is high. Forces independent adversarial critics against a target, surfaces raw output verbatim before synthesis, and iterates until convergence or specification-level findings emerge.

The value is cross-model disagreement: different model families share different blind spots, so a hole one misses another tends to catch. Convergence across independent models is a strong signal; a lone-critic finding is sometimes the most valuable thing in the round.

The harness is the same in every mode: parallel spawn, liveness gate, raw output verbatim, fresh-agent synthesis, convergence math. What changes per mode is only the rubric (the brief the critics answer) and a small amount of per-mode policy. Modes are selected by a `--mode` flag; see the Modes section.

## Roster

The full roster is five critics:

1. **Claude critic subagent** (baseline, always available, no API key, included with Claude Code). Spawn it least-privilege, never as `general-purpose`; see "The blast-radius rule".
2. **Codex CLI** (requires the `codex` CLI installed and authenticated)
3. **Grok via the xAI API** (requires `XAI_API_KEY`)
4. **Gemini via the Google AI Studio API** (requires `GEMINI_API_KEY`)
5. **DeepSeek via an OpenAI-compatible endpoint** (requires `DEEPSEEK_API_KEY`; US-hosted Fireworks by default, `DEEPSEEK_BASE_URL` switches to the PRC-hosted first-party API or a self-hosted vLLM)

Only critic 1 is required. The other three are bolt-ons you enable when you have the credentials. Running with just the Claude subagent is valid but weak: you lose the cross-model diversity that is the whole point. Two or three models arguing is materially better; four is the recommended bar for a decision you cannot cheaply reverse.

If you have all five configured, run all five by default. Drop a critic on a given round only when speed matters more than coverage. Grok, Gemini, and DeepSeek carry higher noise floors than Claude and Codex, so if you are trimming, drop from that tier first. A critic newly added to the roster is UNCALIBRATED (DeepSeek as of 2026-07): run it and read it, but it does not count toward binding thresholds until the promotion criteria in the synthesis section hold.

## Modes

Select the rubric with `--mode architecture|science|editorial` (default `architecture`). Each mode has a brief template in `modes/<mode>.brief-template.md` and an API-critic system prompt in `modes/<mode>.system.txt`. You author the per-run brief from the template; the helper scripts read the system prompt automatically.

| Mode | Use for | Rubric sections |
| --- | --- | --- |
| `architecture` | ADR-grade decisions: system shape, delivery mechanism, multi-tenancy model, new critical-path dependency, repo structure | boring baseline, blank-sheet design, three biggest holes, steel-manned 80% and 110% alternatives, unstated assumptions, consequences for ADR, recommendation |
| `science` | Working papers before submission (SSRN / Zenodo tier) | claim-vs-evidence, identification and confounds, method-question fit, data provenance and reproducibility, re-identification exposure, limitations honesty, recommendation |
| `editorial` | Published-grade articles before release | five lenses: journalistic discipline, defamation and regulatory risk, reader engagement, ai-slop-ness, CTA conversion; scored 0-10 with quoted evidence |

Posture is identical across modes: no sympathetic openers, lead with the strongest objection, no balanced view, every deduction cites the exact passage, no em-dashes or double-dashes.

Per-mode policy that differs from the architecture default:

- **science data-sovereignty.** The external API critics (Grok, Gemini, DeepSeek) are third-party vendors, and DeepSeek's default endpoint is additionally PRC-hosted (strictest tier; prefer a US-hosted endpoint or drop the critic when in doubt). In science mode they may read ONLY the anonymized paper and its stated public sources, NEVER the raw dataset or any file carrying subject identity. A properly anonymized paper is safe to send; the underlying data and any identity key are not. This is a policy about egress of identified data to outside APIs, not a ban on running multiple critics: an anonymized artifact runs the full roster. The brief template restates this rule in its header.
- **editorial calibration.** Model families differ in how readily they flag editorial risk; some run lenient on prose and strict on architecture, or the reverse. Do not assume a critic's architecture-mode temperament carries into editorial. Weight by which critics actually converge on quoted evidence. The API helper scripts run a two-call protocol in editorial mode: call 1 sees the article alone and returns the cold-read log, call 2 gets the brief and materials plus those notes, so the cold first pass is real rather than reconstructed.

## When to invoke

`--mode architecture` (default): system shape, delivery mechanism, multi-tenancy model, a new critical-path dependency, repo structure. Anything where the shape, once shipped, is expensive to change. Non-architectural changes (bug fixes, refactors, feature additions inside an existing shape) do NOT need this. The gauntlet is expensive in attention and time; do not run it on small decisions.

`--mode science`: before a working paper is submitted (SSRN / Zenodo tier), or when a paper's conclusions are load-bearing enough that a desk-reject would be costly. Not for early drafts still finding their claim.

`--mode editorial`: before releasing a flagship, litigious-tier, or template-defining article (the first specimen of a new format, a piece on a named subject that could prompt a legal response). Not per-issue: rerun on template changes or periodically. Your own publish gate stays the gate; this is a complementary layer.

## What you need before invoking

1. **The material under review** at a known file path, saved as `<work-folder>/proposal-v<N>.md`. For architecture that is the ADR proposal (status, context, proposal, what it trades, open questions). For science it is the anonymized paper (plus its sources, subject to the science data-sovereignty rule). For editorial it is the article draft plus its source material and house references.
2. **A work folder** to hold artifacts. Suggested convention: `<your-repo>/decisions/ADR-NNN-<topic>/` for architecture, `<your-repo>/critic-runs/<slug>/` for science and editorial. The brief, proposal, critiques, and synthesis all live together.
3. **Optional context files** the critics should read (an existing ARCHITECTURE.md, contributor/AI guidelines, voice/policy docs, prior critiques if this is round 2+), subject to per-mode policy (science withholds identified data from the external API critics).

## The flow

### Step 1: Probe the roster

Before doing anything else, determine which critics are available on this machine and announce the roster to the user.

```bash
# Probe each critic. Print "available" or "skipped: <reason>".
echo "Critic roster:"

# Claude (always available)
echo "  Claude gauntlet-critic subagent: available"

# Codex CLI
if command -v codex &>/dev/null; then
    echo "  Codex CLI: available"
else
    echo "  Codex CLI: skipped (codex not on PATH)"
fi

# Grok via xAI
if [ -n "${XAI_API_KEY:-}" ]; then
    echo "  Grok (xAI): available"
else
    echo "  Grok (xAI): skipped (XAI_API_KEY not set)"
fi

# Gemini via Google AI Studio
if [ -n "${GEMINI_API_KEY:-}" ]; then
    echo "  Gemini (Google AI Studio): available"
else
    echo "  Gemini (Google AI Studio): skipped (GEMINI_API_KEY not set)"
fi

# DeepSeek (endpoint configurable; default is US-hosted Fireworks)
if [ -n "${DEEPSEEK_API_KEY:-}" ]; then
    echo "  DeepSeek (${DEEPSEEK_BASE_URL:-https://api.fireworks.ai/inference/v1}): available"
else
    echo "  DeepSeek: skipped (DEEPSEEK_API_KEY not set)"
fi
```

If only Claude is available, warn the user that this is a degenerate run and ask whether to proceed. Otherwise proceed without prompting.

### Step 2: Write the brief

Pick the mode. Copy `modes/<mode>.brief-template.md` and fill in the placeholders (title, required reading, prior-round summary, and for editorial/science the product/paper context). Save the filled brief to `<work-folder>/brief-v<N>.md` where N is the round number.

Each mode's rubric sections are listed in the Modes table above. Do not hand-write the rubric; use the template. The API-critic system prompt for the mode is applied automatically by the helper scripts from `modes/<mode>.system.txt`; you do not paste it anywhere.

The shared posture in every brief: no sympathetic openers, lead with the strongest objection, no balanced view, every deduction cites the exact passage, no em-dashes or double-dashes, markdown, no closing pleasantry.

### Step 3: Spawn the critics in parallel

In a single message, fire all enabled critic tool calls.

All critics answer the same brief and follow ITS output format (which differs by mode: the architecture brief has 5 sections, science has 7, editorial has the five-lens format). Do not hardcode "5 sections" in any critic prompt; say "follow the brief's output format." The helper scripts take `--mode <mode>` and load the matching system prompt; the Claude subagent and Codex read the format from the brief itself.

**Critic 1: Claude critic subagent.** Use the Agent tool with `subagent_type: "gauntlet-critic"`. Tell the agent to read the brief, read the required files, follow the brief's output format, write its critique to `<work-folder>/critique-v<N>-claude.md`, and confirm with a one-line output. Run in background.

**Critic 2: Codex CLI.** Use Bash with `codex exec --sandbox read-only --skip-git-repo-check --cd <work-folder> "<inline prompt>"`. The prompt tells Codex to follow the brief's output format. Pipe `</dev/null` to close stdin (Codex hangs on stdin otherwise). Pipe stdout through `tail -30` to keep the bash output bounded. Run in background.

**Critic 3: Grok via the xAI API.** Use the helper script `grok-critic.sh <work-folder> <N> --mode <mode>` from this skill folder. It reads `XAI_API_KEY` from env (or a `.env` / shell rc fallback), loads the mode system prompt, concatenates brief + proposal + prior critiques, calls the xAI API, and writes `critique-v<N>-grok.md`. Run via Bash in background.

**Critic 4: Gemini via the Google AI Studio API.** Use the helper script `gemini-critic.sh <work-folder> <N> --mode <mode>` from this skill folder. Same shape as Grok. Reads `GEMINI_API_KEY`, loads the mode system prompt, calls the Google AI Studio API, writes `critique-v<N>-gemini.md`. Run via Bash in background. In science mode, confirm the proposal file handed to the external critics is the anonymized artifact only.

**Critic 5: DeepSeek via an OpenAI-compatible endpoint.** Use the helper script `deepseek-critic.sh <work-folder> <N> --mode <mode>` from this skill folder. Same shape as Grok; reads `DEEPSEEK_API_KEY`. The endpoint defaults to Fireworks (US-hosted, serving the MIT open weights; model id `accounts/fireworks/models/deepseek-v4-pro`). DeepSeek's first-party API is PRC-hosted; opt into it deliberately via `DEEPSEEK_BASE_URL=https://api.deepseek.com/v1` + `DEEPSEEK_MODEL=deepseek-v4-pro`, and never for material that must not egress to a PRC vendor. Self-hosted vLLM works the same way. The critique header records the serving endpoint. Writes `critique-v<N>-deepseek.md`. Run via Bash in background.

The helper scripts take the work folder path and the round number, plus an optional `--mode` (default architecture). Both auto-pick up prior-round critiques when N > 1.

### The blast-radius rule (read before Step 2, it is newer than the rest of this file)

**Every agent this skill spawns runs least-privilege: `Read, Grep, Glob, Write` and nothing else. Codex runs `--sandbox read-only`.**

This is a repair, not hygiene. On 2026-08-02, during round 1 of a real architecture decision, two critics were spawned the way this file used to say (the Claude critic as a full-tool `general-purpose` agent, Codex under `--sandbox workspace-write`). Between them they edited a project document neither was asked to touch, made two git commits authored as the user, pushed both to the shared main branch, and created five tickets in a live project-management board. Their briefs asked for a critique file and a one-line confirmation. Nothing else.

**The trap is that the work was good.** The tickets were well written and some were genuinely owed. That is exactly why prompt wording cannot be the control: a capable agent with a full toolbelt and rich context finds adjacent work and does it, and the better the agent, the more plausible the overreach looks. The reviewer then has to audit a diff they never asked for, in a repo they thought was quiet.

Three rules that bind:

1. **Never spawn a critic or synthesizer as `general-purpose`.** Define dedicated agents scoped to `Read, Grep, Glob, Write`: no shell, so they cannot run `git`, and no MCP tools, so they cannot write to any external service. If those definitions are missing, create them before running a round; do not substitute `general-purpose` "just this once".
2. **Never run Codex with `workspace-write`.** Under `--sandbox read-only` it cannot write its own critique, so the harness captures stdout and writes the file. That is the intended trade.
3. **Check the work folder's repo state after a round.** `git status` and `git log --oneline -5` before you commit anything of your own. A round that ends with unexpected commits is a skill bug, not an anomaly.

Residual hole, stated so nobody assumes it is closed: a critic still holds `Write`, which can create or overwrite a file at any path, because writing the critique is the job. This reduces blast radius; it does not prove containment. If your runtime supports path-scoped writes, scope them to the work folder.

### Step 4: Verify every critic returned a real critique (liveness gate)

Do not synthesize until every enabled critic has either produced a valid critique or been explicitly dropped by the user. A missing critic must never be silently absorbed: a degraded roster is a decision, not a default. The most common way a gauntlet quietly loses signal is a critic that erred without anyone noticing, and the synthesis treating three-of-an-intended-four as if four had agreed.

Typical timing: Claude subagent 2-3 min, Codex CLI 5-10 min, Grok and Gemini under a minute. DeepSeek is not yet timed; expect thinking-mode latency in minutes, not seconds.

**Success condition (same gate for all critics).** A critic passed only if ALL hold:
1. Its `critique-v<N>-<critic>.md` file exists and is at least ~500 bytes. Real critiques run 3 KB and up; anything smaller is a stub or error.
2. The file is the actual multi-section critique in the brief's format, not an error payload. Reject if it leads with `ERROR:` or contains raw API error JSON.
3. For the Bash critics (Codex, Grok, Gemini): the process exit code was 0. The helper scripts `set -euo pipefail` and exit non-zero on any missing-key / API / empty-response failure. Capture the last stderr line as the failure reason.
4. For the Claude subagent: the Agent tool returned success and the file was written. A subagent that erred without writing the file is a fail even if it returned some text.

**On any critic failing: retry once, then halt.**
1. Retry the failed critic exactly once. Transient infrastructure, rate-limit, and spawn errors usually clear on the second attempt.
2. If it fails the second time, STOP. Do not synthesize. Tell the user, in plain language: which critic is down, the captured failure reason, the role lost (roster below), the surviving roster, and the choice: proceed with the reduced roster / pause and fix / abort the round.
3. The default recommendation depends on WHICH critic died:
   - Lost an ANCHOR (Claude or Codex, the two low-noise models): default to PAUSE. The synthesis leans on anchor agreement; losing one materially degrades signal.
   - Lost a NOISE-FLOOR critic (Grok, Gemini, or DeepSeek): a reduced run is acceptable. Default to proceed; note the loss in the synthesis roster line.

**Billing note for the Claude critic.** The Claude critic runs as a Claude Code subagent on your existing subscription, not as a metered API call, and it requires no `ANTHROPIC_API_KEY`. Do not "fix" a Claude failure by setting one: in Claude Code, setting `ANTHROPIC_API_KEY` anywhere in the environment routes the entire app to API billing instead of your subscription. If the subagent fails, retry it (above); never reach for a key.

**Roster roles (so a loss is costed correctly):**
- Claude subagent: operational-nuance anchor, low noise, no API key.
- Codex CLI: specification-bug anchor, low noise.
- Grok: privacy / policy / jurisdictional angles. Higher noise.
- Gemini: catches blind spots shaped by Google's training distribution. Highest calibrated noise.
- DeepSeek: a training distribution and RLHF lineage unlike the other four; strong quantitative bent. UNCALIBRATED as of 2026-07: noise tier by default until proven.

Whatever the outcome, the synthesis roster line must name every critic that was attempted and its status (returned / dropped-after-2-fails / user-skipped), so the degraded-roster fact survives into the record.

### Step 5: Surface raw critic outputs verbatim

Read each critique file and present its content to the user verbatim. Do not summarize before the user has seen the raw text. A one-line preamble per critique is fine ("Claude returned. Recommends X."), but the actual critique content goes through verbatim. The point of independent critics is defeated if a synthesizer filters them before the human sees them.

### Step 5.5: Decision discipline (non-negotiable; this is where ADR-002 failed)

The critique stage is not the weak point of this gauntlet; synthesis is. The classic failure: critics unanimously reject an approach and converge on a simpler alternative, then the synthesis (written by the same agent that wrote the proposal) overrides all of them with one persuasive sentence and ships the exact architecture the gauntlet was run to prevent. These rules bind the synthesis so the producer can no longer grade the critics:

1. **Convergence BINDS the decision, not just the next iteration.** If critics converge against the proposed approach (5-of-5, 4-of-5, 4-of-4, 3-of-4, 3-of-3, or 2-of-3, counting calibrated critics only), you may NOT adopt the rejected approach in `decision.md`. The convergent alternative is the default outcome.
2. **Overriding convergence requires explicit escalation, never prose.** If you believe the converged critics are wrong, you may not bury the reversal in the synthesis or decision. Stop and put it to the user in plain words: "All N critics say X. I am proposing NOT-X. Here is exactly what I am asking you to overrule them on, and why." The user overrides consciously, or the convergent answer stands. A hypothetical objection ("it might not scale") is not grounds; only a demonstrated one is.
3. **The synthesizer is not the proposer (always, no exceptions).** The main session is anchored by the whole discussion, so it never writes the synthesis. Spawn a FRESH least-privilege agent (Agent tool, `subagent_type: "gauntlet-synthesizer"`, `model: "haiku"`, a deliberately small model so the judge cannot out-clever the critics) and hand it the fixed synthesis-agent prompt (see "Synthesis agent invocation" below) verbatim. Do not author findings for it or summarize the critiques for it; it reads the raw critiques and the proposal from files itself. Then surface its `synthesis-v<N>.md` to the user VERBATIM, the same rule as the raw critiques, so the proposer cannot spin the verdict on relay. The thing with ego in the proposal neither writes the synthesis nor narrates it.
4. **Boring-baseline must be answered in the synthesis.** Restate the most standard, right-fit way to do this for the job (reuse, a recomposition of existing parts, or one small standard new service, whichever actually fits; reusing a wrong-fit existing tool is NOT the boring baseline). State why the chosen design is not just that. If "why not the boring way" has no demonstrated answer, the boring way wins.
5. **Proof-of-life before "decided."** No `decision.md` is accepted until one real end-to-end slice runs on real infrastructure. A decision on paper is a hypothesis.

### Step 6: Synthesize to `<decisions-folder>/synthesis-v<N>.md`

The synthesis identifies:

- **All-critic convergence (5-of-5, 4-of-4, or 3-of-3, per roster size).** Strongest possible signal. Binding for the next iteration AND for the final decision (Step 5.5): you may not ship an architecture the critics converged against without explicit user override.
- **Majority convergence.** Strong signal. Worth incorporating.
- **Split convergence.** Evaluate by which critics converged. The two lowest-noise models agreeing (Claude + Codex) is high signal. The two noisier models agreeing (Grok + Gemini) should be treated as one combined noisy vote: verify the finding before incorporating. A mixed pair is case-by-case.
- **Uncalibrated critics.** A critic new to the roster (DeepSeek as of 2026-07) does NOT count toward binding thresholds until ALL THREE promotion criteria hold: (1) it has run in at least two different modes; (2) at least one round where it disagreed with part of the calibrated panel and the disagreement did not resolve against it (agreeing with an overwhelming consensus is not calibration evidence; a derivative critic produces the same result); (3) no invented-findings pattern on material that was fundamentally sound. Promotion is a fact about observed behavior, not a round count. Until then: bind on the calibrated critics' counts; treat the uncalibrated critic's agreement as corroboration and its lone novel findings as leads to verify. Log each round's calibration observation.
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

Per round, in the work folder:
- `brief-v<N>.md` (authored from `modes/<mode>.brief-template.md`)
- `critique-v<N>-claude.md`
- `critique-v<N>-codex.md`
- `critique-v<N>-grok.md`
- `critique-v<N>-gemini.md` (when Gemini is enabled for the round)
- `critique-v<N>-deepseek.md` (when DeepSeek is enabled for the round)
- `synthesis-v<N>.md`

After acceptance:
- `decision.md` (architecture) / accepted paper or article (science, editorial)
- Updated `ARCHITECTURE.md` if relevant

## Files this skill ships (in the skill folder, do not delete)

- `SKILL.md` (this file, the harness)
- `grok-critic.sh`, `gemini-critic.sh`, `deepseek-critic.sh` (mode-agnostic critic scripts; take `--mode`)
- `modes/architecture.system.txt` + `modes/architecture.brief-template.md`
- `modes/science.system.txt` + `modes/science.brief-template.md`
- `modes/editorial.system.txt` + `modes/editorial.brief-template.md`

## Worked example

A four-round run on a real decision (renderer delivery mechanism) is reproduced in `examples/worked-example.md`. It shows how findings shift from architecture to specification across rounds, which is the signal that the gauntlet has done its job and can stop. Read it to calibrate what "good" convergence looks like.

## Critic invocation reference

### Claude critic subagent prompt template (`subagent_type: "gauntlet-critic"`)

```
You are an adversarial architecture critic for <ADR-title> round <N>.

STEP 1: Read /path/to/brief-v<N>.md in full.

STEP 2: Read required files in the order specified.

STEP 3: Write your critique to /path/to/critique-v<N>-claude.md with this header:

# Critique v<N>: Claude (gauntlet-critic subagent) <date>

Model: Claude via gauntlet-critic subagent type, adversarial brief.
Brief location: brief-v<N>.md in this folder.

---

Then follow the brief's output format exactly.

STEP 4: After writing, output ONE LINE: 'Critique written to <path>, N words, recommendation: <the brief's recommendation vocabulary>'

POSTURE:
- Adversarial. Find what is wrong.
- Read prior critiques if any (in same folder) to calibrate rigor.
- No em-dashes or double-dashes. Use periods, commas, colons.
- Lead with the strongest objection, no sympathetic opener.
```

### Synthesis agent invocation

The synthesis is written by a FRESH least-privilege synthesizer agent, never the main (proposer) session (Step 5.5 rule 3). Spawn it with the Agent tool, `subagent_type: "gauntlet-synthesizer"`, `model: "haiku"` (a deliberately small model: the synthesis job is near-mechanical, and a less-clever judge cannot rationalize past the critics), and pass this prompt verbatim. Do not summarize the critiques for it; it reads them itself. Surface its output to the user verbatim.

The prompt below is written for architecture mode. For science and editorial, keep the convergence logic and neutral-judge posture unchanged, but swap the recommendation vocabulary (science: minor / major revisions / reject-rescope; editorial: publish / blocker-edits / hold) and drop the boring-baseline and blank-sheet bullets, which are architecture-only.

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
codex exec --sandbox read-only --skip-git-repo-check --cd <work-folder> "<same prompt template, but: print the critique to STDOUT, write no files>" </dev/null > <work-folder>/critique-v<N>-codex.raw 2>&1
```

Important: `</dev/null` is required. Without it, `codex exec` waits on stdin and hangs indefinitely.

### Grok invocation

```bash
./grok-critic.sh <work-folder> <round-number> [--mode architecture|science|editorial]
```

Reads `brief-v<N>.md` and `proposal-v<N>.md`, loads the mode system prompt from `modes/<mode>.system.txt` (default architecture), builds the prompt, calls the xAI API, writes `critique-v<N>-grok.md`. Requires `XAI_API_KEY`. The model is pinned at the top of the script (override per run with `GROK_MODEL=...`).

### Gemini invocation

```bash
./gemini-critic.sh <work-folder> <round-number> [--mode architecture|science|editorial]
```

Same shape as Grok. Requires `GEMINI_API_KEY`. The model is pinned at the top of the script (override per run with `GEMINI_MODEL=...`). Free tier covers normal usage; paid tier is sub-penny per critique.

### DeepSeek invocation

```bash
./deepseek-critic.sh <work-folder> <round-number> [--mode architecture|science|editorial]
```

Same shape as Grok. Requires `DEEPSEEK_API_KEY`. The model is pinned at the top of the script (override with `DEEPSEEK_MODEL=...`); the endpoint is `DEEPSEEK_BASE_URL` (default: Fireworks, US-hosted; any OpenAI-compatible host works, including the PRC-hosted first-party API and a self-hosted vLLM). The critique header records the serving endpoint.

## Models to skip

**Single-shot MCP wrappers** (e.g. a `chatgpt_query` or `gemini_query` MCP tool) without agentic file reading tend to produce generic output. Prefer the direct API path (the helper scripts above), which accepts the full brief + proposal + prior critiques inline. That is functionally equivalent to file reading for this use case and gives much sharper critiques.

## Cost

Per round with the full five-critic roster:
- Claude gauntlet-critic subagent: included in subscription
- Codex CLI: included in subscription
- Grok via xAI API: roughly $0.05
- Gemini via Google AI Studio API: roughly $0.05 (free tier often covers it)
- DeepSeek via Fireworks (US-hosted): a few cents (the PRC-hosted first-party API is ~$0.01 if deliberately opted into)

Wall-clock: about 10 minutes if all four run cleanly. Allow up to 30 minutes for slow Codex runs. Grok and Gemini both return in under a minute and never gate completion.

Across a typical 3-4 round decision: roughly $0.20-$0.30 of paid-API cost, 30-60 minutes of total elapsed time spread across the session.
