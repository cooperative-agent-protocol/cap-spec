<!--
SPDX-License-Identifier: Apache-2.0
Copyright 2026 CAP Authors
-->

# CAP RFCs — Request for Comments

> CAP (Cooperative Agent Protocol) の重要な変更を提案・議論・記録するためのプロセス。

## When to write an RFC

通常の bug fix / doc tweak / refactor は GitHub Pull Request だけで OK。RFC が必要なのは
以下のような **意味論的にコミュニティへの影響がある変更**:

- 新しい message 型・field・enum value の追加 (proto schema 拡張)
- 既存 field の deprecation / removal
- 新しい state machine 遷移
- transport profile の追加 (gRPC / MQTT 以外)
- security model の変更
- conformance Level の追加・変更
- 新しい **Domain Pack** の提案 (Agriculture / Mining / Forestry / Intralogistics 等)
- governance model の変更
- breaking changes (wire-format incompatible な変更)
- 外部 standards body との liaison 関係の追加

## RFC lifecycle

```
                ┌────────────────────┐
                │  Draft (in PR)     │  ← author opens PR with rfcs/RFC-NNNN-*.md
                └─────────┬──────────┘
                          │
                  community discussion
                  (GitHub Discussions linked from PR)
                          │
                          ▼
                ┌────────────────────┐
                │  Proposed (merged) │  ← maintainer merges with `Status: Proposed`
                └─────────┬──────────┘
                          │
                  reference implementation lands
                          │
                          ▼
                ┌────────────────────┐
                │  Accepted          │  ← maintainer updates `Status: Accepted`
                └─────────┬──────────┘
                          │
                shipped in a release tag
                          │
                          ▼
                ┌────────────────────┐
                │  Final / Shipped   │
                └────────────────────┘

Other terminal statuses:
  Rejected   — community / maintainer consensus against
  Withdrawn  — author withdraws
  Superseded — replaced by a later RFC (link to the successor)
```

## How to write an RFC

1. 最新の RFC 番号を確認 (`ls cap-spec/rfcs/` で max number を見つけて +1)
2. 新規ファイル `cap-spec/rfcs/RFC-NNNN-short-title.md` を作る (template は
   [RFC-0000-template.md](./RFC-0000-template.md) を copy)
3. GitHub Discussion を開いて RFC PR と相互リンク
4. PR で community feedback を集める
5. maintainer が `Status: Proposed` で merge
6. 参照実装 (cap-reference 内) が landed したら `Status: Accepted` に更新
7. release tag に含まれたら `Status: Final` に更新

## Domain Pack RFCs

新しい Domain Pack (例: Agriculture, Mining, Forestry, Intralogistics) を CAP に追加する
場合は、通常の RFC とは別に **Domain Pack 提案テンプレート** を使う。詳細は
[domain-pack-template.md](./domain-pack-template.md) を参照。

Domain Pack RFC では以下を必須項目として明記する:

- ドメインの定義と既存 standards との関係 (ISO TC23 / TC82 / VDA 5050 等)
- Skill 名前空間の prefix (`agriculture.*`, `mining.*` 等)
- 必要な追加 message 型 (skills / zones / equipment)
- 既存 Core API との互換性検証
- 適合性テストの追加 (cap-conformance/domains/<name>/)
- 提案者がリファレンス実装を提供できるか (人手リソース commit)
- 標準化アライアンス候補 (どの standards body と liaison を取るか)

## Naming convention

```
RFC-0000-template.md            (template, never assigned)
RFC-0001-<kebab-case-title>.md  (first real RFC)
RFC-0002-<kebab-case-title>.md
...
```

Domain Pack RFC は通し番号で OK だが、タイトルで明示:
```
RFC-0042-domain-pack-agriculture.md
```

## Relationship to ADRs

| RFC | ADR |
|---|---|
| 変更の **提案・議論** プロセス | 変更の **決定・記録** |
| Discussion focus | Decision focus |
| 1 RFC が複数 ADR を生むこともある | 1 ADR が独立に書かれることもある |
| `cap-spec/rfcs/` 配下 | `cap-spec/docs/adr/` 配下 |

簡単な原則: **議論用は RFC, 確定事項の記録は ADR**。Accepted RFC のうち、CAP の
fundamental な構造に関わるものは ADR に promote する。
