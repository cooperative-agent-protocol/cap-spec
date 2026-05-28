<!--
SPDX-License-Identifier: Apache-2.0
Copyright 2026 CAP Authors
-->

# ADR-002: CAP は Transport-Neutral Semantics

## Status

Accepted

## Context

建設現場では多様な通信環境が存在する:

- **Site Agent ↔ Machine Agent**: gRPC over Wi-Fi/5G/LTE
- **Machine Agent 内部**: ROS 2 (DDS) topics/services/actions
- **現場ネットワーク**: MQTT（低帯域・高遅延環境）
- **外部連携**: REST API（クラウド / モニタリング）

プロトコルを特定のトランスポートに結合すると、異なる環境への適用が困難になる。

## Decision

**CAP のメッセージセマンティクス（意味論）はトランスポートに依存しない。**

- CAP メッセージは Protobuf で定義し、意味論は `.proto` ファイルが正とする
- 参照実装では gRPC bidirectional streaming を使用するが、これは唯一の正しいトランスポートではない
- 同じ CAP メッセージを以下のトランスポートで運べるものとする:
  - gRPC (参照実装)
  - ROS 2 DDS (ROS2-TMS bridge 経由)
  - MQTT (低帯域環境)
  - REST/WebSocket (dashboard / 外部連携)

## Consequences

### 利点

- **既存システム統合**: ROS2-TMS や OPERA のような既存基盤と自然に接続できる
- **環境適応**: 通信品質に応じてトランスポートを選択可能
- **標準化**: プロトコルの意味論が特定ベンダーの通信スタックに依存しない

### 制約

- 各トランスポートへのアダプタ（bridge）の実装が必要
- トランスポート間での QoS（順序保証、到達保証、レイテンシ）の違いを考慮する必要がある
- 参照実装の gRPC は「推奨」であり「必須」ではないことを明確にする

## Compatibility Rules

トランスポートアダプタは以下を保証しなければならない:

1. **メッセージの完全性**: CapFrame の全フィールドが欠損なく伝達される
2. **順序**: 同一 sender → receiver 間のメッセージ順序が保持される
3. **Correlation**: `correlation_id` によるリクエスト-レスポンスの紐付けが維持される
4. **Timestamp**: `sent_at` はトランスポートを跨いでも変更されない

## Related

- `runtime.proto` — CapFrame envelope と CapRuntime service 定義
- ADR-001 — LLM は Site Agent のみに配置（通信構成に影響）
