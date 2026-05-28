<!--
SPDX-License-Identifier: Apache-2.0
Copyright 2026 CAP Authors
-->

# Postmortem: `<short title>`

| Field | Value |
|---|---|
| Date of incident | YYYY-MM-DD HH:MM JST |
| Affected component | (cap-spec / cap-sdk-* / cap-conformance / Domain Pack) |
| Affected version | v0.x.y |
| Detected by | (alerting / community report / CI / maintainer) |
| Severity | (S1 / S2 / S3 / S4) |
| Duration | (time-to-detect → time-to-mitigate → time-to-resolve) |
| Authors | (maintainer names / handles) |
| Status | Draft / Under review / Published |

> **Reminder**: this template is for **published postmortems**. Sanitize
> all customer / OEM identifiers before public release. Internal-only
> postmortems may include identifiers but should not be linked from
> public-facing documents.

## Summary

One paragraph: what happened, who was affected, how it was resolved.

## Impact

- Who was affected (downstream packages, conformance claimants,
  external implementations)
- Functional impact (broken workflows, data inconsistencies)
- Visibility (silently broken vs loud failure)

## Timeline

| Time (JST) | Event |
|---|---|
| HH:MM | Change merged |
| HH:MM | First report |
| HH:MM | Investigation started |
| HH:MM | Mitigation deployed |
| HH:MM | Root cause confirmed |
| HH:MM | Full resolution |

## Root cause

What technical cause produced the incident. Be specific — file path,
commit SHA, configuration value. If multiple causes contributed, list
them all.

## Detection

How did we learn about this? What would have detected it earlier?

## Resolution

What did we do to mitigate? What did we do to fully resolve?

## What went well

- (action items that worked as intended)

## What went wrong

- (gaps in detection / response / tooling)

## Action items

| Action | Owner | Due | Tracking |
|---|---|---|---|
| (e.g., add CI check for X) | @handle | YYYY-MM-DD | #issue-N |

## References

- Pull request that introduced the issue:
- Pull request that resolved it:
- Related issues / discussions:
- Related ADRs / RFCs:
