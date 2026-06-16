<!--
SPDX-License-Identifier: Apache-2.0
Copyright 2026 CAP Authors
-->

# Chapter 11: Implementation Guidelines

> **Informative.** This chapter provides recommendations for implementing CAP.
> These are guidelines, not requirements.

---

## 11.1 Language and Framework Recommendations

### 11.1.1 Machine Agent

| Concern | Recommendation | Rationale |
|---------|---------------|-----------|
| Language | Python 3.11+ or C++ | Python for rapid prototyping; C++ for resource-constrained embedded |
| gRPC | grpcio (Python), gRPC C++ | Well-supported, async-capable |
| MQTT | aiomqtt (Python), Eclipse Paho (C++) | Asyncio-native for Python |
| Async I/O | asyncio | CAP is inherently concurrent (heartbeat + task + dialogue) |
| LLM integration | HTTP API (Claude, Gemini, OpenAI) or local (Ollama) | Advisory only, see ADR-001 |

### 11.1.2 Site Agent

| Concern | Recommendation | Rationale |
|---------|---------------|-----------|
| Language | Python 3.11+ | Matches LLM ecosystem |
| gRPC server | grpcio | Reference implementation uses this |
| Web framework | FastAPI | WebSocket support, OpenAPI docs |
| Task compiler | Deterministic Python | No LLM in compilation path |
| State persistence | SQLite or PostgreSQL | For task and reservation state |

---

## 11.2 Versioning Policy

### 11.2.1 Semantic Versioning

CAP follows [Semantic Versioning 2.0](https://semver.org/):

- **v0.x.y**: Incubation phase. Breaking changes allowed between minor versions.
- **v1.0.0+**: Stable. Breaking changes require major version bump.

Current version: **v0.1.0**

### 11.2.2 Protocol Buffer Evolution Rules

| Change | Version Impact | Rule |
|--------|---------------|------|
| Add optional field | Minor | ALLOWED — use next available field number |
| Add new message type | Minor | ALLOWED — add to CapFrame oneof |
| Add enum value | Minor | ALLOWED — append to end of enum |
| Remove field | Major | MUST NOT in same major version |
| Change field number | Major | NEVER — field numbers are permanent |
| Change field type | Major | NEVER — breaks wire compatibility |
| Rename field | None | ALLOWED — field names are not on the wire |
| Mark field deprecated | Minor | ALLOWED — add `[deprecated = true]` |

### 11.2.3 Version Negotiation

1. Machine Agent sends `ConnectRequest.supported_versions` in the first message.
2. Site Agent selects the highest mutually supported version.
3. Site Agent responds with `ConnectResponse.negotiated_version`.
4. If no common version: `CapError(2003, VERSION_MISMATCH)` and stream closure.
5. If `supported_versions` is empty: assume latest v0.x.

### 11.2.4 Backward Compatibility

Implementations MUST:
- Ignore unknown protobuf fields (protobuf default behavior).
- Treat unknown enum values as `UNSPECIFIED`.
- Not require new optional fields to be present.

Implementations SHOULD:
- Log warnings when encountering unknown fields or enum values.
- Include `software_version` in `CapabilityManifest` for debugging.

### 11.2.5 Deprecation Policy

- Deprecated fields MUST remain in the proto for at least 2 minor versions.
- Deprecated fields MUST be documented with `[deprecated = true]` and a comment.
- Implementations SHOULD log warnings when deprecated fields are used.
- Removal occurs in the next major version.

---

## 11.3 Performance Guidelines

### 11.3.1 Recommended Intervals

| Parameter | Default | Min | Max | Notes |
|-----------|---------|-----|-----|-------|
| Heartbeat interval | 5s | 1s | 30s | Lower = faster detection, higher bandwidth |
| Heartbeat timeout | 15s | 5s | 60s | SHOULD be ≥ 3× heartbeat interval |
| Reconnect initial delay | 1s | 0.5s | 5s | |
| Reconnect max delay | 60s | 10s | 300s | |
| Grace period | 30s | 10s | 120s | Time before marking task as FAILED |
| Dialogue timeout | 60s | 10s | 300s | Time to wait for dialogue response |

### 11.3.2 Message Size Guidelines

| Message Type | Typical Size | Maximum |
|-------------|-------------|---------|
| Heartbeat | 200–500 bytes | 64 KB |
| ProgressEvent | 100–300 bytes | 64 KB |
| WorkOrder | 500–2000 bytes | 64 KB |
| CapabilityManifest | 1–10 KB | 64 KB |
| EntityDescriptor | 2–20 KB | 1 MB |
| AgentDialogue | 1–50 KB | 1 MB |
| CapFrame (any) | — | 4 MB |

### 11.3.3 Connection Limits

| Resource | Recommended Limit | Notes |
|----------|------------------|-------|
| Concurrent machines per Site Agent | 50 | Scale horizontally for more |
| Concurrent streams per machine | 1 | One bidirectional stream |
| Messages per second per machine | 10 | Heartbeat + events + dialogue |
| Total messages per second (site) | 500 | Sum across all machines |

---

## 11.4 Testing Recommendations

### 11.4.1 Unit Testing

- Test each state machine independently with all valid and invalid transitions.
- Test message serialization/deserialization round-trips.
- Test error code generation for each error condition.

### 11.4.2 Integration Testing

- Use `cap-conformance` test suites at the claimed conformance level.
- Test with the reference `fake_site` and `fake_excavator` agents.
- Test reconnection by killing and restarting the machine agent process.

### 11.4.3 Transport Testing

- Test gRPC with both insecure and TLS channels.
- Test MQTT with mosquitto broker.
- Test deduplication for MQTT QoS 1 messages.
- Test Last Will and Testament by killing the MQTT client process.

### 11.4.4 Load Testing

- Simulate 10+ concurrent machine agents.
- Measure heartbeat round-trip latency at p50, p95, p99.
- Verify no message loss under sustained load.

---

## 11.5 Deployment Checklist

### 11.5.1 Production

- [ ] TLS 1.3 enabled for all connections
- [ ] mTLS configured for machine agents (Level 2+)
- [ ] JWT authentication for operator console (Level 2+)
- [ ] Heartbeat timeout configured appropriately for network conditions
- [ ] Audit logging enabled with persistent storage
- [ ] SAFE_STOP behavior verified for all failure modes
- [ ] Certificate rotation procedure documented

### 11.5.2 Development / Testing

- [ ] `cap-conformance` tests pass at claimed level
- [ ] Docker Compose runs all services successfully
- [ ] Simulator integration verified (if using reference implementation)
- [ ] MQTT broker configured (if using MQTT transport)
