<!--
SPDX-License-Identifier: Apache-2.0
Copyright 2026 CAP Authors
-->

# Contributing to CAP (Cooperative Agent Protocol)

CAP への貢献に感謝します。本プロジェクトは Apache 2.0 + DCO (Developer Certificate
of Origin) で運営されており、すべての commit に `Signed-off-by:` trailer が必要です
(下記 [Developer Certificate of Origin](#developer-certificate-of-origin-dco) 参照)。

## How to Contribute

### Proto 定義の変更 (小さい)

非破壊的な field 追加・コメント修正・enum value 追加など、wire-format に影響しない
変更:

1. `feature/*` ブランチを作成
2. `proto/cap/v0/core/` または `proto/cap/v0/domains/<domain>/` 配下を編集
3. `make lint` でリントを通す
4. `make breaking` で破壊的変更がないか確認
5. PR を作成し、`Signed-off-by:` 付きの commit でレビューを受ける

### RFC が必要な変更 (大きい)

以下の場合は事前に RFC を書く必要があります (詳細は [`rfcs/README.md`](rfcs/README.md)):

- 新しい message 型 / field を **意味論的に大きく** 追加する
- field の deprecation / removal
- state machine の遷移を追加・変更
- transport profile の追加
- security model の変更
- conformance Level の追加・変更
- **新しい Domain Pack の提案** ([`rfcs/domain-pack-template.md`](rfcs/domain-pack-template.md) を使う)
- breaking change (`cap.vN` → `cap.vN+1`)

### ADR の追加

1. `docs/adr/` に新しい ADR ファイルを作成 (番号は連番、既存 ADR-001..011 の続き)
2. テンプレート: Status / Context / Decision / Consequences / References
3. RFC が accepted されていることが前提のことが多い
4. PR を作成

### 新しい Domain Pack の Contribution

CAP は Core (universal) + Domain Pack (domain-specific) の二層構造です ([ADR-011](docs/adr/011-domain-pack-architecture.md))。
新しい Domain Pack (Agriculture / Mining / Forestry / Intralogistics / その他) を提案する
には:

1. [`rfcs/domain-pack-template.md`](rfcs/domain-pack-template.md) を copy して
   `rfcs/RFC-NNNN-domain-pack-<name>.md` を作成
2. GitHub Discussion で community feedback を受ける
3. PR を merge してもらう (Status: Proposed)
4. `proto/cap/v0/domains/<name>/` 配下に skills.proto / zones.proto / equipment.proto
   を実装
5. `cap-conformance/domains/<name>/` 配下に適合性テストを追加
6. リファレンス実装を `cap-reference` 配下 (または別 repo) で提供

### サンプルペイロードの追加

1. `examples/` 配下に適切なディレクトリを作成
2. JSON ファイルは proto 定義と整合すること
3. フィールド名は camelCase (protobuf JSON mapping 標準)

## Development Setup

### Prerequisites

- [buf CLI](https://buf.build/docs/installation)
- Protocol Buffers compiler (`protoc`) — buf 経由で自動管理される

### Commands

```bash
cd cap-spec/
make lint      # proto ファイルのリント
make gen       # コード生成 (Python, C++, TypeScript)
make breaking  # 破壊的変更の検出
make clean     # 生成コードの削除
```

## Style Guide

### Proto

- Core パッケージ名: `cap.v0.core` (e.g. `cap.v0.core.machine_agent`)
- Domain Pack パッケージ名: `cap.v0.domains.<domain>` (e.g. `cap.v0.domains.construction.skills`)
- Enum 値: `ENUM_NAME_VALUE` 形式 (例: `MACHINE_TYPE_EXCAVATOR`)
- Enum の先頭値: `_UNSPECIFIED = 0`
- メッセージ名: PascalCase
- フィールド名: snake_case
- コメント: `//` で各メッセージ・フィールドの意味を記述
- Skill 名: `<domain>.<skill_name>` (e.g. `construction.excavate_batch`)

### JSON Examples

- フィールド名: camelCase (protobuf JSON mapping 標準)
- Timestamp: RFC 3339 形式 (例: `2026-03-19T09:00:00Z`)

### SPDX headers

すべてのソースファイル冒頭に SPDX-License-Identifier ヘッダーが必須:

```
// SPDX-License-Identifier: Apache-2.0
// Copyright YYYY CAP Authors
```

CI で `reuse lint` を実行しています。

## Developer Certificate of Origin (DCO)

CAP は [Developer Certificate of Origin](https://developercertificate.org/)
に従って運営されています。全 commit に `Signed-off-by:` trailer が必要です。

```bash
git commit -s -m "Your commit message"
```

これにより、commit message 末尾に以下が自動付与されます:

```
Signed-off-by: Your Name <your.email@example.com>
```

`Signed-off-by:` を付けることで、貢献者は DCO 1.1 のすべての条項を確認したことを
表明します:

- (a) 貢献物は貢献者自身が作成したものであり、Apache License 2.0 の下で提出する権利
  を有する。
- (b) または、貢献物は既知の適切な OSS ライセンスに基づくものであり、その元のライ
  センスに従って Apache 2.0 のもとで提出する権利を有する。
- (c) (a) または (b) と同等の認識を持つ他者から直接受け取った貢献物であり、ライセン
  ス条項に修正を加えていない。
- (d) 貢献物は公開記録として永続的に保持されることに同意し、含まれる個人情報
  (氏名、メールアドレス等) もそのライセンス・プロジェクト規範に従って配布される
  ことに同意する。

CAP は **CLA (Contributor License Agreement) を採用しません**。DCO は法的に十分で、
contributor 摩擦が低く、将来の foundation 寄贈にも対応可能です。

DCO 違反 (`Signed-off-by:` のない commit を含む PR) は merge 前に修正が必要です。
過去の commit に sign-off を追加する方法:

```bash
git rebase --signoff main
git push --force-with-lease
```

## License

貢献は Apache License 2.0 の下で行われます。
