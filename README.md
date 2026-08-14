# Critic Gauntlet

A Claude Code skill that pits five AI models against your work as adversarial critics, surfaces their raw objections to you unfiltered, and synthesizes where they agree. For decisions and documents you cannot cheaply reverse.

One harness, three rubric modes: **architecture** (ADR-grade design decisions, the default), **science** (working-paper desk-screen before submission), and **editorial** (five-lens review of published-grade articles). The critics, the parallel spawn, the liveness gate, and the synthesis rules are identical in every mode; only the rubric the critics answer changes.

## The problem it solves

When you ask one model to review your design, you get one model's blind spots baked into the answer. It is also, by default, agreeable: it will help you improve the thing rather than tell you the thing is wrong. Both failures are silent. You ship, and six months later you discover the hole the model never raised because its training distribution shared your blind spot, or because it was busy being supportive.

The gauntlet fixes both:

1. **Adversarial framing.** Every critic is instructed to find what is wrong, lead with the strongest objection, and refuse sympathetic openers. No "great proposal." It steel-mans a simpler alternative and a more rigorous one, lists the unstated assumptions, and names what the team will regret in six months.
2. **Cross-model diversity.** Five different model families critique in parallel: Claude, OpenAI's Codex, xAI's Grok, Google's Gemini, and DeepSeek. Different families share different blind spots, so a hole one misses, another tends to catch. When independent models converge on the same objection, that is a strong signal. When one lone model catches something the others missed, that is often the most valuable finding in the round.
3. **Raw output, then synthesis.** You see every critic's verbatim output before anything summarizes it. The synthesizer cannot quietly drop a finding it disagrees with, because you have already read the original.

## How it works

You write a short proposal (for architecture: status, context, what you propose, what it trades, open questions; for science: the anonymized paper; for editorial: the article draft) and drop it in a work folder. The skill:

1. Writes an adversarial brief from the mode's template (`modes/<mode>.brief-template.md`) that tells the critics exactly what to attack and in what format.
2. Spawns all enabled critics in parallel, each reading the brief and proposal independently. The helper scripts take `--mode architecture|science|editorial` and load the matching system prompt automatically.
3. Enforces a liveness gate: every enabled critic either returns a real critique or is explicitly dropped by you. A failed critic is retried once, then the run halts and asks. A partial roster must never be silently synthesized as if the full roster had agreed.
4. Shows you each critique verbatim.
5. Synthesizes via a fresh agent: what all critics agreed on (binding), what a majority agreed on (strong), what split, and what a single critic uniquely caught.
6. You decide: run another round against a revised proposal, or accept and write the decision record.

You iterate until the findings shift from architecture ("the shape is wrong") to specification ("the shape is right, but it is imprecise here, here, and here"). That shift is the signal to stop. See [the worked example](skills/critic-gauntlet/examples/worked-example.md) for a real four-round run.

## What each critic returns

Every critic answers the mode's rubric in the same structure, which is what forces rigor instead of agreeable mush. In architecture mode:

1. **The boring baseline and the blank-sheet design.** The most standard, right-fit way to do the job, and what a from-scratch design with no sunk cost would look like. If the proposal cannot beat the boring baseline on a demonstrated benefit, the boring baseline wins.
2. **Three biggest holes.** Specific failure modes or real costs, not vague concerns. The cap at three forces prioritization.
3. **Steel-manned alternatives.** An 80% version (simpler, most of the value, less work) and a 110% version (more rigorous, what you are dismissing). Demanding both directions blocks the lazy "just do less" or "just do more" critique.
4. **Unstated assumptions** (at least four), each with why it might be wrong.
5. **Consequences for the ADR.** What the team regrets in six months if this ships as-is.
6. **Recommendation.** Ship as-is, ship with named amendments, or kill and reformulate, plus a confidence level. Forces a verdict, not a hedge.

Science mode swaps in a peer-review desk-screen rubric (claim-vs-evidence, identification and confounds, method-question fit, data provenance, re-identification exposure, limitations honesty). Editorial mode scores five lenses 0-10 with quoted evidence (journalistic discipline, defamation and regulatory risk, reader engagement, AI-slop-ness, CTA conversion).

The shared structure is also why convergence is meaningful: when five models independently fill the same slots, you can see exactly where they agree and where one caught something the others missed.

## Decision discipline

The critique stage is not the weak point of a gauntlet; synthesis is. The classic failure: critics unanimously reject an approach, then the same agent that wrote the proposal writes the synthesis and overrides all of them with one persuasive sentence. The skill binds the synthesis so the producer can no longer grade the critics:

- **Convergence binds.** If the critics converge against the proposed approach, that approach may not ship. Overriding convergence requires an explicit, plain-words escalation to the human, never a buried sentence in a synthesis.
- **The synthesizer is not the proposer.** A fresh agent on a deliberately small model writes the synthesis from the raw critique files, and its output is surfaced verbatim. The thing with ego in the proposal neither writes the verdict nor narrates it.
- **Proof-of-life before "decided."** No decision record is accepted until one real end-to-end slice runs on real infrastructure. A decision on paper is a hypothesis.

## The roster

