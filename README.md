<!--
SPDX-License-Identifier: Apache-2.0
Copyright 2026 CAP Authors
-->

# CAP Spec — Cooperative Agent Protocol

> 産業機械群の協調運用のためのオープンプロトコル仕様 — Construction Domain Pack v0 をリファレンス実装として開発、将来 Agriculture / Mining / Forestry / Intralogistics ドメインへ拡張可能

## Overview

CAP (Cooperative Agent Protocol) は、LLM ベースの Site Agent と産業機械の Machine Agent 間の
通信セマンティクスを定義する domain-agnostic なプロトコルです。Core (Manifest / WorkOrder /
Heartbeat / Dialogue / ALO / Safety Supervisor) は任意の重機・農機・鉱山機械等で利用可能で、
ドメイン固有の skill / zone / equipment 定義は **Domain Pack** として切り出されています。
v0.x のリファレンスドメインは **Construction** (建設重機) です。

**設計原則:**

- **Transport-Neutral**: gRPC / MQTT / WebSocket のいずれでも同じ意味論で運べる (ADR-002)
- **Machine-Agnostic**: OEM を問わず同じスキル API
- **Safety-Independent**: 安全インターロックは CAP の外側に独立系統として配置 (ADR-003)
- **3-Layer LLM Architecture** (ADR-001 改訂):
  - Layer [A] Site Agent — 大規模 LLM（戦略計画、タスク分解）
  - Layer [B] Machine Agent — LLM/SLM（状況判断、advisory only）
  - Layer [C] Safety Supervisor — deterministic 制御（LLM 非介在）

## Proto Structure

```
proto/cap/v0/
├── common.proto         # 共通型 (enums, MessageHeader, Pose3D, etc.)
├── site_agent.proto     # Site → Machine (WorkOrder, ModeCommand, Reservation)
├── machine_agent.proto  # Machine → Site (Manifest, Heartbeat, WorkOrderAck)
├── events.proto         # イベント (Progress, Fault, Handover, Safety, Reservation, Audit)
├── error.proto          # 構造化エラー (CapError, ErrorDomain, 15+ エラーコード)
├── alo.proto            # Abstract Language Objects (ALODescriptor, ALOManager)
├── dialogue.proto       # エージェント対話 (SituationReport, LocalDecision, PlanProposal)
└── runtime.proto        # CapFrame envelope + CapRuntimeService gRPC
```

## Core Messages

| Message | Direction | Purpose |
|---------|-----------|---------|
| `CapabilityManifest` | Machine → Site | 接続時に機体のスキル・ALO 記述を宣言 |
| `Heartbeat` | Machine → Site | 定期的な死活監視・状態報告 |
| `WorkOrder` | Site → Machine | スキルレベルのタスク指示 |
| `WorkOrderAck` | Machine → Site | タスクの受理/拒否/延期 |
| `ProgressEvent` | Machine → Site | タスク進捗の報告 |
| `HandoverEvent` | Machine → Site | 遠隔操作への切替要求 |
| `ModeCommand` | Site → Machine | 運転モード変更指示 |
| `ReservationRequest/Status` | Both | 共有リソースの予約・競合管理 |
| `AgentDialogue` | Both | エージェント間対話（状況報告、判断提案） |
| `ALOStateUpdate` | Machine → Site | ALO 状態の動的更新 |
| `CapError` | Both | 構造化エラー応答 |

## Formal Specification

11 章の正式仕様書: [docs/specification/](docs/specification/)

| 章 | 内容 |
|----|------|
| Ch01 | Scope — 適用範囲と限界 |
| Ch02 | Terms and Definitions |
| Ch03 | Architecture Overview — 3 層アーキテクチャ |
| Ch04 | Communication Model — transport profile, QoS |
| Ch05 | Protocol Flows — シーケンス図 |
| Ch06 | State Machines — TaskState, MachineMode, ReservationState, Handover, Dialogue |
| Ch07 | Message Reference — 全メッセージの詳細仕様 |
| Ch08 | Error Handling — エラーコード体系、リトライ |
| Ch09 | Security — mTLS, JWT, RBAC, STRIDE 脅威モデル |
| Ch10 | Conformance — Level 1 (Core) / Level 2 (Coordination) / Level 3 (Intelligence) |
| Ch11 | Implementation Guidelines |

## Formal Verification (TLA+)

全状態遷移が TLA+ で形式検証済み: [formal/tla/](formal/tla/)

- **TaskState**: terminal absorbing, at most one active, eventual termination
- **ReservationState**: no double-grant, eventual decision
- **MachineMode + Handover**: SAFE_STOP reachability, timeout → SAFE_STOP
- **CAPCoordination**: multi-machine deadlock-free, no double-grant

検証結果: [formal/tla/RESULTS.md](formal/tla/RESULTS.md)

## Architecture Decision Records

| ADR | 内容 |
|-----|------|
| [ADR-001](docs/adr/001-llm-site-agent-only.md) | 3 層 LLM アーキテクチャ（改訂版: Machine Agent にも LLM、advisory only） |
| [ADR-002](docs/adr/002-transport-neutral-semantics.md) | Transport-Neutral Semantics |
| [ADR-003](docs/adr/003-independent-safety-channel.md) | Safety Channel は独立系統 |
| [ADR-004](docs/adr/004-alo-representation.md) | ALO as machine and site object representation |
| [ADR-005](docs/adr/005-agent-dialogue-protocol.md) | Agent Dialogue Protocol |
| [ADR-006](docs/adr/006-security-architecture.md) | Security Architecture (mTLS, RBAC, STRIDE) |
| [ADR-007](docs/adr/007-formal-verification.md) | Formal Verification with TLA+ |

## Quick Start

```bash
make lint       # Proto lint (requires buf CLI)
make gen        # Generate code (Python, C++, TypeScript)
make breaking   # Check breaking changes
make verify     # TLA+ formal verification (requires Java + tla2tools.jar)
```

## Other Documents

- [Safety Boundary](docs/safety-boundary.md) — 安全境界の設計原則
- [CAP vs MCP](docs/cap-vs-mcp.md) — MCP との比較と位置づけ
- [Examples](examples/v0/excavator_dump/) — サンプルペイロード

## License

Apache License 2.0 — see [LICENSE](LICENSE).
