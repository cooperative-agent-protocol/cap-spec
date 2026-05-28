<!--
SPDX-License-Identifier: Apache-2.0
Copyright 2026 CAP Authors
-->

# Governance

## Versioning Policy

CAP はセマンティックバージョニング（SemVer）に従う。

- **v0.x.y**: インキュベーション段階。破壊的変更が入りうる。
- **v1.0.0**: 安定版。破壊的変更は次のメジャーバージョンまで行わない。

### Proto バージョニング

- パッケージ名にバージョンを含める: `cap.v0`, `cap.v1`
- 新バージョンは新パッケージとして追加し、旧バージョンは deprecation 期間を経て削除する
- `buf breaking` による破壊的変更検出を CI で必須とする

## Branch Policy

| Branch | Purpose |
|--------|---------|
| `main` | 最新の安定版。直接 push は禁止。 |
| `dev` | 開発ブランチ。feature ブランチからの PR をマージする。 |
| `feature/*` | 機能開発。`dev` からブランチし、PR で `dev` にマージ。 |
| `release/v*` | リリース準備。`dev` からブランチし、テスト後 `main` にマージ。 |

## Decision Process

- 設計上の重要な決定は **ADR (Architecture Decision Record)** として `docs/adr/` に記録する
- ADR の追加・変更は PR を通じてレビューを受ける
- プロトコルの破壊的変更は RFC プロセス（将来導入予定）を経る

## Code of Conduct

全コントリビュータは相互に敬意を持ち、建設的な議論を行うこと。
