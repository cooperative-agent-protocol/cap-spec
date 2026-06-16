<!--
SPDX-License-Identifier: Apache-2.0
Copyright 2026 CAP Authors
-->

# ADR-006: Security Architecture

## Status

Accepted

## Context

これまでの CAP 参照実装は平文通信（`grpc.insecure_channel`）で動作しており、
認証・認可・暗号化の仕組みが存在しない。研究デモとしては十分だが、本仕様書では
外部実装者が安全な CAP 実装を構築できるレベルのセキュリティ要件を定義する必要がある。

建設現場の通信には以下の脅威が存在する:

- **なりすまし**: 不正なデバイスが Machine Agent を偽装し、虚偽の ProgressEvent を送信
- **改ざん**: WorkOrder のパラメータ（掘削座標、搬出先）が通信中に書き換えられる
- **否認**: Machine Agent が LocalDecision を実行した後に「承認されていなかった」と主張
- **情報漏洩**: Heartbeat（位置、燃料残量）や GoalSpec（工事計画）の傍受
- **DoS**: 大量の偽 Heartbeat によるサーバ過負荷
- **権限昇格**: Observer ロールのクライアントが WorkOrder を発行

## Decision

### 1. 暗号化: TLS 1.3 必須

すべての CAP 通信は TLS 1.3 以上で暗号化しなければならない（MUST）。
平文通信は開発・テスト環境でのみ許容される（MAY）。

### 2. 認証: mTLS for Machine-to-Site, JWT for Human-to-Platform

| 通信パス | 認証方式 | 根拠 |
|---------|---------|------|
| Machine Agent ↔ Site Agent (gRPC) | mTLS | 各建機に固有のクライアント証明書を発行。自動化された通信であり、トークン管理より証明書が適切 |
| Machine Agent ↔ Site Agent (MQTT) | TLS + username/password or client certificate | MQTT ブローカーの認証機能を活用 |
| 運用コンソール ↔ Dashboard (WebSocket) | JWT (Bearer token) | 人間ユーザーの認証。OAuth 2.0 / OIDC との統合を想定 |
| External API | JWT (Bearer token) | 外部システム連携 |

### 3. 認可: ロールベースアクセス制御 (RBAC)

| ロール | 許可される操作 |
|-------|-------------|
| `site_admin` | 全操作。WorkOrder 発行、ModeCommand（AUTONOMY への遷移含む）、ユーザー管理 |
| `operator` | WorkOrder 発行、ModeCommand（AUTONOMY 以外）、HandoverEvent 応答、ダッシュボード閲覧 |
| `machine_agent` | CapabilityManifest 送信、Heartbeat 送信、WorkOrderAck、ProgressEvent、FaultEvent、HandoverEvent、SafetyEvent、AgentDialogue、EntityStateUpdate |
| `observer` | 読み取りのみ。ダッシュボード閲覧、Audit 参照 |

CapFrame body type ごとに送信可能なロールを定義し、認可違反時は `CapError(3006, AUTHORIZATION_DENIED)` を返す。

### 4. 証明書管理

- サイト CA（認証局）は Site Agent デプロイ時に生成
- 各 Machine Agent にクライアント証明書を発行（machine_id と紐付け）
- 証明書有効期間: 実装定義（推奨 1 年、現場配備期間に合わせる）
- 証明書失効: CRL または OCSP による失効チェック

### 5. Audit との統合

- すべての認可判定は `AuditEvent` に記録
- `DialogueProvenance` の `agent_id` は mTLS 証明書の CN と一致しなければならない
- `plan_hash` による操作のトレーサビリティは既存の仕組みを活用

## Consequences

- 参照実装に TLS/mTLS サポートを追加する必要がある
- 本 ADR は仕様定義のみ。参照実装は引き続き insecure_channel を使用可能（テスト環境）
- MQTT ブローカー（mosquitto）の ACL 設定が必要になる
- JWT 発行サーバーの設計は実装側（運用コンソールを持つレイヤー）の範囲
