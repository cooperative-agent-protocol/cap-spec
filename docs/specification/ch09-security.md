<!--
SPDX-License-Identifier: Apache-2.0
Copyright 2026 CAP Authors
-->

# Chapter 9: Security

> **Normative.** This chapter defines the security requirements for CAP deployments.
> See also ADR-006 for the architectural rationale.

---

## 9.1 Threat Model (STRIDE)

The following analysis identifies threats to a CAP deployment and their mitigations.

| Threat Category | Threat | Example Attack | Mitigation | CAP Mechanism |
|----------------|--------|---------------|------------|---------------|
| **Spoofing** | Machine impersonation | Rogue device sends CapabilityManifest with a legitimate machine_id | Mutual authentication | mTLS with per-machine client certificates |
| **Spoofing** | Site Agent impersonation | Man-in-the-middle serves fake WorkOrders | Server authentication | TLS server certificate validation |
| **Tampering** | WorkOrder modification | Attacker changes `target_volume_m3` or `zone_id` in transit | Transport encryption | TLS 1.3 mandatory |
| **Tampering** | Plan hash collision | Attacker crafts a modified GoalSpec with the same plan_hash | Integrity verification | SHA-256 plan_hash (collision-resistant) |
| **Repudiation** | Denying a LocalDecision | Machine Agent claims it never proposed a plan change | Provenance tracking | `DialogueProvenance` with `agent_id`, `model_id`, `generated_at` + `AuditEvent` |
| **Information Disclosure** | Heartbeat interception | Attacker learns machine positions, fuel levels, task progress | Encryption | TLS 1.3 for all transports |
| **Information Disclosure** | GoalSpec leakage | Construction plan details exposed | Access control | RBAC: only `site_admin` and `operator` can view GoalSpec |
| **Denial of Service** | Heartbeat flooding | Attacker sends thousands of Heartbeats per second | Rate limiting | Per-machine_id rate limit (implementation-defined) |
| **Denial of Service** | Connection exhaustion | Attacker opens many concurrent streams | Connection limits | Max connections per client certificate |
| **Elevation of Privilege** | Observer issues WorkOrder | Observer role sends WorkOrder via a crafted CapFrame | Authorization check | RBAC per CapFrame body type |

---

## 9.2 Authentication

### 9.2.1 Machine Agent ↔ Site Agent (gRPC)

CAP deployments MUST use mutual TLS (mTLS) for machine-to-site communication:

- **Site Agent** presents a server certificate signed by a trusted CA.
- **Machine Agent** presents a client certificate with `CN = {machine_id}`.
- The Site Agent MUST verify that the `machine_id` in `CapabilityManifest` matches
  the CN of the client certificate. Mismatch results in `CapError(3006)` and
  stream closure.

**Certificate lifecycle:**
1. Site CA is generated during site deployment.
2. Machine certificates are issued at machine registration (bound to `machine_id`).
3. Recommended validity: aligned with site deployment duration (typically 1 year).
4. Revocation: CRL or OCSP. Revoked certificates MUST be rejected at the TLS layer.

### 9.2.2 Machine Agent ↔ Site Agent (MQTT)

MQTT brokers MUST enforce one of:
- TLS + client certificate authentication (preferred), or
- TLS + username/password authentication.

The MQTT username or client certificate CN MUST match the `machine_id`.
See Chapter 4 (Communication Model) for MQTT-specific ACL requirements.

### 9.2.3 Human Users (WebSocket / REST)

Human operators authenticate via JWT tokens:
- Tokens are issued by an identity provider (implementation-defined; OAuth 2.0 / OIDC recommended).
- Tokens MUST contain: `sub` (user_id), `role` (CAP role), `exp` (expiration), `iss` (issuer).
- The dashboard WebSocket connection MUST validate the JWT on the HTTP upgrade request.
- Token lifetime: implementation-defined (recommended 1 hour with refresh).

---

## 9.3 Authorization (RBAC)

### 9.3.1 Role Definitions

| Role | Description | Typical User |
|------|-------------|-------------|
| `site_admin` | Full access to all CAP operations | Site manager, system administrator |
| `operator` | Task management and machine control (except full autonomy mode) | Remote operator, field supervisor |
| `machine_agent` | Machine-side protocol participation | Automated machine agent software |
| `observer` | Read-only access to dashboards and audit logs | Client representative, safety auditor |

### 9.3.2 Role × Message Authorization Matrix

