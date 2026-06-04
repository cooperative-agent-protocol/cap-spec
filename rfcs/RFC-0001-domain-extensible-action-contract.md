<!--
SPDX-License-Identifier: Apache-2.0
Copyright 2026 CAP Authors
-->

# RFC-0001: Domain-extensible action contract (typed skill params via `Any`)

| Field | Value |
|---|---|
| RFC | 0001 |
| Title | Domain-extensible action contract (typed skill params via `Any`) |
| Author(s) | R-Okauchi (`@R-Okauchi`) |
| Status | Draft |
| Created | 2026-06-04 |
| Last Updated | 2026-06-04 |
| Related ADR | (TBD) |
| Related Discussion | (TBD) |
| Reference Implementation | **Phase-1 landed (additive・非破壊)**: `SkillInvocation`(core/skill.proto), `WorkOrder.invocation`(core/site_agent.proto), `WorkOrder.parameters` の `deprecated` 化, Core conformance(`cap-conformance/tests/test_skill_invocation.py`)。**Phase-2 (additive・非破壊)**: `Intent.domain_intent`(Any) 追加、`domains/construction/intent.proto` 新設、旧 core 建設 intent/message/oneof fields の `deprecated` 化、`SkillExecution.invocation` 追加 + `SkillExecution.parameters` deprecated。削除・tag reserve は v0 では行わず、cap.v1 境界のみ。 |

## Summary

CAP は「多分野・多者で使われる汎用協調プロトコル」を標榜するが、**機体に「何の動作を・どの引数で」やらせるか**の表現が現状 3〜4 通りに分裂し、しかも **core に建設(掘削機)固有の型が直書き**されている。本 RFC は、(1) core に**分野非依存の汎用アクション・エンベロープ** `SkillInvocation`(domains が `google.protobuf.Any` で型付き payload を差し込む) を定義し、(2) `Intent.domain_intent`(Any) を追加して domain-specific intent を core 不変で運べるようにし、(3) 建設 intent の正本を `domains/construction/intent.proto` に置き、core に残る旧建設 intent を deprecated 化し、(4) `WorkOrder`/`SkillExecution` の `map<string,string> parameters` (= 型なし blob) を非推奨化する。ADR-008 により v0 は additive-only なので、core の旧 message/field は削除せず v0 中は並存させる。これにより**新分野 (Agriculture/Mining/Intralogistics 等) が core を一切変更せず**、自分の typed param/intent を足して CAP に乗れるようになる。

## Motivation

現状、「アクション + 引数」の表現が **不整合かつ分野漏れ** している(実 proto 調査):

1. **core への分野漏れ**: `core/intent.proto` の `Intent.payload` oneof が `drive/stop`(汎用)に加えて **`dig`(`DigIntent`)/`swing`/`load_truck`(`LoadTruckIntent`)/`stabilize_arm`/`dump`(`DumpIntent`)/`wait_for_load`** という**掘削機固有**の型を持つ。これは domain-agnostic であるべき core の層違反で、Agriculture や Intralogistics から見れば無関係なノイズ。新分野ごとに core の oneof を膨張させるのは破綻する。
2. **宙吊りの拡張機構**: `domains/construction/skills.proto:54` のコメントは「各 skill は強く型付けされた param message を持ち、**CAP-Core の `SkillInvocation` が `Any` で運ぶ**(string blob を避ける)」と設計意図を明記しているが、**`SkillInvocation` はどの proto にも定義されていない**(dangling reference)。
3. **`google.protobuf.Any` が CAP 全体で未使用**: 分野が型付き payload を core を触らず差し込む拡張機構が**実装されていない**。
4. **型なし blob の残存**: `WorkOrder.parameters` と `SkillExecution.parameters` は `map<string,string>`。実装(例: cap-pangaea)は `dig_reach`/`swing_to_rad`/経路 JSON 等を文字列で密輸しており、型安全・検証・相互運用を失っている — これはまさに上記コメントが避けたかった "blob"。

この RFC が無いと: **新 Domain Pack を足すたびに core を改変する**圧力がかかり(層違反の拡大)、実装は string-map に頼り続け(相互運用の喪失)、`SkillInvocation` の設計意図は宙吊りのまま残る。

## Background

- CAP は `core/`(transport/runtime, 分野非依存) と `domains/<x>/`(Domain Pack) に分かれる。`rfcs/domain-pack-template.md` と README の例示(Agriculture/Mining/Forestry/Intralogistics)が**複数分野前提**を示す。
- `domains/construction/skills.proto` は既に**正しい層**で `enum SkillName` + 型付き param (`ExcavateBatchParams`/`HaulRouteParams`/`DumpParams`) を持つ。足りないのは、それらを core が運ぶ汎用機構。
- `core/intent.proto` の `DriveIntent` は `plan`(= `control.proto` の `TrajectoryRequest`) + `abort_policy` を持ち、これは**汎用**(任意の移動協調エージェント)。`StopIntent` も汎用。`Dig/Swing/LoadTruck/StabilizeArm/Dump/WaitForLoad` のみが建設固有。

