<!--
SPDX-License-Identifier: Apache-2.0
Copyright 2026 CAP Authors
-->

# Domain Pack Proposal Template

> 新しい Domain Pack を CAP に追加する際の必須記述事項。通常 RFC の構成に加えて、本 template
> の項目をすべて埋めること。

CAP は domain-agnostic な Core 仕様 (Manifest / WorkOrder / Heartbeat / Dialogue / ALO /
Safety Supervisor) + ドメイン固有の **Domain Pack** (skills / zones / equipment) で構成
される。v0.x のリファレンス Domain Pack は Construction。Agriculture / Mining /
Forestry / Intralogistics 等は本テンプレートに沿って提案する。

## RFC header

通常の [RFC-0000-template.md](./RFC-0000-template.md) header をそのまま埋める。Title は
`Domain Pack: <Name>` 形式 (例: `Domain Pack: Agriculture`)。

## Domain Pack metadata

| Field | Value |
|---|---|
| Pack name | `agriculture` (lowercase, ASCII, kebab-case 可) |
| Skill namespace prefix | `agriculture.*` (e.g. `agriculture.plow`) |
| Proto namespace | `cap.v0.domains.agriculture.*` |
| Maintainer(s) | 名前 + GitHub handle + 連絡先 + 所属 |
| License | Apache-2.0 (CAP-Core と整合させる) |
| Reference implementation | URL or repo path |
| Target conformance Level | Core L1 + Pack L1 / Core L2 + Pack L2 / etc. |

## Domain definition

### Scope

このドメインで CAP プロトコルが coordinate する対象を明確に。

- 対象機械の種類 (例: tractor, harvester, sprayer, seeder)
- 対象作業 (例: tillage, planting, application, harvesting, transport)
- 対象環境 (例: open-field, orchard, paddy)
- 対象でないもの (out of scope)

### 関連 standards

このドメインの既存 standards との位置関係:

| Standard | Relation |
|---|---|
| ISO TC23 (Agricultural tractors) | アライアンス対象 |
| ISO 11783 (ISOBUS) | wire-level interop / field mapping を意図 |
| AEF (Agricultural Industry Electronics Foundation) | 認証連携を将来検討 |
| (other) | … |

### 既存実装との関係

そのドメインで使われている既存システム (proprietary な fleet management、OEM tooling
等) との関係。CAP がそれを replace するのか、それらの上の layer なのか。

## Proto definitions

### `skills.proto`

```protobuf
// cap-spec/proto/cap/v0/domains/agriculture/skills.proto
syntax = "proto3";
package cap.v0.domains.agriculture;

// Skill definitions specific to agricultural operations.
message PlowSkill { /* … */ }
message PlantSkill { /* … */ }
// …
```

### `zones.proto`

```protobuf
// cap-spec/proto/cap/v0/domains/agriculture/zones.proto
package cap.v0.domains.agriculture;

// Zone types relevant to agriculture (field, headland, refill_point, …).
```

### `equipment.proto`

```protobuf
// cap-spec/proto/cap/v0/domains/agriculture/equipment.proto
package cap.v0.domains.agriculture;

// Equipment-specific attributes (tractor, harvester, sprayer, …).
```

### Core への追加要望 (もしあれば)

Domain Pack 設計時に「Core にこの field が必要」となった場合、それは **別 RFC** として
切り出すこと。Domain Pack RFC 内で Core 拡張を同時提案するのは推奨しない (議論の粒度が
混ざる)。

## Conformance test suite

`cap-conformance/domains/<name>/` 配下に test 群を提供:

- skill 適合性テスト (各 skill の precondition / postcondition / effects 検証)
- zone 型適合性テスト
- equipment manifest 適合性テスト
- domain-specific failure label 検証 (該当する場合)

Core conformance Level 1/2/3 はそのまま使えるはず。Domain Pack 適合性は **opt-in**:

```bash
pytest cap-conformance --target grpc://localhost:50051 --domain agriculture
```

## Reference implementation commitment

Domain Pack RFC は **リファレンス実装の提供者** が必須:

- Pack maintainer 名と連絡先
- 期待される最初の release timeline
- 継続メンテナンス commitment (最低 12 ヶ月)
- 緊急時 (security issue 等) の対応 SLA

リファレンス実装は CAP の reference SDK (cap-reference) に同居させるか、別 repo
(cooperative-agent-protocol/cap-domain-<name>) を作るか、Domain Pack RFC 内で決める。

## Adoption path

このドメインで CAP を採用する OEM / integrator のターゲット候補:

| Org | Status |
|---|---|
| Kubota | (e.g. brief 送付済み / interest expressed / committed) |
| Yanmar | … |
| John Deere | … |

Pack RFC が accepted されるためには **少なくとも 1 social proof** が望ましい (実装者
コミット / OEM interest / 学術プロジェクト等)。

## Standards body outreach plan

| Body | Approach | Timeline |
|---|---|---|
| ISO TC23 | liaison inquiry via JISC | M+3 |
| AEF | informal contact | M+6 |
| (regional) | … | … |

## Risks

- 既存 Domain (Construction) との semantic 衝突 (例: 同じ skill 名を別意味で使う)
- 既存 ISO / industry standards との conflict
- 法令対応 (農薬散布 / 食品安全 / 環境)

## Naming guidelines

新しい Domain Pack を提案する際、名前は以下のガイドラインに従う:

- ASCII lowercase / kebab-case
- 業界で広く認知された短い英単語
- 既存 Domain Pack と衝突しない (`construction`, `agriculture`, `mining`,
  `forestry`, `intralogistics`)
- Sub-domain は dot で区切る (e.g. `agriculture.orchard`, `mining.surface`,
  `mining.underground`) — ただし sub-domain 設計は別 RFC で確定する

## Open questions

domain 別の特殊事情を、Pack RFC 内で必ず議論しておく:

- 規制対応 (safety / environment / data privacy 等)
- 通信環境 (low-bandwidth field 環境での MQTT 制約等)
- 地域差 (北米 / EU / 日本 / 中南米でユースケースが異なる場合の position)
- 既存標準との dual-stack (例: ISOBUS と CAP を併用する移行期間)
