---
issue: 156
title: その他の植物に水やりのときも複数選択したい
status: approved
---

## 概要

「その他の植物に水やり」ボタンから開くダイアログは現在1植物しか選択できない。
`_UnscheduledWateringDialog` をチェックボックスによる複数選択対応に変更し、
選択した全植物に対して一括でログを記録できるようにする。

## 変更対象ファイル

- `lib/screens/today_watering_screen.dart`
  - `_UnscheduledWateringDialog`（L1541〜）: 単一選択 → 複数選択（チェックボックス）
  - `_showUnscheduledWateringDialog()`（L1120〜）: pop値 `Plant` → `List<Plant>` 対応

## データモデル変更

なし

## DB変更

なし

## UI/UX設計

### 変更前の動作
1. 「その他の植物に水やり」ボタンをタップ
2. `_UnscheduledWateringDialog` が開く（検索フィールド＋植物リスト）
3. 植物を **1件タップ** → ダイアログが閉じる
4. `_LogTypeSelectionDialog` が開く（記録種別選択）
5. 確定 → 選んだ植物1件にログを記録

### 変更後の動作
1. 「その他の植物に水やり」ボタンをタップ
2. `_UnscheduledWateringDialog` が開く（検索フィールド＋植物リスト、**チェックボックス**）
3. 植物を **複数チェック**（1件でも可）
4. 「記録する（N件）」ボタン（ダイアログ下部）をタップ → ダイアログが閉じる
5. `_LogTypeSelectionDialog` が開く（既存のまま、種別選択）
6. 確定 → 選んだ**全植物**に同じ種別のログを一括記録

### ウィジェット変更詳細

`_UnscheduledWateringDialog` の変更点:
- State に `final Set<String> _selectedIds = {}` を追加
- `ListView` の各アイテムを `ListTile`（onTap でpop）→ `CheckboxListTile` に変更
  - `onChanged` で `_selectedIds` を更新、`setState` で再描画
- ダイアログの `actions` に「キャンセル」と「記録する（N件）」ボタンを追加
  - 0件選択中は「記録する」ボタンを disabled にする
  - タップで `List<Plant>` をポップ
- ダイアログの `title` は「水やり記録をつける」のまま

`_showUnscheduledWateringDialog()` の変更点:
- `showDialog<Plant>` → `showDialog<List<Plant>>` に変更
- 返却値が `List<Plant>` になるため、ループで各植物に `_recordLog()` を呼ぶ
- 成功メッセージを「選択した N 件に <種別> を記録しました」形式に統一

参考にすべき既存実装:
- 一括記録ボタンの FAB 部分（L428〜）: `_selectedPlantIds` + `_bulkLog()` の複数選択パターン
- `_LogTypeSelectionDialog`（L1464〜）: チェックボックスリストダイアログの実装例

## エラーハンドリング

- 0件選択での確定ボタンは disabled にするため、空リストが渡ることはない
- `unscheduledPlants` が空の場合は既存のスナックバー表示（変更なし）

## 影響範囲

- バックアップ/エクスポート: 影響なし（UI変更のみ）
- 通知: 影響なし
- 他画面: 影響なし

## テスト観点

- [ ] 「その他の植物に水やり」ボタンをタップするとダイアログが開く
- [ ] 植物リストにチェックボックスが表示される
- [ ] 検索フィールドで絞り込んでもチェック状態が保持される
- [ ] 1件選択 → 「記録する（1件）」ボタンが活性になる
- [ ] 複数件選択 → 「記録する（N件）」ボタンが件数を反映する
- [ ] 0件選択時は「記録する」ボタンが disabled になる
- [ ] 「記録する」タップ後に `_LogTypeSelectionDialog` が開く
- [ ] 水やり・肥料・活力剤を選択して確定すると、選択した全植物にログが記録される
- [ ] 記録後のスナックバーに件数と種別が表示される
- [ ] 「キャンセル」でダイアログを閉じてもメインリストに変化がない

## レビュー結果
- レビュー日: 2026-06-29
- 結果: 承認
- コメント: アーキテクチャ規約・コーディング規約・エッジケースすべて問題なし。既存の一括選択パターンを踏襲しており整合性も高い。

## 実装上の注意点

- `_UnscheduledWateringDialog` は `StatefulWidget` のため State で `_selectedIds` を管理する
- チェックボックスの状態は検索フィルタリングをまたいで保持する（フィルタは表示のみ変更）
- `_showUnscheduledWateringDialog()` の返却値型を `Plant?` → `List<Plant>?` に変更するため、
  呼び出し後の null チェックを忘れないこと
- 成功メッセージ: 1件は「○○に水やりを記録しました」の代わりに
  「N件の植物に水やりを記録しました」と統一するほうが自然（N=1含む）