## Detailed Design

### Proto schema changes

**(1) core に汎用アクション・エンベロープを新設** (`core/skill.proto`):

```protobuf
import "google/protobuf/any.proto";

// SkillInvocation: domain-agnostic envelope for "invoke skill X with typed params".
// The domain-specific parameters travel as a google.protobuf.Any so a new Domain
// Pack can plug in its own typed message WITHOUT any core change.
message SkillInvocation {
  string skill_id            = 1;  // stable id; domain-namespaced (e.g. "construction.excavate_batch")
  string skill_name          = 2;  // human-facing
  google.protobuf.Any typed_params = 3;  // domain param message (e.g. construction.ExcavateBatchParams)
  map<string, string> metadata = 4;      // free-form only (NOT typed args)
}
```

**(2) `Intent` を分野拡張可能に** (`core/intent.proto`): 汎用 (`drive`/`stop`) は core に残す。建設固有 oneof arm は v0 では削除せず deprecated にし、domain-specific intent の新規送信は `Any` 経由の generic arm に移行する:

```protobuf
// Before (core leaks construction specifics)
message Intent {
  // ...
  oneof payload {
    DriveIntent drive = 10;
    DigIntent dig = 11;             // construction-specific — leaks into core
    SwingIntent swing = 12;          // "
    LoadTruckIntent load_truck = 13; // "
    StabilizeArmIntent stabilize_arm = 14; // "
    DumpIntent dump = 15;            // "
    WaitForLoadIntent wait_for_load = 16; // "
    StopIntent stop = 30;
  }
}

// After in cap.v0 (additive-only: legacy arms remain, deprecated)
message Intent {
  // ...
  oneof payload {
    DriveIntent drive = 10;         // generic: any mobile agent
    DigIntent dig = 11 [deprecated = true];
    SwingIntent swing = 12 [deprecated = true];
    LoadTruckIntent load_truck = 13 [deprecated = true];
    StabilizeArmIntent stabilize_arm = 14 [deprecated = true];
    DumpIntent dump = 15 [deprecated = true];
    WaitForLoadIntent wait_for_load = 16 [deprecated = true];
    StopIntent stop = 30;           // generic
    google.protobuf.Any domain_intent = 40;  // NEW: e.g. construction.DigIntent
  }
}

// At the cap.v1.core boundary only, the deprecated construction arms may be
// removed and their field tags reserved. ADR-008 forbids doing that inside v0.
```

**(3) 建設固有 intent を domain pack へ** (`domains/construction/intent.proto`, NEW): `DigIntent`/`SwingIntent`/`LoadTruckIntent`/`StabilizeArmIntent`/`DumpIntent`/`WaitForLoadIntent` を core から同一 shape で複製し、以後の正本とする。旧 core message は `option deprecated = true`、旧 oneof fields は `[deprecated = true]` とし、`[DEPRECATED] removed in cap.v1.core` コメントを付ける。

**(4) 型なし blob の非推奨化** (`core/site_agent.proto`, `core/skill.proto`):

```protobuf
message WorkOrder {
  // ...
  map<string, string> parameters = 8 [deprecated = true];  // 型なし blob → 非推奨
  SkillInvocation invocation = 15;                          // NEW: 型付きアクション
}
message SkillExecution {
  // ...
  map<string, string> parameters = 5 [deprecated = true];  // 型なし blob → 非推奨
  SkillInvocation invocation = 9;                           // NEW: 型付き実行記録
}
```

### State machine changes

なし。WorkOrder/Intent のライフサイクル(状態遷移)は不変。本 RFC は**ペイロード表現のみ**を変える。

### Wire compatibility

- **Additive**: `WorkOrder.invocation`/`SkillExecution.invocation`/`Intent.domain_intent` は新フィールド。古い実装は未知フィールドを無視し、`parameters` map や legacy core intent arms で動作継続(deprecation 期間中は両方を populate する dual-write を推奨)。
- **No v0 removal**: `DigIntent` 等の core→domain 移行は v0 では「domain 側に正本を追加 + core 側を deprecated」に留める。field tag の reserve は cap.v1.core で削除するときだけ行う。これは ADR-008 の additive-only 方針に従うため。
- forward (古→新) / backward (新→古) いずれも deprecation window 中は string-map fallback で成立。

### Conformance impact

- **Core conformance (Level 1/2)** は分野非依存を維持: `SkillInvocation` と `Intent.domain_intent` が**不透明な `Any` を round-trip**できること(type_url 保持、payload 透過)を検証する新テスト。具体 param 型は検証しない。
- **Construction Domain Pack conformance** が `ExcavateBatchParams`/`DigIntent` 等の typed param を検証(現 Level の延長)。
- **新 Domain Pack** は自分の conformance を同梱(domain-pack-template に追記)。core テストは新分野追加で不変。

