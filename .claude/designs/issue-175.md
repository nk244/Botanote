---
issue: 175
title: 植え替え・剪定・葉水などケアタイプの拡張記録
status: approved
---

## 概要
水やり/肥料/活力剤の3種別に加え、植え替え・剪定・葉水・掃除を記録できるようにする。これらは間隔設定・スケジュール管理を持たない「記録専用」のケアタイプとし、既存の水やりスケジュール機能（今日の水やり画面）には影響を与えない。

## 変更対象ファイル
- `lib/models/log_entry.dart`: `LogType` に `repotting`/`pruning`/`misting`/`cleaning` を追加（実施済み）
- `lib/models/daily_log_status.dart`: 新タイプはスケジュール対象外として exhaustive switch に default 分岐を追加
- `lib/providers/plant_provider.dart`: 汎用ケア記録メソッド `recordCareLog` を追加
- `lib/screens/plant_detail_screen.dart`: ログタブで新タイプの表示・記録UIを追加
- `lib/screens/today_watering_screen.dart`: exhaustive switch に default 分岐を追加（新タイプは表示対象外のため影響なし）

## データモデル変更
`LogEntry` 自体の変更は不要（`type` は既に `TEXT`（`type.name`）で保存されており、新しい enum 値もそのまま保存・復元できる）。

## DB変更
なし。`logs` テーブルの `type` カラムは既存の文字列カラムのため、enum 値の追加だけで対応可能。

## UI/UX設計
- `plant_detail_screen.dart` の「ログ」タブ（`_buildUnifiedLogTab`）の先頭に `OutlinedButton.icon`「その他のケアを記録」を配置する（FABは使わない。Issue #69/#95 でFAB・登録ボタンが「不要」として明示的に削除された経緯があるため、タブ内の通常ボタンとして配置する）
- ボタン押下で `AlertDialog` を表示: ケアタイプの選択（`ChoiceChip` 4種）、日付選択（`showDatePicker`、デフォルト今日）、メモ入力（任意）
- 保存後、`recordCareLog` を呼び出し、ログタブを再読み込みする
- 新タイプは既存の統合ログリストに時系列でマージ表示される（アイコン・ラベルは種別ごとに用意）
- 「今日の水やり」画面には新タイプを表示しない（記録専用のためスケジュール計算対象外）

## エラーハンドリング
- 記録保存時の DB エラーは既存の `recordWatering` 等と同様に呼び出し元で try/catch し SnackBar 表示する
- `DailyLogStatus`/`today_watering_screen` の exhaustive switch は新タイプを default 分岐で無視することで、コンパイルエラー・実行時例外を防ぐ

## 影響範囲
- 今日の水やり画面: 新タイプはスケジュール算出・表示に一切関与しないため影響なし
- エクスポート/インポート: `LogEntry.toMap`/`fromMap` は enum 名の文字列化のため自動的に対応（バックアップの互換性も維持: 旧バージョンアプリで新タイプの含まれるバックアップをインポートすると `LogType.values.firstWhere` が例外を投げる可能性があるため、将来的な後方非互換に注意 — 本Issueのスコープでは新規追加のみとし対応不要）
- 通知（リマインダー）: 新タイプは間隔を持たないため通知対象外

## テスト観点
- [ ] 植物詳細画面のログタブから「その他のケアを記録」で4種類それぞれ記録できる
- [ ] 記録した内容がログタブの統合リストに正しいアイコン・ラベルで表示される
- [ ] 記録した日のログをまとめて削除できる（既存の `_deleteLogsForDay` が新タイプにも対応していることを確認）
- [ ] 今日の水やり画面の表示・予定計算に新タイプが影響しないこと（回帰なし）
- [ ] `flutter analyze` で non_exhaustive_switch エラーが出ないこと
- [ ] エクスポート→インポートで新タイプのログが保持される

## 実装上の注意点
- CLAUDE.md の依存方向規約（screens→providers→services→models）を遵守し、新規記録処理は `PlantProvider` 経由で行う
- Issue #69「植物画面の右下に表示される水やりボタンは不要」、Issue #95「植物画面に水やり/肥料/活力剤の登録機能は必要ない」の経緯を踏まえ、FABや画像オーバーレイ上のクイックボタンではなく、ログタブ内の明示的なボタンとして配置する
