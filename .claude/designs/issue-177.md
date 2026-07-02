---
issue: 177
title: AI写真による病害虫診断
status: approved
---

## 概要
ノートに添付した植物の写真をAnthropic Claude API（vision）に送信し、病気・害虫の可能性と対処法を診断する機能を追加する。診断結果はノート本文に追記して保存できる。

## 変更対象ファイル
- `lib/models/app_settings.dart`: `aiApiKey` を追加
- `lib/providers/settings_provider.dart`: `updateAiApiKey()` を追加
- `lib/services/ai_service.dart`（新規）: Anthropic Messages API（vision）クライアント
- `lib/screens/add_edit_note_screen.dart`: 添付画像から「AI診断」を実行する導線を追加
- `lib/screens/settings_screen.dart`: AI診断のAPIキー設定UIを追加

## データモデル変更
`AppSettings.aiApiKey`（`String`, デフォルト `''`）を追加。既存の `natureRemoToken` 等と同様の手入力方式。

## DB変更
なし（`AppSettings` は SharedPreferences 保存のため DB マイグレーション不要）。

## UI/UX設計
- 設定画面に「AI診断」セクションを追加し、Anthropic APIキーを入力するobscuredフィールドを設置（IoT連携のトークン入力と同じUIパターン）
- `add_edit_note_screen.dart` の画像セクションヘッダーに「AI診断」ボタン（`TextButton.icon`）を追加。画像が1枚もない場合は非表示
- タップ時、APIキー未設定なら「設定画面でAPIキーを登録してください」とSnackBar表示して終了
- APIキー設定済みなら最初の画像を送信し、ローディングダイアログ→結果ダイアログ（診断結果テキスト＋「内容欄に追記」ボタン）を表示
- 「内容欄に追記」を押すと `_contentController` に診断結果を追記する（ノート保存は既存の保存フローに委譲）

## エラーハンドリング
- APIキー未設定、通信失敗、タイムアウト（30秒）、画像読み込み失敗はすべてダイアログ/SnackBarでエラーメッセージを表示し、アプリを継続動作させる
- `stop_reason == "refusal"` の場合は「診断できませんでした」とユーザーに分かるメッセージを表示する

## 影響範囲
- 既存のノート保存フロー・エクスポート/インポートには影響しない（診断結果は通常のノート本文として保存されるため）
- APIコストはユーザー自身のAPIキーに帰属し、アプリ側では課金処理を行わない

## テスト観点
- [ ] 設定画面でAPIキーを登録・削除できる
- [ ] 画像添付済みノートで「AI診断」ボタンが表示され、タップで診断が実行される
- [ ] 診断結果を「内容欄に追記」でノート本文に反映できる
- [ ] APIキー未設定時に案内メッセージが表示される
- [ ] 通信エラー時にアプリがクラッシュせずエラーメッセージが表示される
- [ ] 画像が0枚のノートでは「AI診断」ボタンが表示されない

## 実装上の注意点
- CLAUDE.mdの依存方向規約に従い、AiServiceの呼び出しはscreens→services直接ではなく、実質的にscreens内の非同期処理から直接serviceを呼ぶ形になるが、既存の `export_service.dart` 等と同様にUIイベントハンドラから直接サービスを呼ぶ既存パターンに準拠する
- モデルは `claude-opus-4-8` を使用する
- APIキーは既存のIoTトークン同様、平文でSharedPreferencesに保存する（既存実装と同じ信頼モデル）
