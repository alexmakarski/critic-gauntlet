# Critic Gauntlet

A Claude Code skill that pits four AI models against your architectural proposal as adversarial critics, surfaces their raw objections to you unfiltered, and synthesizes where they agree. For decisions you cannot cheaply reverse.

## The problem it solves

When you ask one model to review your design, you get one model's blind spots baked into the answer. It is also, by default, agreeable: it will help you improve the thing rather than tell you the thing is wrong. Both failures are silent. You ship, and six months later you discover the hole the model never raised because its training distribution shared your blind spot, or because it was busy being supportive.

The gauntlet fixes both:

1. **Adversarial framing.** Every critic is instructed to find what is wrong, lead with the strongest objection, and refuse sympathetic openers. No "great proposal." It steel-mans a simpler alternative and a more rigorous one, lists the unstated assumptions, and names what the team will regret in six months.
2. **Cross-model diversity.** Four different model families critique in parallel: Claude, OpenAI's Codex, xAI's Grok, and Google's Gemini. Different families share different blind spots, so a hole one misses, another tends to catch. When independent models converge on the same objection, that is a strong signal. When one lone model catches something the others missed, that is often the most valuable finding in the round.
3. **Raw output, then synthesis.** You see every critic's verbatim output before anything summarizes it. The synthesizer cannot quietly drop a finding it disagrees with, because you have already read the original.

## How it works

You write a short proposal (status, context, what you propose, what it trades, open questions) and drop it in a decisions folder. The skill:

1. Writes an adversarial brief that tells the critics exactly what to attack and in what format.
2. Spawns all enabled critics in parallel, each reading the brief and proposal independently.
3. Waits for all of them, then shows you each critique verbatim.
4. Synthesizes: what all critics agreed on (binding), what a majority agreed on (strong), what split, and what a single critic uniquely caught.
5. You decide: run another round against a revised proposal, or accept and write the decision record.

You iterate until the findings shift from architecture ("the shape is wrong") to specification ("the shape is right, but it is imprecise here, here, and here"). That shift is the signal to stop. See [examples/worked-example.md](examples/worked-example.md) for a real four-round run.

## The roster

| Critic | Requires | Notes |
| --- | --- | --- |
| Claude general-purpose subagent | Claude Code only | Baseline. Always available, no API key. |
| Codex CLI | `codex` CLI installed + authed | Tends to catch specification bugs. |
| Grok | `XAI_API_KEY` | Tends to catch privacy / policy / jurisdictional angles. |
| Gemini | `GEMINI_API_KEY` | Different training distribution, catches a different class of issue. |

**Only the Claude subagent is required.** The other three are optional bolt-ons. But the entire value proposition is models disagreeing, so the more you can enable, the better the result. One critic is a code review. Four critics arguing is the gauntlet. If you can only run two or three, you still get most of the benefit; if you can run all four on a decision that matters, do.

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

The helper scripts resolve keys from the environment first, then from a `.env` file in the skill folder or your home directory, then from common shell rc files (`.zshrc`, `.bashrc`, `.bash_profile`, `.profile`). The exported-env path is the most reliable. See [.env.example](skills/critic-gauntlet/.env.example).

Other dependencies the scripts assume: `bash`, `curl`, and [`jq`](https://jqlang.github.io/jq/).

## Model pins

The Grok and Gemini scripts pin a specific model at the top of each file. Models move fast and these pins go stale; update them when a provider ships a newer flagship. You can also override per run without editing the file:

```bash
GROK_MODEL=grok-4.4 ./grok-critic.sh /path/to/decisions 1
GEMINI_MODEL=gemini-3.5-pro ./gemini-critic.sh /path/to/decisions 1
```

Pins verified current as of 2026-06-03: `grok-4.3`, `gemini-3.1-pro-preview`.

## When to use it, and when not to

**Use it for** architectural decisions: system shape, delivery mechanism, multi-tenancy model, a new critical-path dependency, repo structure. Anything expensive to change once shipped.

**Do not use it for** bug fixes, refactors, or features that live inside an existing shape. The gauntlet costs real attention and 30-60 minutes of elapsed time per decision. Spending that on a small choice is waste.

## Cost

Per round with all four critics: the two API critics run roughly $0.05 each (Gemini's free tier often covers it); Claude and Codex are included in their subscriptions. A typical 3-4 round decision costs $0.20-$0.30 in API spend and 30-60 minutes spread across a session.

## License

MIT. See [LICENSE](LICENSE).
