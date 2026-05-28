<!--
SPDX-License-Identifier: Apache-2.0
Copyright 2026 CAP Authors
-->

# ADR-001: LLM 配置アーキテクチャ

## Status

**Revised** — 初版: Site Agent のみ → 改訂版: 3 層アーキテクチャ（ADR-004, ADR-005 と同時）

## Context

CAP アーキテクチャにおいて、LLM/VLM をどの層に配置するかは安全性・レイテンシ・コストに大きく影響する。選択肢として:

1. **Machine Agent に LLM を配置**: 各重機が自律的に言語理解・計画を行う
2. **Site Agent にのみ LLM を配置**: 中央で言語理解・計画を行い、Machine Agent にはスキルレベルの指示を送る
3. **両方に配置**: Site Agent に大規模 LLM、Machine Agent に小規模 LLM

## Decision

**LLM/VLM は Site Agent にのみ配置する。**

Machine Agent は deterministic なスキル実行エンジンとし、LLM を含まない。

## Consequences

### 利点

- **安全性**: Machine Agent のリアルタイム制御ループに LLM の不確実性が入らない
- **監査可能性**: LLM の出力は TaskGraph / WorkOrder として明示的に記録され、後から検証可能
- **コスト効率**: 高性能 GPU は Site Server に集約。各重機の rugged PC に GPU は不要
- **レイテンシ**: Machine Agent の制御ループ（100Hz クラス）に LLM 推論（数百ms〜数秒）が介在しない
- **説明責任**: 計画の生成元が一箇所に限定され、責任の所在が明確

### 制約

- Machine Agent は自然言語を直接理解できない（WorkOrder の skill / parameters で指示を受ける）
- 通信断時に Machine Agent は再計画できない（safe_wait / safe_stop に遷移する）
- 将来、エッジ LLM が十分成熟した場合はこの決定を見直す可能性がある

## Decision (Revised)

初版の「Site Agent のみ」から以下の 3 層アーキテクチャに改訂:

| 層 | 配置 | モデル | 役割 | 制御権 |
|----|------|--------|------|--------|
| **[A] 戦略層** | Site Agent | 大規模 LLM (Claude/GPT) | 全体計画・スケジューリング・対話解釈 | TaskGraph / WorkOrder |
| **[B] 戦術層** | Machine Agent | LLM/SLM (Claude Haiku / Gemini Flash / Phi-3 等) | 状況判断・状態記述・提案 | **Advisory のみ** |
| **[C] 実行層** | Safety Supervisor | なし (deterministic) | 100Hz 制御・安全停止 | Actuator 直接制御 |

**改訂の核心**: Machine Agent に LLM/SLM を追加するが、**安全原則は維持**:
- モデルは actuator に直接指令を出さない（Advisory role のみ）
- デフォルトは Cloud LLM（Claude Haiku 等）。SLM（Ollama/Phi-3）は低遅延・オフライン環境向けオプション
- Layer [C] は LLM/SLM 非介在の deterministic 制御を維持
- Safety channel の独立性（ADR-003）は不変

**自律性スコープ管理** (LocalDecisionScope):
- MICRO: 自律実行可（パラメータ微調整）
- TASK / CROSS_TASK: Site Agent 承認必須

**ALO 統合** (ADR-004): ALO (Ochiai, 2304.04498) を機械の自己表現モデルとして採用。
CapabilityManifest に ALODescriptor を含め、Heartbeat に alo_state_summary を追加。

**Agent Dialogue Protocol** (ADR-005): 構造化された対話プロトコルで
SituationReport / LocalDecision / PlanProposal をサポート。

## Related

- [safety-boundary.md](../safety-boundary.md) — LLM は Task レベルのみを担当
- ADR-003 — Safety channel の独立性
- ADR-004 — ALO を現場オブジェクトの統一表現として採用
- ADR-005 — Agent Dialogue Protocol
