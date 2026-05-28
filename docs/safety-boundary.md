<!--
SPDX-License-Identifier: Apache-2.0
Copyright 2026 CAP Authors
-->

# CAP Safety Boundary

> このドキュメントは、Cooperative Agent Protocol (CAP) における安全境界の設計原則を定義する。

## 1. CAP は安全認証対象外

CAP プロトコル自体は **安全認証（SIL, PL, ASIL 等）の対象ではない**。CAP はタスクレベルの通信セマンティクスを定義するものであり、緊急停止や衝突回避などの安全機能を提供するものではない。

**安全機能は CAP の外側に配置しなければならない。**

## 2. 独立安全チャネル

安全インターロック（E-stop、ジオフェンス、人検知による停止等）は、CAP ランタイムとは **独立した通信経路・プロセス** で動作する。

- CAP ランタイムがクラッシュ・遅延しても、安全チャネルは影響を受けない
- 安全チャネルは dedicated なハードウェア（Safety PLC / MCU）または独立プロセスで実装する
- E-stop は物理的な配線レベルで保証する（ソフトウェアのみに依存しない）

```
┌─────────────────────────────────────────┐
│           CAP Runtime (gRPC)            │
│  WorkOrder / Ack / Progress / Handover  │
└─────────────────────────────────────────┘
           ↕ 情報共有のみ（制御権なし）
┌─────────────────────────────────────────┐
│       Safety Supervisor (独立系統)       │
│  Geofence / Human Detection / E-stop   │
│  Motion Inhibit / Safe Stop            │
└─────────────────────────────────────────┘
           ↕ ハードウェアインターロック
┌─────────────────────────────────────────┐
│       Safety PLC / MCU / Relay          │
│  物理 E-stop / 油圧カットオフ           │
└─────────────────────────────────────────┘
```

## 3. LLM は Task レベルのみ

LLM/VLM は以下のみを担当する:

- 自然言語指示の解釈 → GoalSpec への変換
- TaskGraph / Behavior Tree の生成
- 再計画と説明生成

LLM は以下を **直接制御しない**:

- 油圧バルブ / ジョイント角度 / モータトルク
- 低レイヤのモーションプランニング（100Hz クラスの制御ループ）
- 安全インターロックの発動・解除

## 4. Safety Kernel 分離

Safety Supervisor は CAP ランタイムおよび LLM planner とは **別プロセス** で動作する。

| 機能 | 担当 | LLM アクセス |
|------|------|-------------|
| ジオフェンス侵入検知 | Safety Supervisor | なし |
| 人検知 → motion inhibit | Safety Supervisor | なし |
| 測位精度劣化 → safe stop | Safety Supervisor | なし |
| E-stop 状態監視 | Safety PLC/MCU | なし |
| WorkOrder 生成 | Site Agent (LLM) | あり |
| 再計画 | Site Agent (LLM) | あり |

## 5. モード遷移

マシンの動作モードは Safety Supervisor が管轄する。

```
MANUAL ←→ TELEOP ←→ SUPERVISED_AUTONOMY ←→ AUTONOMY
                          ↓
                      SAFE_STOP
```

- `MANUAL → TELEOP`: オペレータ操作で遷移
- `TELEOP → SUPERVISED_AUTONOMY`: Safety Supervisor が条件確認後に許可
- `SUPERVISED_AUTONOMY → AUTONOMY`: 将来拡張（v0 では未使用）
- `任意 → SAFE_STOP`: Safety Supervisor が一方的に発動可能
- `SAFE_STOP → MANUAL`: オペレータによる物理リセット後のみ

CAP の `ModeCommand` メッセージは **リクエスト** であり、Safety Supervisor がそれを拒否する権限を持つ。

## 6. 関連規格

- **ISO 17757**: Earth-moving machinery — Autonomous and semi-autonomous machine system safety
- **ISO 15817**: Earth-moving machinery — Safety requirements for remote operator control
- **ISO 19014**: Earth-moving machinery — Functional safety

CAP はこれらの規格に直接準拠するものではないが、これらの規格が要求する安全アーキテクチャと矛盾しない設計を目指す。