### Security impact

- `google.protobuf.Any` は type_url + bytes。**未知 type_url の安全な拒否**(allowlist された domain 型のみ unpack)を conformance/実装ガイドに明記。Any の任意 unpack による型混同を防ぐ。mTLS/RBAC とは直交。

### Performance impact

- `Any` は type_url 文字列 + serialized bytes のオーバヘッド(数十 bytes)。string-map blob の撤去でむしろ縮む場合も。無視できる範囲。

## Alternatives Considered

- **A. 現状維持 (status quo)**: `map<string,string>` + core 直書き intent を続ける。→ 新分野ごとに core 改変が必要(層違反の拡大)、型安全喪失、`SkillInvocation` 設計意図の宙吊り継続。**却下**(本 RFC の motivation そのもの)。
- **B. core の `Intent` oneof に分野型を足し続ける**: 新分野(Mining 等)の intent を core oneof に追加。→ core が全分野の union になり肥大化・分野間結合・compile 時に全分野 proto が必要。多分野でスケールしない。**却下**。
- **C. extensions (proto2 style) で拡張**: proto3 では非推奨/制約あり。`Any` の方が proto3 ネイティブで明示的。**却下**。
- **D. 本 RFC (`Any` 拡張 + core/domain 分離)**: 採用。proto3 ネイティブ、core 不変で新分野追加、型安全、`SkillInvocation` 設計意図を実現。

## Open Questions

著者(@R-Okauchi)の現時点の判断を併記する(レビューで確定):

- **`Intent` と `SkillInvocation` の関係** → **役割分離して両方残す**を推奨。`SkillInvocation` = Site→機体の **WorkOrder 層**の高レベル typed アクション(本 RFC の中核)。`Intent`(`control.proto`) = **機体内 control 層**(planner→executor)の細粒度。両者は granularity が違うので統合しない。`SkillInvocation` 採用と `Intent` の core 分野漏れ是正は独立に進められる。
- **`skill_id` namespacing** → **`"<domain>.<skill>"` を本 RFC で固定**(例 `construction.excavate_batch`)。Domain Pack 名は `cap.v0.domains.<x>` と一致させる。
- **type_url allowlist の広告** → **本 RFC scope 外(将来 RFC)**。`CapabilityManifest` の skill param schema 広告(別議論)と統合して扱うのが筋。当面は実装が allowlist を持つ(security 節参照)。
- **`TrajectoryRequest` の所在** → **core 据え置き**(汎用: 任意の移動協調エージェントが使う)。`DriveIntent.plan` として参照されるが移設不要。

これらの判断のうち breaking なものは無い(全て additive か非 core)。

## Migration Plan

breaking ではない(additive + deprecation)。ADR-008 により、v0 中の削除・rename・wire type 変更は禁止。

1. **v0.(n)**: `SkillInvocation` + `Intent.domain_intent` を追加、`domains/construction/intent.proto` を新設(core の建設 intent と**並存**、core 側は `deprecated`)。`parameters` map を `deprecated` マーク。実装は dual-write(両方 populate)。
2. **v0.(n+1)**: 全リファレンス実装・主要 Domain Pack が typed path に移行。conformance を typed path 必須へ。
3. **cap.v1.core boundary**: 最低 2 minor releases の deprecation window 後、次 major package (`cap.v1.core`) でのみ core の建設固有 intent と `parameters` map を削除し、旧 field tags を `reserved` にする。cap.v0.core では削除しない。

## Rollout Plan

- Reference 実装: `cap-reference` に `SkillInvocation`/`Any` round-trip を、`cap-pangaea`(construction 実装)に `parameters["dig_reach"]` 等 → `construction.ExcavateBatchParams`(Any) への移行を進める。
- Conformance: Core に `SkillInvocation.typed_params` と `Intent.domain_intent` の Any round-trip テスト、Construction Domain Pack に typed param/intent テストを追加。
- Docs: `domain-pack-template.md` に「typed params を `SkillInvocation.typed_params`(Any) で運び、domain intent を `Intent.domain_intent`(Any) で運ぶ」節を追記。

## References

- `domains/construction/skills.proto`(既存の正しい型付き param パターン + 宙吊りの `SkillInvocation` 参照)
- `core/intent.proto`(現状の core 分野漏れ)
- `rfcs/domain-pack-template.md`, README(多分野前提)
- `google.protobuf.Any`(proto3 の型消去拡張機構)
- 類似事例: ROS 2 `action`/`msg` の package 分離、OPC-UA companion specs(コア + 業界別 companion)、AutoSAR の generic + domain profiles