| Critic | Requires | Notes |
| --- | --- | --- |
| Claude general-purpose subagent | Claude Code only | Baseline. Always available, no API key. Low noise. |
| Codex CLI | `codex` CLI installed + authed | Tends to catch specification bugs. Low noise. |
| Grok | `XAI_API_KEY` | Tends to catch privacy / policy / jurisdictional angles. |
| Gemini | `GEMINI_API_KEY` | Different training distribution, catches a different class of issue. |
| DeepSeek | `DEEPSEEK_API_KEY` | A training distribution and RLHF lineage unlike the other four. Newest seat: uncalibrated, so it corroborates but does not count toward binding convergence until proven over several rounds. |

**Only the Claude subagent is required.** The other four are optional bolt-ons. But the entire value proposition is models disagreeing, so the more you can enable, the better the result. One critic is a code review. Several critics arguing is the gauntlet. If you can only run two or three, you still get most of the benefit; if you can run the full roster on a decision that matters, do.

## Install

Pick either path.

**As a plugin (recommended).** Inside Claude Code:

```
/plugin marketplace add alexmakarski/critic-gauntlet
/plugin install critic-gauntlet@critic-gauntlet
```

It is also listed in the combined marketplace at [alexmakarski/claude-plugins](https://github.com/alexmakarski/claude-plugins) alongside the other tools, if you would rather add one marketplace and get everything.

**Manual.** Clone and copy the skill folder into your skills directory:

```bash
git clone https://github.com/alexmakarski/critic-gauntlet.git
cp -R critic-gauntlet/skills/critic-gauntlet ~/.claude/skills/critic-gauntlet
chmod +x ~/.claude/skills/critic-gauntlet/*.sh
```

Or run the installer from the cloned folder: `./install-critic-gauntlet.sh`.

Either way it is available to Claude Code as the `critic-gauntlet` skill.

## Setup

The baseline (Claude subagent only) needs nothing. To enable the optional critics:

**Codex CLI:** install and authenticate the [`codex` CLI](https://github.com/openai/codex). The skill calls `codex exec`.

**Grok:** get an [xAI API key](https://x.ai/api) and set it:

```bash
export XAI_API_KEY=your-key
```

**Gemini:** get a [Google AI Studio API key](https://ai.google.dev/) and set it:

```bash
export GEMINI_API_KEY=your-key
```

**DeepSeek:** get a [Fireworks API key](https://fireworks.ai) (the default endpoint) or a first-party key at platform.deepseek.com, and set it:

```bash
export DEEPSEEK_API_KEY=your-key
```

Data-sovereignty note: the default endpoint is Fireworks, a US host serving the MIT open weights, so the forgot-to-configure failure mode is an error, not silent egress. DeepSeek's first-party API is PRC-hosted (prompt data stored in the PRC); opt into it with `DEEPSEEK_BASE_URL=https://api.deepseek.com/v1` and `DEEPSEEK_MODEL=deepseek-v4-pro`. Any OpenAI-compatible endpoint works, including self-hosted vLLM, and each critique records which endpoint produced it.

The helper scripts resolve keys from the environment first, then from a `.env` file in the skill folder or your home directory, then from common shell rc files (`.zshrc`, `.bashrc`, `.bash_profile`, `.profile`). The exported-env path is the most reliable. See [.env.example](skills/critic-gauntlet/.env.example).

Other dependencies the scripts assume: `bash`, `curl`, and [`jq`](https://jqlang.github.io/jq/).

## Model pins

The Grok, Gemini, and DeepSeek scripts pin a specific model at the top of each file. Models move fast and these pins go stale; update them when a provider ships a newer flagship. You can also override per run without editing the file:

```bash
GROK_MODEL=grok-5 ./grok-critic.sh /path/to/decisions 1
GEMINI_MODEL=gemini-3.5-pro ./gemini-critic.sh /path/to/decisions 1
```

Pins verified current as of 2026-08-14: `grok-4.6` (4.6 shipped 2026-08-12; confirmed in /v1/models), `gemini-3.1-pro-preview` (Gemini 3.5 shipped as Flash only; 3.1 Pro remains the reasoning tier), `accounts/fireworks/models/deepseek-v4-pro` (Fireworks' id for V4-Pro; on the first-party API use `deepseek-v4-pro`, and note the legacy deepseek-chat / deepseek-reasoner slugs retire 2026-07-24). The Claude and Codex critics carry no pin: they run on whatever your Claude Code session and `codex` CLI default to, so they update themselves.

## When to use it, and when not to

**Use `--mode architecture` (default) for** architectural decisions: system shape, delivery mechanism, multi-tenancy model, a new critical-path dependency, repo structure. Anything expensive to change once shipped.

**Use `--mode science` for** working papers before submission, when a desk-reject would be costly. Note the data-sovereignty rule: the external API critics read only the anonymized paper, never raw data or anything carrying subject identity.

**Use `--mode editorial` for** flagship, litigious-tier, or template-defining articles before release. Not per-issue: rerun on template changes or periodically.

**Do not use it for** bug fixes, refactors, or features that live inside an existing shape, or drafts still finding their claim. The gauntlet costs real attention and 30-60 minutes of elapsed time per decision. Spending that on a small choice is waste.

## Cost

Per round with the full roster: the API critics run roughly $0.05 each (Gemini's free tier often covers it); Claude and Codex are included in their subscriptions. A typical 3-4 round decision costs $0.20-$0.30 in API spend and 30-60 minutes spread across a session.

## License

MIT. See [LICENSE](LICENSE).
