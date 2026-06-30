---
issue: 67
title: AI組み込み
status: implemented
---

## 概要

植物の管理体験を向上させるため、Claude API（Anthropic）を用いたAI機能を3つ追加する。
① 写真・症状テキストから植物の健康診断を行う「健康診断」、② 写真から植物を自動識別して登録フォームに入力する「自動登録」、③ 過去のケアログ・ノートを踏まえた相談ができる「パーソナル植物コーチ」。
実装は段階的に行い、まず共通基盤（AIサービス・API設定UI）を構築してから各機能を追加する。

---

## 変更対象ファイル

| ファイル | 種別 | 変更概要 |
|---|---|---|
| `lib/services/ai_service.dart` | 新規 | Claude API との通信処理（テキスト・画像送信） |
| `lib/providers/ai_provider.dart` | 新規 | AIチャット状態管理（メッセージ履歴・ローディング） |
| `lib/models/ai_chat_message.dart` | 新規 | チャットメッセージデータモデル |
| `lib/screens/ai_chat_screen.dart` | 新規 | パーソナル植物コーチのチャットUI |
| `lib/screens/plant_health_screen.dart` | 新規 | 植物健康診断UI |
| `lib/screens/add_plant_screen.dart` | 変更 | 植物登録時にAI識別ボタンを追加 |
| `lib/screens/plant_detail_screen.dart` | 変更 | 詳細タブに「健康診断する」ボタンを追加 |
| `lib/screens/settings_screen.dart` | 変更 | Claude APIキー入力UIを追加 |
| `lib/screens/home_screen.dart` | 変更 | BottomNavigationにAIタブを追加 |
| `lib/main.dart` | 変更 | MultiProvider に AiProvider を追加 |
| `lib/models/app_settings.dart` | 変更 | `claudeApiKey` フィールドを追加 |
| `lib/services/settings_service.dart` | 変更 | `claudeApiKey` の保存・読み込みを追加 |
| `pubspec.yaml` | 変更 | `http` パッケージを追加 |

---

## データモデル変更

### `AppSettings` に `claudeApiKey` を追加

```dart
class AppSettings {
  // 既存フィールド...
  final String claudeApiKey; // Claude API キー（空文字列 = 未設定）
}
```

sentinel パターン不要（空文字列でデフォルト値を表現できるため）。

### 新規: `AiChatMessage`

```dart
/// AIチャットのメッセージデータモデル
class AiChatMessage {
  final String id;        // UUID
  final bool isUser;      // true=ユーザー発言, false=AI応答
  final String text;
  final String? imageBase64; // ユーザーが添付した画像（Base64エンコード済み）
  final DateTime createdAt;
}
```

チャット履歴はセッション内のみ保持（DB永続化なし）。コーチ機能は画面を閉じるとリセット。

---

## DB変更

なし（チャット履歴はメモリのみ。APIキーはSharedPreferencesに保存）。

---

## UI/UX設計

### ① BottomNavigation に「AI」タブを追加

`home_screen.dart` の `NavigationBar` に4つ目のタブ（`Icons.smart_toy_outlined` / `Icons.smart_toy`）を追加し、AIチャット画面 `AiChatScreen` を表示する。

### ② 設定画面: APIキー入力

`settings_screen.dart` に「Claude API設定」セクションを追加。
- テキストフィールド（パスワード表示切替付き）でAPIキーを入力・保存
- 未設定の場合、AI機能の各エントリーポイントで「設定 > APIキーを設定してください」とSnackBarで案内

### ③ 植物健康診断 (`PlantHealthScreen`)

**エントリーポイント**: `PlantDetailScreen` の詳細タブに「健康診断する」ボタンを追加。

**画面フロー**:
```
PlantDetailScreen（詳細タブ）
  └─ 「健康診断する」ボタン
       └─ PlantHealthScreen
            ├─ 植物名・品種の自動表示
            ├─ 症状テキスト入力フィールド（必須）
            ├─ 写真添付ボタン（任意・image_picker使用）
            ├─ 「診断する」ボタン → AI呼び出し
            └─ 診断結果表示（Markdownテキスト）
```

**プロンプト方針**:
- システム: 植物の健康アドバイザーとしてのロールを設定
- ユーザー: 植物名・品種・水やり間隔・最終水やり日・症状テキスト・画像を送信
- 参考: `plant_detail_screen.dart` のログ表示部分（最終水やり日の取得方法）

### ④ 植物自動登録 (`AddPlantScreen` 改修)

**エントリーポイント**: `AddPlantScreen` の画像選択後に「AIで植物を識別」ボタンを表示。

**フロー**:
```
画像選択（既存）
  └─ 「AIで識別」ボタン（画像設定後に出現）
       ├─ ローディング表示
       └─ 識別結果ダイアログ
            ├─ 植物名（候補）
            ├─ 品種（候補）
            ├─ 「この内容で入力する」→ フォームに自動入力
            └─ 「キャンセル」
```

**プロンプト方針**:
- 画像のみ送信、「植物名と品種を日本語でJSON形式で返してください」と指示
- レスポンス例: `{"name": "モンステラ", "variety": "デリシオサ"}`