| CapFrame Body Type | site_admin | operator | machine_agent | observer |
|-------------------|:----------:|:--------:|:-------------:|:--------:|
| WorkOrder (send) | ALLOW | ALLOW | DENY | DENY |
| CancelWorkOrder (send) | ALLOW | ALLOW | DENY | DENY |
| ReservationRequest (send) | ALLOW | DENY | ALLOW | DENY |
| ReservationRelease (send) | ALLOW | DENY | ALLOW | DENY |
| ModeCommand (send) | ALLOW | ALLOW¹ | DENY | DENY |
| CapabilityManifest (send) | DENY | DENY | ALLOW | DENY |
| Heartbeat (send) | DENY | DENY | ALLOW | DENY |
| WorkOrderAck (send) | DENY | DENY | ALLOW | DENY |
| ProgressEvent (send) | DENY | DENY | ALLOW | DENY |
| FaultEvent (send) | DENY | DENY | ALLOW | DENY |
| HandoverEvent (send) | DENY | DENY | ALLOW | DENY |
| SafetyEvent (send) | DENY | DENY | ALLOW | DENY |
| AuditEvent (send) | ALLOW | ALLOW | ALLOW | DENY |
| EntityStateUpdate (send) | DENY | DENY | ALLOW | DENY |
| EntityInteraction (send) | DENY | DENY | ALLOW | DENY |
| AgentDialogue (send) | ALLOW | ALLOW | ALLOW | DENY |
| CapError (send) | ALLOW | ALLOW | ALLOW | DENY |
| ReservationStatus (send) | ALLOW | DENY | DENY | DENY |
| Dashboard read | ALLOW | ALLOW | DENY | ALLOW |
| Audit read | ALLOW | ALLOW | DENY | ALLOW |

> ¹ `operator` can send `ModeCommand` for all modes **except** `AUTONOMY`. Only `site_admin`
> can authorize transition to full `AUTONOMY` mode.

### 9.3.3 Authorization Enforcement

1. The Site Agent MUST check the sender's role before processing any CapFrame.
2. Authorization is enforced at the CapFrame body type level, not the field level.
3. Unauthorized requests MUST be rejected with `CapError(3006, AUTHORIZATION_DENIED)`.
4. All authorization decisions (both ALLOW and DENY) MUST be recorded in the audit trail.

---

## 9.4 Transport Encryption

### 9.4.1 Requirements

| Requirement | Level | Description |
|-------------|-------|-------------|
| TLS version | MUST | TLS 1.3 or later. TLS 1.2 MAY be accepted as a fallback but MUST NOT be the default. |
| Cipher suites | MUST | Only AEAD cipher suites (e.g., `TLS_AES_256_GCM_SHA384`, `TLS_CHACHA20_POLY1305_SHA256`). |
| Certificate validation | MUST | Both sides MUST validate peer certificates against the site CA trust store. |
| Plaintext fallback | MUST NOT | Production deployments MUST NOT allow unencrypted connections. |
| Development exception | MAY | Development and testing environments MAY use plaintext connections with explicit opt-in configuration. |

### 9.4.2 Per-Transport Requirements

| Transport | Encryption | Authentication | Additional |
|-----------|-----------|---------------|------------|
| gRPC | TLS 1.3 | mTLS | gRPC keepalive over TLS |
| MQTT | TLS 1.3 | Client cert or username/password | Broker-level ACL per topic |
| WebSocket | WSS (TLS 1.3) | JWT on upgrade | Origin validation |

---

## 9.5 Safety Boundary

> See also: `docs/safety-boundary.md`

The security model does NOT replace the Safety Supervisor. Key distinctions:

| Concern | Security Model | Safety Supervisor |
|---------|---------------|-------------------|
| Purpose | Prevent unauthorized access | Prevent physical harm |
| Mechanism | Authentication + Authorization | Geofence, human detection, E-stop |
| Failure mode | CapError → stream closure | SAFE_STOP → motion inhibit |
| Independence | Depends on CAP runtime | Independent of CAP runtime |

A compromised CAP security layer (e.g., stolen machine certificate) MUST NOT be able to
bypass the Safety Supervisor. The Safety Supervisor operates on an independent channel
(see ADR-003) and can unilaterally trigger `SAFE_STOP` regardless of CAP state.

---

## 9.6 Implementation Notes

As of M3.8, the reference implementation provides:

- **mTLS support**: `cap_sdk.server.serve_secure()` and `MachineAgentClient` TLS
  parameters (`tls_cert_path`, `tls_key_path`, `tls_ca_path`).
- **Certificate generation**: `cap_sdk.security.cert_gen` generates site CA, server,
  and per-machine client certificates (P-256 EC keys).
- **RBAC enforcement**: `cap_sdk.security.rbac.RBACEnforcer` implements the Ch09 §9.3.2
  matrix. Enable via `CapRuntimeServicer(enforce_rbac=True)`.
- **CN validation**: Site Agent verifies `CapabilityManifest.machine_id` matches the
  client certificate CN when mTLS is active.
- The insecure `serve()` function is retained for development and testing.
- JWT authentication for an operator-facing dashboard is out of scope here
  and is owned by the implementation layer that provides such a console.
- Conformance Level 1 does not require security features.
  Conformance Level 2 requires TLS. Conformance Level 3 requires mTLS + RBAC.
