<!--
SPDX-License-Identifier: Apache-2.0
Copyright 2026 CAP Authors
-->

# ADR-003: Safety Channel は独立系統

## Status

Accepted

## Context

建設重機の自律運用において、安全機能（E-stop、ジオフェンス、人検知、motion inhibit）は最も重要な要素である。これらを CAP プロトコルの通信チャネルに依存させることは、以下のリスクを生む:

- CAP ランタイムのクラッシュ / ハング時に安全機能が停止する
- ネットワーク遅延 / 切断時に安全応答が遅れる
- ソフトウェアバグが安全機能に波及する

## Decision

**安全インターロックは CAP ランタイムとは独立した系統で実装する。**

具体的には:

1. **Safety Supervisor** は CAP ランタイムとは別プロセスで動作する
2. **E-stop** は物理配線レベルで保証する（ソフトウェア非依存）
3. **Motion inhibit** は Safety Supervisor → Safety PLC/MCU の直接経路で発動する
4. CAP の `SafetyEvent` / `HandoverEvent` は **情報伝達** であり、安全動作のトリガーではない

## Architecture

```
  CAP Runtime        Safety Supervisor       Safety PLC/MCU
  ┌──────────┐       ┌──────────────┐       ┌──────────────┐
  │WorkOrder │       │ Geofence     │       │ Physical     │
  │Progress  │←info──│ Human Detect │──act──│ E-stop       │
  │Handover  │       │ Localization │       │ Hydraulic    │
  │SafetyEvt │       │ Mode Control │       │ Cutoff       │
  └──────────┘       └──────────────┘       └──────────────┘
       ↑ 情報のみ          ↑ 制御権           ↑ ハードウェア
```

- **info**: Safety Supervisor → CAP Runtime への通知（SafetyEvent 送信）。CAP 側は情報として受信するが、安全動作は既に発動済み。
- **act**: Safety Supervisor → Safety PLC/MCU への直接制御。CAP を経由しない。

## Consequences

### 利点

- **フェイルセーフ**: CAP ランタイムが停止しても安全機能は継続する
- **ISO 準拠**: ISO 17757 / ISO 19014 が要求する安全アーキテクチャと整合する
- **認証分離**: 安全系統のみを安全認証の対象にでき、CAP 全体を認証する必要がない
- **信頼性**: 安全機能のコードベースを最小限に保てる

### 制約

- Safety Supervisor と CAP Runtime の間に情報共有のインターフェースが必要
- Safety Supervisor の開発・テストは CAP とは別のプロセスで行う必要がある
- 重機ごとに Safety PLC/MCU のハードウェア設計が必要

## Related

- [safety-boundary.md](../safety-boundary.md) — 安全境界の全体設計
- ADR-001 — LLM は Site Agent のみ（Machine Agent に LLM を置かないことで安全性を確保）
