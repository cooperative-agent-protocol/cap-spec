<!--
SPDX-License-Identifier: Apache-2.0
Copyright 2026 CAP Authors
-->

# ADR-005: Agent Dialogue Protocol

## Status

Accepted

## Context

M3 までの CAP は WorkOrder / ProgressEvent / HandoverEvent による命令・報告型の通信のみを
サポートしていた。Machine Agent は Site Agent の指示を受けてスキルを実行し、進捗を報告する
受動的な存在であった。

しかし、現場では:
- 機械側で検知した状況変化を即時に伝え、Site Agent に判断材料を提供したい
- 機械が軽微な判断（掘削速度の微調整など）を自律的に行い、重要な判断のみ承認を求めたい
- 機械が計画変更を提案できるようにしたい（例: 土質変化による掘削方法の変更提案）

これらを実現するため、Machine Agent に LLM（デフォルト）または SLM を搭載し、構造化された対話プロトコルを導入する。

## Decision

**3 層アーキテクチャと Agent Dialogue Protocol を導入する。**

### 3 層アーキテクチャ

| 層 | 配置 | モデル | 役割 | 制御権 |
|----|------|--------|------|--------|
| [A] 戦略層 | Site Agent | 大規模 LLM (Claude/GPT) | 全体計画・スケジューリング・対話解釈 | TaskGraph / WorkOrder |
| [B] 戦術層 | Machine Agent | LLM/SLM (Claude Haiku / Gemini Flash / Phi-3 等) | 状況判断・状態記述・提案 | **Advisory のみ** |
| [C] 実行層 | Safety Supervisor | なし (deterministic) | 100Hz 制御・安全停止 | Actuator 直接制御 |

**モデルの制約: Layer [B] のモデル（LLM/SLM）は actuator に直接指令を出さない。**
すべてのアクチュエータ制御は Layer [C] の deterministic 層を経由する。

### Dialogue Protocol

新規 proto: `dialogue.proto`

**メッセージ型:**
- `SituationReport` — Machine → Site: 現在の状況報告（自然言語 + 構造化 facts）
- `LocalDecision` — Machine → Site: 機械が行った/提案する判断
- `PlanProposal` — Machine → Site: 計画変更提案
- `DialogueMessage` — 個々のメッセージ（intent + content + provenance）
- `AgentDialogue` — 対話エンベロープ（dialogue_id + 参加者 + メッセージ列）

**DialogueIntent:**
- SITUATION_REPORT: 状況報告
- LOCAL_DECISION: ローカル判断
- PLAN_PROPOSAL: 計画提案
- ACKNOWLEDGEMENT: 受領確認
- INSTRUCTION: Site Agent からの指示
- QUERY: 質問

### LocalDecisionScope（自律性スコープ）

| Scope | 説明 | 承認 |
|-------|------|------|
| MICRO | パラメータ微調整（掘削速度、旋回速度など） | 不要 — 自律実行可 |
| TASK | 現在タスクに影響する判断（掘削方法変更、一時停止など） | **Site Agent 承認必須** |
| CROSS_TASK | 複数タスク/他機械に影響（スケジュール変更提案など） | **Site Agent 承認必須** |

フロー:
1. Machine Agent が LocalDecision (scope=TASK, approval_required=true) を送信
2. Site Agent が approval を判断し、approved=true/false を設定して AgentDialogue で返信
3. Machine Agent は approved=true を受信するまで該当行動を実行しない

### DialogueProvenance（出所追跡）

すべての DialogueMessage に DialogueProvenance を付与:
- `agent_id`: 発話元エージェント
- `model_id`: 使用したモデル（"claude/claude-haiku-4-5", "ollama/phi3:mini", "fake-rule-based" 等）
- `confidence`: 信頼度 (0.0–1.0)
- `reasoning_summary`: 生成ロジックの要約

これにより、対話の監査・リプレイ・分析が可能になる。

## Consequences

### 利点

- **双方向知能**: 機械が受動的スキル実行機からインテリジェントな対話者に進化
- **段階的自律**: MICRO は即時実行、TASK/CROSS_TASK は承認付きで安全性を維持
- **監査可能**: Provenance によりすべての対話に出所と信頼度が記録される
- **モデル安全性**: Advisory only — actuator 非制御の原則により ADR-003 の安全チャネル独立性を維持
- **研究貢献**: ALO-grounded 2 層 LLM multi-agent 協調は新規性の核

### 制約

- モデルの推論品質はバックエンド・プロンプトに依存 — FakeMachineModel でも基本動作は保証
- 対話の遅延は TaskGraph 実行のクリティカルパスに影響しうる — MICRO scope で回避可能
- Site Agent の LLM が対話を解釈できない場合のフォールバックが必要

## Related

- ADR-001 (revised) — 2 層 LLM アーキテクチャ（本 ADR で具体化）
- ADR-003 — Safety channel 独立性（Layer [C] の原則）
- ADR-004 — ALO 表現（対話の共有コンテキスト）
- [dialogue.proto](../../proto/cap/v0/dialogue.proto) — 対話メッセージ定義
- [safety-boundary.md](../safety-boundary.md) — LLM scope の制限
