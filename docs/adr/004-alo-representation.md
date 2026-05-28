<!--
SPDX-License-Identifier: Apache-2.0
Copyright 2026 CAP Authors
-->

# ADR-004: ALO を現場オブジェクトの統一表現として採用

## Status

Accepted

## Context

CAP アーキテクチャでは、ゾーン・機械・資材・積込地点・搬出路など多様なオブジェクトを
Site Agent（LLM）と Machine Agent（LLM/SLM / deterministic）の双方が共有する必要がある。

従来の approach では:
1. 各オブジェクトをスキーマごとに別個の proto message で定義 → message 増加、拡張困難
2. Key-Value bag で汎用化 → 型安全性が低く、LLM が構造を把握しにくい

ALO (Abstract Language Object, Ochiai et al., 2304.04498) は、言語的オブジェクトと
Turing machine オブジェクトを橋渡しする表現で、以下の特性を持つ:
- **canonical_name**: 人間にとって自然な名前（"B3区画"、"バックホウ1号機"）
- **typed properties**: 機械が QueryProxy 的に参照可能な構造化属性
- **state_description**: LLM が直接読める自然言語状態記述
- **manager**: スキル・関係・ルールの宣言

## Decision

**ALO を CAP のすべてのドメインオブジェクト表現の統一基盤とする。**

具体的には:

1. **CapabilityManifest に ALODescriptor を追加** (field 8)
   - 機械は接続時に自身を ALO として自己記述する
   - Site Agent は LLM に manifest の ALO を渡して自然言語で推論できる
   - capabilities（スキル）は manager.available_skills と対応

2. **ALOStateUpdate で状態同期** (CapFrame field 40)
   - Machine Agent が ALO の状態変化を Site Agent に通知
   - state_description は LLM/SLM 生成（advisory）または template-based

3. **ALOInteraction でオブジェクト間イベント** (CapFrame field 41)
   - 掘削機がゾーンを掘削する、ダンプに積み込むなどの interaction を記録

4. **SiteState (Digital Twin) は ALO インスタンスの集合**
   - 実装側 world_model は ALOInstance の集合として保持する想定
   - to_llm_context() 等で LLM プロンプトに投入可能

## Consequences

### 利点

- **統一表現**: ゾーン・機械・資材を同じスキーマで扱え、拡張時に新 message 型が不要
- **LLM-friendly**: canonical_name + state_description で LLM が自然に理解
- **監査可能**: ALOStateUpdate / ALOInteraction が proto レベルで audit trail に乗る
- **研究基盤**: Ochiai et al. の理論的フレームワークに基づき、論文化が容易

### 制約

- ALODescriptor はオプショナル — ALO 非対応の Machine Agent も接続可能
- state_description の品質は LLM/SLM / テンプレートの実装品質に依存
- ALO のスキーマ進化は alo.proto の後方互換性を維持して行う

## Related

- ADR-001 (revised) — 2層 LLM アーキテクチャ
- ADR-005 — Agent Dialogue Protocol（ALO を対話の共有コンテキストとして使用）
- [alo.proto](../../proto/cap/v0/alo.proto) — ALO メッセージ定義
- Ochiai et al. (2304.04498) — ALO 理論的基盤
