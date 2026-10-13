<!--
SPDX-License-Identifier: Apache-2.0
Copyright 2026 CAP Authors
-->

# RFC-0002: Fleet member pose uncertainty and heading reference

| Field | Value |
|---|---|
| RFC | 0002 |
| Title | Fleet member pose uncertainty and heading reference |
| Author(s) | R-Okauchi (`@R-Okauchi`) |
| Status | Proposed |
| Created | 2026-10-14 |
| Last Updated | 2026-10-14 |
| Related ADR | ADR-008 (versioning: v0 is additive-only) |
| Related Discussion | (TBD) |
| Reference Implementation | `proto/cap/v0/core/world_model.proto` (`FleetMemberState.position_sigma_xy_m`, `FleetMemberState.heading_reference`, `enum HeadingReference`); Core conformance `cap-conformance/tests/test_fleet_member_state.py`. A reference construction implementation relaying both and sizing its peer hazards by them: in progress. |

## Summary

`WorldDelta.fleet` の `FleetMemberState` は他機の位置 (`pose`) を運ぶが、その位置がどれだけ確かか、`pose.yaw` が
どの体の向きか (走行する体か、それと独立に旋回する上部か) を運ばない。受け手は他機の不確かさを自分の保守的な上限で
仮定し、走行の向きを知らないものとして扱うしかない。本 RFC は `FleetMemberState` に
(1) `optional double position_sigma_xy_m` (送り手の推定の水平 1σ) と (2) `HeadingReference heading_reference`
(`BASE` = 走行する体 / `UPPER` = 旋回する上部) を **追加のみ** で足す (ADR-008)。付いていなければ受け手は今どおり
自分の上限と「向き不明」を仮定する。

## Motivation

- 他機の占める範囲を不確かさで広げる受け手 (経路計画・衝突の監視) は、σ が分からなければ自分の上限を使う。実装例
  (建設のリファレンス実装) では上限 0.30 m を 3σ で広げ、2 機合わせて約 0.9–1.3 m の幅になる。実際の RTK の推定は
  0.02–0.05 m で、幅は約 0.2 m で足りる。過大な幅は、積込のように 2 機が数 m で寄り添う作業の配置の候補を塞ぐ
  (積込の位置の窓が 8.5–9.2 m に押し込まれ、候補が尽きて作業が止まった)。
- 旋回する上部を持つ機体 (油圧ショベル、旋回する荷台のクローラキャリア、砲塔を持つ機体) の位置は、上部の向きでしか
  分からないことがある (上部に載った GNSS コンパス)。そのとき `pose.yaw` は走行の向きではない。受け手が向きの種類を
  知らなければ、走行する体を向きの分からない円で囲むしかない。向きが走行する体のものと分かれば、向きのある矩形で
  囲める。
- 送り手はこれらを既に知っている (自分の推定の共分散、自分の向きがどの体のものか)。運ぶ欄が無いだけである。

## Background

- `FleetMemberState` (`core/world_model.proto`) は Site が各機の報告から作り、`WorldDelta.fleet` で他機へ流す。
  各機の報告 (heartbeat など) に何を載せるかは実装の自由で、本 RFC は流す側の欄だけを定める。
- ADR-008: v0 は追加のみ。既存の欄の意味・番号は変えない。

## Detailed Design

### Proto schema changes

```protobuf
// Before
message FleetMemberState {
  string machine_id = 1;
  MachineType machine_type = 2;
  Pose3D pose = 3;
  double speed_mps = 4;
  double heading_rate_rad_s = 5;
  string active_command_id = 6;
  MachinePhase phase = 7;
  google.protobuf.Timestamp pose_at = 8;
}

// After
enum HeadingReference {
  HEADING_REFERENCE_UNSPECIFIED = 0;  // not reported: the travel direction is not known from pose.yaw
  HEADING_REFERENCE_BASE = 1;         // the travelling body's heading (its tracks or wheels)
  HEADING_REFERENCE_UPPER = 2;        // an upper structure's heading, slewing independently of the travelling body
}

message FleetMemberState {
  // ... 1-8 unchanged ...
  optional double position_sigma_xy_m = 9;   // NEW: 1-sigma horizontal uncertainty of pose [m], sqrt(var_x + var_y)
  HeadingReference heading_reference = 10;    // NEW
}
```

