---
issue: 173
title: 季節ごとの水やり・肥料間隔の自動調整
status: approved
---

## 概要
現在の水やり/肥料/活力剤の間隔は固定日数のみで、冬季の生育鈍化を考慮できない。植物ごとに「冬季（12〜2月）は間隔を延長する」設定を追加し、予定日計算に反映する。

## 変更対象ファイル
- `lib/utils/seasonal_interval_utils.dart`（新規）: 休眠期判定・間隔調整の純粋関数
- `lib/models/plant.dart`: `seasonalAdjustmentEnabled` / `dormantSeasonIntervalMultiplier` フィールド追加
- `lib/services/database_service.dart`: DBバージョン 5→6、`plants` テーブルにカラム追加
- `lib/providers/plant_provider.dart`: `addPlant`/各種 `calculateNext*Date` / `calcNext*DateFromLogs` で季節調整を適用
- `lib/screens/add_plant_screen.dart`: 季節調整の設定UIを追加

## データモデル変更
`Plant` に以下を追加する:
- `seasonalAdjustmentEnabled`（`bool`, デフォルト `false`）: 非nullableのため sentinel 不要、`copyWith` は通常の `??` パターン
- `dormantSeasonIntervalMultiplier`（`double?`）: 冬季の間隔倍率（例: 1.5 = 1.5倍に延長）。sentinel パターンを適用してnullクリア可能にする

## DB変更
- 現在のバージョン: 5 → 新バージョン: 6
- `plants` テーブルに以下カラムを ALTER TABLE で追加（try/catchでべき等化）:
  - `seasonalAdjustmentEnabled INTEGER NOT NULL DEFAULT 0`
  - `dormantSeasonIntervalMultiplier REAL`
- `_onCreate` の `plants` テーブル定義にも同カラムを追加（新規インストール向け）

## UI/UX設計
`add_plant_screen.dart` の「水やり間隔」ListTile の直後に以下を追加する:
- `SwitchListTile`: 「冬季は間隔を延長する（12〜2月）」
- ONの場合のみ表示: 倍率選択（`DropdownButtonFormField<double>` で 1.2倍/1.5倍/2.0倍/3.0倍から選択、デフォルト1.5倍）

`plant_detail_screen.dart` 側は編集画面経由の設定のみで、詳細画面への表示は必須としない（スコープ外）。

## エラーハンドリング
- `dormantSeasonIntervalMultiplier` が null のまま `seasonalAdjustmentEnabled: true` になることを防ぐため、UIでON時は必ずデフォルト値(1.5)を設定する
- 季節調整ロジックは `seasonalAdjustmentEnabled == false` または倍率 null の場合、常に元の間隔をそのまま返す（フェイルセーフ）

## 影響範囲
- 既存の固定間隔ロジックとは後方互換（デフォルトOFFのため既存植物の挙動は変わらない）
- エクスポート/インポート: `Plant.toMap`/`fromMap` に追加するだけで自動的に対応
- 通知（リマインダー）: `calculateNextWateringDate` 等の計算結果を使用しているため自動的に反映される
- `bulkAdjustWateringInterval`/`bulkUpdateWateringInterval`: 季節調整とは独立した基準間隔の一括変更のため変更不要

## テスト観点
- [ ] 季節調整OFFの植物は従来通りの予定日で計算される（回帰なし）
- [ ] 季節調整ONで12月に水やりを記録した場合、次回予定日が基準間隔×倍率で計算される
- [ ] 季節調整ONで夏季（6月等）に水やりを記録した場合、基準間隔のまま計算される（倍率が適用されない）
- [ ] 肥料/活力剤が「水やりN回に1回」モードの場合も、冬季は間隔が延長される
- [ ] 植物編集画面でON/OFF切り替え・倍率変更が保存され、再度開いたときに復元される
- [ ] 既存DB（バージョン5以前）からのアップグレードでエラーが出ない
- [ ] エクスポート→インポートで設定が保持される

## 実装上の注意点
- 季節の判定は「間隔の起算日（最終ログ日または購入日）の月」を基準にする。現在月ではなく起算日基準にすることで、月をまたぐ計算でも一貫性を保つ
- `calculateNextFertilizerDate`/`calculateNextVitalizerDate` の「水やりN回に1回」モードでは `wateringIntervalDays! * remaining` のようにベース間隔を回数分掛けているため、掛け算前の単位間隔に対して季節調整を適用すること（掛け算後に一括調整しない）
- `plant_provider.dart` 内に重複しているロジック（DBアクセス版・ログリスト版）両方に同じ調整を適用する

## レビュー結果
- レビュー日: 2026-07-02
- 結果: 承認
- コメント: アーキテクチャ規約（models非依存、依存方向）に適合。DB変更は累積マイグレーション+try/catchでべき等。デフォルトOFFのため既存挙動への影響なし。
