---
issue: 178
title: AI写真による植物名・品種の自動同定
status: approved
---

## 概要
植物登録画面で写真を撮ると、Anthropic Claude API（vision）を用いて植物名・品種名の候補を自動入力する機能を追加する。

## 変更対象ファイル
- `lib/models/app_settings.dart`: `aiApiKey` を追加（#177と同一の設定項目。#177は別ブランチのため本Issueでも独立して追加する）
- `lib/providers/settings_provider.dart`: `updateAiApiKey()` を追加
- `lib/services/ai_service.dart`（新規）: Anthropic Messages API（vision）クライアント。`identifyPlant()` を実装
- `lib/screens/add_plant_screen.dart`: 画像選択後に「AIで植物名を推定」導線を追加
- `lib/screens/settings_screen.dart`: AI診断・同定共通のAPIキー設定UIを追加

## データモデル変更
`AppSettings.aiApiKey`（`String`, デフォルト `''`）。#177 と同じキーを共有する想定（両PRがマージされる際は同一フィールドとして自然に統合される）。

## DB変更
なし。

## UI/UX設計
- `add_plant_screen.dart` の画像プレビュー領域下に「AIで植物名を推定」ボタンを追加。画像未選択時は非表示
- タップ時、APIキー未設定なら案内SnackBarを表示
- 設定済みなら画像を送信し、ローディング表示→結果を確認ダイアログで表示（推定植物名・品種名・信頼度）
- 「反映」を押すと植物名・品種名の入力欄に候補値を反映する（ユーザーは反映後も自由に編集可能）

## エラーハンドリング
- APIキー未設定・通信失敗・タイムアウト・JSON解析失敗はすべてダイアログ/SnackBarでエラー表示し、アプリを継続動作させる
- レスポンスのJSON解析に失敗した場合は「植物名を推定できませんでした」と表示する

## 影響範囲
- 植物登録・編集の既存フロー、DB、エクスポート/インポートには影響しない（テキストフィールドへの入力補助のみ）

## テスト観点
- [ ] 画像選択後に「AIで植物名を推定」ボタンが表示される
- [ ] タップで推定結果（植物名・品種名候補）が確認ダイアログに表示される
- [ ] 「反映」で植物名・品種名の入力欄に候補が反映される
- [ ] APIキー未設定時に案内メッセージが表示される
- [ ] レスポンスがJSON形式でない場合にエラー表示され、アプリがクラッシュしない

## 実装上の注意点
- #177 の `AiService` と機能的に重複するが、両Issueは独立したブランチで開発されるため本Issueでも `AiService`（`identifyPlant()` 含む）を自己完結的に実装する。マージ順序によっては統合時に軽微な重複解消が必要になる
- レスポンスは厳密なJSONのみを返すようプロンプトで指示し、`jsonDecode` 失敗時はエラーとして扱う