意味:

- `position_sigma_xy_m`: 送り手が自分の推定について言う水平の 1σ (`sqrt(var_x + var_y)`)。**付いていない (presence
  なし) は「報告なし」で 0 ではない**: 受け手は自分の上限を仮定する。受け手は下限で切ってよい (0 や極端に小さい値を
  そのまま信じない)。有限でない値・負の値は「報告なし」と同じに扱う。Site は自分の受け入れの上限 (中継してよい
  不確かさ) を超える報告を流さなくてよい。
- `heading_reference`: `pose.yaw` がどの体の向きか。`UNSPECIFIED` (既定値、古い送り手) は今どおり「走行の向きは
  分からない」。`BASE` なら `pose.yaw` は走行する体の向き (向きのある外形で囲める)。`UPPER` なら上部の向きで、走行の
  向きは分からない (上部の外形はその向きで、走行する体は円で囲む)。
- 位置 (`pose` の x y z) はどちらの場合も同じ点の意味 (各実装の約束のまま)。本 RFC は位置の基準点を変えない。

### State machine changes

なし。

### Wire compatibility

追加のみ (field 9・10 は未使用だった番号)。古い受け手は未知の欄として読み飛ばす。古い送り手は欄を付けない: 新しい
受け手は `position_sigma_xy_m` の presence が無いことと `HEADING_REFERENCE_UNSPECIFIED` から「報告なし」と分かり、
今までどおり振る舞う。`buf breaking` (FILE) は変更なしで通る。

### Conformance impact

Core 適合に追加 (`cap-conformance/tests/test_fleet_member_state.py`):

- 欄が付いていない `FleetMemberState` は `HasField("position_sigma_xy_m")` が偽、`heading_reference` が
  `UNSPECIFIED` (受け手は 0 m と読まない)。
- 0.0 を明示した σ は presence ありとして往復する (「報告なし」と区別できる)。
- 新しい欄を持つメッセージは、欄を知らない古い型としても読め (未知の欄)、再び新しい型で読むと値が残る。

### Security impact

送り手が小さすぎる σ を言えば、受け手の安全の余裕が減る。受け手は下限で切り、Site は報告の上限を超えるものを流さない
(上の意味)。σ は送り手の自己申告であり、受け手の安全の判断をそれだけに預けない。

### Performance impact

1 機あたり最大 11 バイト (double + varint の enum)。無視できる。

## Alternatives Considered

- **共分散を丸ごと運ぶ (6×6 や 2×2)**: 受け手が使うのは水平の大きさだけで、向き付きの楕円を扱う受け手はまだ無い。
  必要になれば別の欄として足せる (本 RFC の欄と両立する)。
- **向きの種類を `MachinePhase` や `machine_type` から推す**: 同じ機体でも、位置の出どころ (上部のコンパスか走行体の
  推定か) で変わる。機体の種類からは決まらない。
- **`Pose3D` に足す**: `Pose3D` は位置一般の型で、多くのメッセージが使う。不確かさと向きの種類は「他機として流す位置」
  の性質なので `FleetMemberState` に置く。

## Open Questions

- 向き (`pose.yaw`) の不確かさも運ぶか。今の受け手は位置の σ だけを使う。
- 速度 (`speed_mps`) の不確かさ。

## Migration Plan

追加のみなので移行は不要。送り手は対応したら欄を付け、受け手は付いていれば使う。

## Rollout Plan

1. proto と生成コード、Core 適合の試験 (本 RFC)。
2. リファレンス実装: Site が中継で両方の欄を付け、機体が他機の外形を σ と向きの種類で作る。
3. 次の v0 のリリースタグに含める。

## References

- ADR-008: Versioning and deprecation policy (`docs/adr/008-versioning.md`)
- `proto/cap/v0/core/world_model.proto` (`FleetMemberState`, `WorldDelta.fleet`)
