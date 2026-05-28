<!--
SPDX-License-Identifier: Apache-2.0
Copyright 2026 CAP Authors
-->

# Security Policy — CAP (Cooperative Agent Protocol)

## Supported versions

CAP is currently in pre-1.0 development. Security fixes will be applied to the
**latest minor release** of each repository in the `cap-protocol` GitHub org:

| Repo | Supported versions |
|---|---|
| `cap-spec` | Latest minor (currently `v0.x`) |
| `cap-conformance` | Latest minor |
| `cap-sdk-python` | Latest minor of Core + active Domain Packs |
| `cap-sdk-cpp` | Latest minor of Core + active Domain Packs |
| `cap-agent-python` | Latest minor |

Once CAP reaches v1.0, the policy will be updated to cover at least the
current major and the immediately previous major.

## Reporting a vulnerability

**Please do not report security vulnerabilities through public GitHub issues,
public Discussions, or any public channel.**

### Preferred reporting channel — GitHub Private Vulnerability Reporting

For repositories under the `cap-protocol` GitHub org, please use GitHub's
**Private Vulnerability Reporting** feature:

1. Navigate to the affected repository on GitHub.
2. Click **Security** in the top tab.
3. Click **Report a vulnerability**.
4. Fill in the form with as much detail as possible (see below).

This creates a private channel between you and the CAP maintainers without
disclosing the issue publicly.

### Email channel — if GitHub access is unavailable

If you cannot use GitHub Private Vulnerability Reporting (for example, you
prefer end-to-end encrypted communication), please email:

- `security@cap-protocol.example` *(placeholder — will be set once the
  domain / org email is provisioned)*

PGP key for encrypted reporting: *(placeholder — will be published as a
detached signature in this repo at `SECURITY-PGP.asc` once the security
contact email is finalized)*.

### What to include in a report

To help triage quickly:

- **Reproduction**: minimal reproducible example (proto messages, transport,
  configuration). A wireshark / tshark capture of the offending CapFrame is
  ideal.
- **Impact**: which CAP layer (Site Agent, Machine Agent, Safety Supervisor,
  transport, etc.) is affected, and what an attacker can achieve.
- **Affected versions**: which `cap-spec` / SDK / conformance versions you
  have tested.
- **Suggested mitigation**: optional, but helpful if you have one.
- **Disclosure preference**: whether you want public credit for the report
  and your preferred name / handle.

## Disclosure timeline

CAP follows a **90-day embargo** consistent with Google Project Zero / GitHub
Security Advisories. The standard timeline:

| Day | Step |
|---|---|
| 0 | Report received and acknowledged within 72 hours. |
| 0-14 | Maintainers triage, confirm reproducibility, assess severity (CVSS 3.1 + 4.0). |
| 14-45 | Fix developed in a private fork. Reporter is kept informed of progress. |
| 45-60 | Coordinated disclosure planning: CVE assignment via GitHub's CNA, security advisory drafted, downstream maintainers (large adopters) given pre-release notice. |
| 60-90 | Public release of the fix in the affected repos as a PATCH version bump. GitHub Security Advisory published. Reporter credited (unless they prefer anonymity). |

Severity-based deviations:

- **Critical** (CVSS 9.0+) with active exploitation: timeline may be
  accelerated to 30 days at the maintainers' discretion.
- **Defense-in-depth** issues without a known exploit path: timeline may
  extend to 120 days to coordinate ecosystem updates.

## Severity classification

CAP severity classifications follow CVSS 3.1 / 4.0. Additionally we apply CAP
specific qualifiers:

| Class | Examples |
|---|---|
| **Safety-critical** | Vulnerabilities that allow bypassing the independent safety channel (ADR-003) or causing a Safety Supervisor to miss an E-stop signal. Treated as Critical regardless of CVSS score. |
| **Authentication / authorization** | mTLS bypass, RBAC bypass (Ch09 §9.3.2), JWT forgery on the operator console. Generally Critical or High. |
| **Confidentiality** | Heartbeat / WorkOrder leakage through a misconfigured transport. Depends on data sensitivity. |
| **Integrity** | Replay / tamper attacks on WorkOrder or ProgressEvent payloads. Generally High. |
| **Availability** | DoS against Site Agent or broker. Generally Medium-High. |

## Security-affecting components in scope

- All `cap-spec` proto messages and the security architecture defined in
  ADR-006 and Chapter 9 of the specification.
- All `cap-sdk-*` packages.
- All `cap-agent-*` packages.
- All `cap-conformance` test scaffolding.
- The Sigstore / SLSA / SBOM supply-chain attestation pipeline (CVEs
  affecting build reproducibility or signature verification are in scope).

Out of scope (escalate directly to the respective vendor):

- The host operating system, container runtime, or Kubernetes layer running
  CAP components.
- Third-party LLM providers (Claude, Gemini, OpenAI, Ollama) used by the
  reference Machine Agent implementations.
- Mosquitto / Eclipse Paho / other MQTT broker vulnerabilities — report
  directly to upstream, then notify CAP maintainers so we can adjust
  recommendations.

## CNA registration

CAP is in the process of registering as a **CVE Numbering Authority (CNA)**
through GitHub's free CNA program. While that registration is pending, CVEs
for CAP-related vulnerabilities will be requested through the GitHub Security
Advisory workflow (which uses MITRE as the issuing CNA).

Status of CNA application: *(placeholder — will be updated to "Registered
on <DATE>" once GitHub confirms)*.

## Acknowledgements

Past security reports and reporters (in chronological order) will be listed
here once the project reaches public release.

## Bounty program

There is no monetary bounty at this time. As CAP matures and gains industrial
adopters, the maintainers will evaluate establishing a coordinated bounty
program (e.g., through HackerOne or YesWeHack). Until then, recognition is
through public acknowledgement (unless the reporter prefers anonymity) and
GitHub Security Advisory credit.

## References

- ADR-003 (Independent Safety Channel) — defines the safety boundary that
  must remain inviolable.
- ADR-006 (Security Architecture) — mTLS / RBAC / STRIDE threat model.
- Chapter 9 of the CAP specification.
- GitHub Security Advisory documentation:
  <https://docs.github.com/en/code-security/security-advisories>
- CVSS 3.1: <https://www.first.org/cvss/v3.1/specification-document>
- CVSS 4.0: <https://www.first.org/cvss/v4.0/specification-document>
