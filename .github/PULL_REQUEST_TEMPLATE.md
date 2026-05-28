<!--
SPDX-License-Identifier: Apache-2.0
Copyright 2026 CAP Authors
-->

## Summary

One-paragraph summary of the change.

## Type of change

- [ ] Doc / typo fix
- [ ] Proto schema addition (backwards-compatible)
- [ ] Proto schema breaking change (requires RFC + new `cap.vN` package)
- [ ] ADR / RFC
- [ ] Tooling / build / CI
- [ ] Domain Pack proposal (use the
      [Domain Pack template](../rfcs/domain-pack-template.md))

## RFC reference

If this PR implements an RFC, link it: `rfcs/RFC-NNNN-*.md`.

## Checklist

- [ ] I have signed off all commits (`git commit -s`); see
      [CONTRIBUTING.md](../CONTRIBUTING.md) on DCO.
- [ ] `make lint` passes (`buf lint`).
- [ ] `make gen` produces the expected output; `git diff gen/` is empty
      after regeneration.
- [ ] `make breaking` does not report unintended wire-format changes.
- [ ] Conformance tests updated (if behavior changes).
- [ ] TLA+ models updated (if state machine changes); `make verify` passes.
- [ ] SPDX-License-Identifier header present on new files
      (`reuse lint` passes).
- [ ] CHANGELOG.md updated under `[Unreleased]`.

## Notes for reviewers

Anything specific you want reviewers to focus on.
