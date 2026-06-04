# Worked example: a four-round gauntlet

This is an anonymized record of a real decision run through the gauntlet: how to deliver a server-rendered report from a background worker. It ran for four rounds with three to four critics per round. The point of reproducing it is not the specific architecture. It is the shape of the convergence, and the moment it became safe to stop.

Read the round-by-round convergence below. Notice that the findings start as arguments about the shape of the system ("this whole approach is wrong") and end as arguments about precision ("the shape is right, but five things are underspecified"). That shift is the stop signal.

## Round 1: critics converged on

- Tenant/brand isolation matters and the proposal underweights it.
- A build-time dependency on an external Git host is worse than the same dependency at delivery time.
- Rendering in-process from the worker's language was claimed easy and is not.
- There is no rollback story.

## Round 2: critics converged on

- Pre-render the artifact to object storage at generation time, rather than rendering on request. Two strong critics independently recommended this.

## Round 3: critics converged on

- Run the renderer as a sidecar, not embedded. (All critics.)
- Vendoring the templates repeats the earlier hazard. (All critics.)
- The forward-only schema story is internally inconsistent. (All critics.)
- Cold start must be measured, not assumed. (All critics.)
- Embed provenance in the rendered output. (All critics.)
- Ship the design system as a versioned package. (Majority.)
- Use versioned, immutable artifact keys. (Majority.)
- Add an asset-closure CI gate. (Majority.)

## Round 4: critics converged on

- The storage publication transaction needs an explicit state machine.
- Multi-runtime container supervision is underspecified.
- The hand-maintained schema adapter is a drift risk.
- The renderer's data path is internally contradictory in one place.
- The content hash is self-referential.

Every round-4 finding is a specification gap, not an architecture objection. The shape had stopped moving. That is where the gauntlet stopped.

## What it cost and what it bought

Each round took roughly 30 minutes of compute, about 2 hours total across four rounds. The four proposals were materially different architectures, not vocabulary refreshes of one idea. Round 1's proposal and round 4's proposal would have produced different systems with different failure modes.

The lesson: the gauntlet is worth the time on a decision you cannot cheaply reverse, and it tells you when to stop on its own. When the critics stop arguing about the shape and start arguing about the spec, you are done iterating and can amend in place.
