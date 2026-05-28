---
name: Feature request
about: Suggest an addition or improvement to the specification
title: "[FEATURE] "
labels: enhancement, triage
assignees: ''
---

<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 CAP Authors -->

## Motivation

What problem does this address? Who is affected?

## Proposed change

What should be added / changed?

- New message type / field?
- New state machine transition?
- New conformance test?
- New Domain Pack? — if yes, please use the
  [Domain Pack proposal template](../../rfcs/domain-pack-template.md) instead.

## Alternatives considered

What other approaches did you consider? Why are they less suitable?

## Wire / API impact

- Does this require a new `cap.vN` proto package? (See ADR-008.)
- Backwards compatibility implications?
- Conformance Level affected?

## Need for an RFC?

Substantial changes (new messages, state machines, breaking changes, new
Domain Pack) require an RFC — see [rfcs/README.md](../../rfcs/README.md).
For small additive changes, this issue alone is sufficient.