### ⑤ パーソナル植物コーチ (`AiChatScreen`)

**画面構成**:
```
AiChatScreen
├─ AppBar: 「植物コーチ」
├─ チャット履歴リスト（ListView.builder、下から最新）
│   ├─ ユーザーメッセージ（右寄り吹き出し）
│   └─ AIメッセージ（左寄り吹き出し、アバターアイコン付き）
├─ ローディングインジケーター（AI応答待ち中）
└─ 入力エリア
    ├─ テキストフィールド
    ├─ 画像添付ボタン
    └─ 送信ボタン
```

**コンテキスト送信方針**:
- 初回メッセージ時、ユーザーの全植物サマリー（名前・水やり間隔・最終水やり日）と直近30件のログを自動的にシステムプロンプトに含める
- 以降は会話履歴のみ追記して送信（最大20往復程度でトリミング）

---

## エラーハンドリング

| 異常系 | 対処方針 |
|---|---|
| APIキー未設定 | SnackBarで「設定からAPIキーを設定してください」と案内 |
| APIキー不正（401） | 「APIキーが無効です。設定を確認してください」ダイアログ |
| ネットワーク不通 | 「ネットワーク接続を確認してください」SnackBarで通知 |
| レートリミット（429） | 「しばらく待ってから再試行してください」と案内 |
| AI識別失敗（植物未識別） | 「識別できませんでした。手動で入力してください」 |
| レスポンスJSON解析失敗 | JSONパースをtry/catchでラップ、失敗時はテキスト全体を表示 |
| タイムアウト | 30秒でタイムアウト設定、再試行を促す |

---

## 影響範囲

- **バックアップ/エクスポート**: APIキーはSharedPreferencesに保存するためZIPバックアップには含まれない（意図的）。チャット履歴も永続化しないためエクスポート対象外。
- **通知機能**: 影響なし。
- **他画面**: `PlantDetailScreen` に診断ボタンを1つ追加するのみ。`AddPlantScreen` に識別ボタンを条件付きで追加するのみ。
- **BottomNavigation**: タブが3→4になるため `IndexedStack` のインデックスズレに注意（既存スクリーンへの影響なし）。

---

## テスト観点

### 正常系
- [ ] 設定画面でAPIキーを入力・保存し、アプリ再起動後も保持されること
- [ ] 植物詳細画面から健康診断を開き、症状テキストのみで診断結果が返ること
- [ ] 健康診断で画像を添付して送信すると、画像を考慮した診断結果が返ること
- [ ] 植物追加画面で画像選択後に「AIで識別」ボタンが表示され、識別結果がフォームに入力されること
- [ ] コーチ画面でメッセージを送ると返答が返り、会話を継続できること
- [ ] コーチ画面で画像を添付して送信できること

### 異常系
- [ ] APIキー未設定の状態でAI機能を使おうとするとSnackBarが表示されること
- [ ] 不正なAPIキーを設定した場合にエラーメッセージが表示されること
- [ ] 機内モードでAI機能を使おうとするとネットワークエラーが表示されること

### 境界値
- [ ] 植物が0件の状態でコーチ画面を開いてもクラッシュしないこと
- [ ] 長い診断結果テキストが正しくスクロール表示されること
- [ ] コーチの会話が20往復を超えてもクラッシュしないこと

---

## 実装上の注意点

### Claude API呼び出し
- モデルは `claude-haiku-4-5-20251001`（コスト効率重視）を基本とし、コーチ機能は `claude-sonnet-4-6` も選択可能にすることを検討する
- 画像送信は Base64 エンコードで `image/jpeg` として送信（`Plant.imagePath` はすでにBase64のため変換不要）
- `http` パッケージ（`^1.2.0`）を使用。`dio` は過剰。

### APIキーの管理
- SharedPreferences に保存する（既存の `settings_service.dart` の仕組みに乗る）
- UI上は `obscureText: true` で表示、コピー防止は行わない（利便性優先）

### Provider パターン
- `AiProvider` を新設し、`ChangeNotifier` で管理
- `main.dart` の `MultiProvider` に追加
- `AiService` は `AiProvider` からのみ呼び出す（`screens` から直接呼ばない）

### BottomNavigation の変更
- `home_screen.dart` の `_screens` リストと `NavigationDestination` に追加
- インデックス番号が変わるため、既存の `index == 2`（ノートタブ）の判定を `index == 3` に更新すること

### コーチのシステムプロンプト
- 植物一覧と最近のログは `AiProvider.buildSystemPrompt()` で生成し、`PlantProvider` のデータを渡す
- 個人情報（購入先など）はプロンプトに含めない

---

## レビュー結果
- レビュー日: 2026-06-29
- 結果: 承認
- コメント: 3件の軽微な指摘をレビュー内で修正済み。①変更対象に `plant_detail_screen.dart` と `main.dart` を追記、②`AiChatMessage.imagePath` → `imageBase64` にリネーム。設計の方向性・アーキテクチャ規約への準拠に問題なし。
