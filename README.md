# Botanote 🌱💧

植物の水やり・肥料・活力剤ログ管理アプリ。スケジュール通知・ログ記録・ノート機能を備えた Flutter 製アプリです。

---

## 主な機能

| 機能 | 説明 |
|---|---|
| 📅 水やりログ | 日付別に水やり・肥料・活力剤の施用履歴を確認・記録。PageViewによる日付切り替えと過去ログ・未来の予定確認に対応 |
| 🗓️ カレンダービュー | TableCalendar によるログ日付の可視化。カレンダーから日付を選択してログを確認可能 |
| 🌿 植物管理 | 名前・品種・購入日・画像などを登録。リスト表示 / グリッド表示を切り替え可能 |
| 💧 ログ記録 | 水やり・肥料・活力剤の施用履歴を植物ごとに管理。一括記録・一括取り消しに対応 |
| ⏱️ 間隔設定 | 水やり・肥料・活力剤それぞれに「N日ごと」または「水やりN回に1回」の間隔を設定可能 |
| 📸 植物画像 | カメラ・ギャラリーから画像取得、トリミング対応。詳細画面で背景表示 |
| 📝 ノート | 植物に紐付けられる自由記述ノート。タイトル・タグ・画像添付に対応 |
| 🔔 プッシュ通知 | 指定時刻に水やりリマインダーを送信（Android / iOS） |
| 🎨 テーマ設定 | グリーン / ブルー / パープル / オレンジの 4 テーマ。ライト / ダーク / システム連動の 3 モード切り替え対応 |
| 🔄 並び替え | 名前順・購入日順・ドラッグ操作によるカスタム順 |
| 💾 ZIPバックアップ | 植物・ログ・ノート・画像ファイルをまとめて ZIP に圧縮してバックアップ・復元 |
| 🌐 Web 対応 | SharedPreferences によりリロード後もデータを保持 |

---

## 対応プラットフォーム

- Android
- iOS
- Web (Chrome)

---

## 開発環境のセットアップ

### 必要なもの

- Flutter SDK `^3.11.0`
- Dart SDK `^3.11.0`
- Android Studio（Android ビルド用）
- Xcode（iOS ビルド用、macOS のみ）

### セットアップ手順

```powershell
# 1. リポジトリをクローン
git clone https://github.com/nk244/Botanote.git
cd Botanote

# 2. 依存パッケージを取得
flutter pub get

# 3. 接続デバイスを確認
flutter devices

# 4. アプリを起動
flutter run -d chrome       # Web
flutter run -d android      # Android
flutter run -d ios          # iOS (macOS のみ)
```

---

## プロジェクト構成

```
lib/
├── main.dart                         # エントリポイント
├── data/
│   └── test_data_generator.dart     # 開発用テストデータ生成
├── models/
│   ├── plant.dart                   # 植物モデル
│   ├── log_entry.dart               # 水やり/肥料/活力剤ログ
│   ├── note.dart                    # ノートモデル
│   ├── app_settings.dart            # アプリ設定（テーマ・通知）
│   └── daily_log_status.dart        # 日別ログステータス
├── providers/
│   ├── plant_provider.dart          # 植物データの状態管理
│   ├── note_provider.dart           # ノートデータの状態管理
│   └── settings_provider.dart       # 設定の状態管理
├── screens/
│   ├── home_screen.dart             # ホーム（タブナビゲーション）
│   ├── today_watering_screen.dart   # 水やりログ（日付別・過去/未来対応）
│   ├── plant_list_screen.dart       # 植物一覧（リスト/グリッド切り替え）
│   ├── plant_detail_screen.dart     # 植物詳細（画像背景・タブ表示）
│   ├── add_plant_screen.dart        # 植物追加・編集
│   ├── image_crop_screen.dart       # 画像トリミング
│   ├── notes_list_screen.dart       # ノート一覧（検索・タグ絞り込み）
│   ├── note_detail_screen.dart      # ノート詳細
│   ├── add_edit_note_screen.dart    # ノート追加・編集
│   └── settings_screen.dart         # 設定（テーマ・通知・データ管理）
├── services/
│   ├── database_service.dart        # SQLite 操作（Android/iOS）
│   ├── web_storage_service.dart     # SharedPreferences によるデータ永続化（Web）
│   ├── memory_storage_service.dart  # インメモリストレージ（Web 開発用）
│   ├── export_service.dart          # JSON エクスポート/インポート
│   ├── log_service.dart             # 水やりログ集計
│   ├── notification_service.dart    # ローカルプッシュ通知
│   └── settings_service.dart        # 設定の永続化（SharedPreferences）
├── theme/
│   └── app_themes.dart              # テーマ定義
├── utils/
│   └── date_utils.dart              # 日付ユーティリティ
└── widgets/
    └── plant_image_widget.dart      # 植物画像表示ウィジェット
```

---

## 主要依存パッケージ

| パッケージ | バージョン | 用途 |
|---|---|---|
| `provider` | ^6.1.1 | 状態管理 |
| `sqflite` | ^2.3.0 | SQLite（モバイル） |
| `shared_preferences` | ^2.2.2 | 設定永続化 / Web 永続化 |
| `image_picker` | ^1.0.7 | カメラ・ギャラリー取得 |
| `crop_your_image` | ^1.0.0 | 画像トリミング |
| `flutter_local_notifications` | ^20.1.0 | ローカルプッシュ通知 |
| `table_calendar` | ^3.1.2 | カレンダーUI |
| `timezone` | ^0.10.1 | タイムゾーン管理 |
| `flutter_localizations` | SDK | カレンダー・UI の日本語ローカライゼーション |
| `intl` | ^0.20.2 | 日付フォーマット（ja） |
| `archive` | ^4.0.9 | ZIPバックアップ |
| `share_plus` | ^10.1.4 | OS共有シート |
| `file_picker` | ^10.3.10 | バックアップファイル選択 |
| `permission_handler` | ^11.2.0 | ランタイムパーミッション |
| `uuid` | ^4.3.3 | UUID 生成 |
| `path_provider` | ^2.1.1 | ドキュメントディレクトリ取得 |

---

## よく使うコマンド

```powershell
# 依存パッケージ取得
flutter pub get

# 静的解析
flutter analyze

# テスト実行
flutter test

# Android 向け実行
flutter run -d android

# Web 向け実行
flutter run -d chrome

# リリースビルド（Android APK）
flutter build apk --release
```

---

## アーキテクチャ

- **状態管理**: Provider パターン（`ChangeNotifier`）
- **設計パターン**: Provider + Repository パターン
  - `screens/` → `providers/` → `services/` → `models/` の一方向依存
- **データ永続化**:
  - モバイル: SQLite（`sqflite`）。DBバージョン管理による累積マイグレーション方式
  - Web: SharedPreferences（`shared_preferences`）
- **サービス層**: DB 操作・通知・ファイル I/O を `lib/services/` に分離
- **プラットフォーム分岐**: `kIsWeb` で Web / モバイルを切り替え
- **バックアップ**: 植物・ログ・ノート・画像を ZIP に圧縮して共有シートで書き出し、ファイルピッカーで復元

---

## トラブルシューティング

### パッケージの依存関係エラー

```powershell
flutter clean
flutter pub get
```

### Android ライセンスエラー

```powershell
flutter doctor --android-licenses
```

### 通知が届かない（Android）

`AndroidManifest.xml` に通知パーミッションが設定されているか確認してください。  
また Android 13 以降は実行時パーミッション（`POST_NOTIFICATIONS`）の許可が必要です。

---

## ライセンス

MIT License
