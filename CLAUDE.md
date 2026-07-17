# Botanote — Claude Code 開発ガイドライン

## 基本方針

- **言語**: ユーザーとのやり取りはすべて **日本語** で行うこと
- **PRの発行**: 実装完了後はブランチ作成・コミット・PR発行まで実施する。**マージは原則AIが行わず、ユーザーが確認してからマージする**
  - 例外: ユーザーが `/pr-review <N>` を実行した場合のみ、AIがレビュー後にマージまで実施してよい（詳細は `.claude/commands/pr-review.md`）
- **ソースコメント**: コード内のコメントはすべて **日本語** で記述する
- **コーディング規約**: [Effective Dart](https://dart.dev/effective-dart) に準拠する
- **設計パターン**: Flutter開発の一般的なパターン（Provider + Repository パターン）に基づく
- **コンパイルチェック**: **commit前に必ず `flutter analyze` でエラーがないことを確認すること。エラーがある場合は修正してから commit する**

---

## プロジェクト概要

| 項目 | 内容 |
|---|---|
| アプリ名 | Botanote |
| 概要 | 植物の水やり・肥料・活力剤ログ管理アプリ |
| フレームワーク | Flutter `^3.11.0` |
| 状態管理 | Provider (`^6.1.1`) |
| DB | SQLite via sqflite (`^2.3.0`) |
| 対象プラットフォーム | Android / iOS（主要）, Web / Windows（補助） |
| SDK制約 | Dart `>=3.11.0 <4.0.0` |

---

## よく使うコマンド

```bash
# 静的解析（commit前に必ず実行）
flutter analyze

# ビルド
flutter build apk          # Android
flutter build ios          # iOS
flutter build web          # Web

# テスト
flutter test

# 依存関係の更新
flutter pub get
flutter pub upgrade
```

---

## アーキテクチャ設計

### レイヤー構成（Provider + Repository パターン）

```
UI層          lib/screens/        画面ウィジェット（StatefulWidget / StatelessWidget）
              lib/widgets/        再利用可能な共通ウィジェット

状態管理層    lib/providers/      ChangeNotifier ベースのProviderクラス
                                  ビジネスロジックの集約点

サービス層    lib/services/       DBアクセス・外部API・ファイルI/O等の処理
                                  Providerから呼び出される（直接UI層からは呼ばない）

モデル層      lib/models/         不変データクラス（freezed非使用、手動copyWith）

ユーティリティ lib/utils/          純粋関数・定数・拡張メソッド
              lib/theme/          テーマ定義
```

### 依存方向ルール

```
screens → providers → services → models
widgets → providers（必要な場合）
screens → models（表示のみ）
```

> **禁止**: `screens` から `services` を直接呼び出さない  
> **禁止**: `models` が `services` や `providers` に依存しない

---

## ファイル命名規則（Effective Dart 準拠）

| 対象 | 規則 | 例 |
|---|---|---|
| ファイル名 | `snake_case.dart` | `plant_detail_screen.dart` |
| クラス名 | `UpperCamelCase` | `PlantDetailScreen` |
| メソッド・変数 | `lowerCamelCase` | `wateringIntervalDays` |
| 定数 | `lowerCamelCase` | `const defaultInterval = 7;` |
| プライベートメンバー | `_lowerCamelCase` | `_selectedDate` |
| 型パラメータ | `UpperCamelCase` | `T`, `TResult` |

---

## コーディング規約（Effective Dart 抜粋）

### スタイル

- `var` より型推論が明確な場合は明示的な型アノテーションを付ける
- `final` を積極的に使用し、不変性を優先する
- `const` コンストラクタは可能な限り使用する
- 1ファイル1クラスを原則とする（小さなヘルパークラスは例外）

### ドキュメントコメント

```dart
/// 植物の水やり記録を保存する。
///
/// [plantId] に対応する植物が存在しない場合は [ArgumentError] をスローする。
Future<void> saveWateringLog(String plantId) async { ... }
```

- パブリックAPIには `///` ドキュメントコメントを付ける
- インラインコメントは `//` + 日本語で記述する
- TODOコメントは `// TODO(担当): 内容` の形式にする

### 非同期処理

- `async`/`await` を使用する（`.then()` チェーンは避ける）
- `Future` の戻り値は適切にハンドリングし、`unawaited` は明示する
- エラーハンドリングは `try/catch` で行い、エラーをサイレントに無視しない

### ウィジェット設計

- 大きな `build()` は `_buildXxx()` プライベートメソッドに分割する
- `StatefulWidget` は状態が必要な場合のみ使用し、それ以外は `StatelessWidget`
- `Consumer<T>` / `context.watch<T>()` の使用範囲は最小限に絞る（不要な再描画を避ける）
- ウィジェットの分割基準: 100行を超えたら別ウィジェットに切り出す目安とする

---

## データモデル規約

### `copyWith` パターン

null クリアを可能にするため、sentinel パターンを使用する:

```dart
// ファイル末尾にプライベート定義
const Object _sentinel = Object();

Plant copyWith({
  Object? name = _sentinel,
  Object? wateringIntervalDays = _sentinel,
  // ...
}) {
  return Plant(
    name: name == _sentinel ? this.name : name as String,
    wateringIntervalDays: wateringIntervalDays == _sentinel
        ? this.wateringIntervalDays
        : wateringIntervalDays as int?,
    // ...
  );
}
```

### `toMap()` / `fromMap()` 規約

- キー名はモデルフィールド名と一致させる（DBカラム名と統一）
- `DateTime` は ISO8601 文字列（`.toIso8601String()`）で保存する
- JSONリスト（`plantIds`等）は `jsonEncode`/`jsonDecode` を使用する

---

## データベース規約

### バージョン管理

```dart
// バージョンは整数インクリメント（現在: 4）
static const int _dbVersion = N;

// onUpgrade は累積マイグレーション方式
Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
  if (oldVersion < 2) { /* v1→v2 */ }
  if (oldVersion < 3) { /* v2→v3 */ }
  if (oldVersion < N) { /* vN-1→vN */ }
}
```

### ALTER TABLE 規約

- 新カラム追加は `try/catch` でラップしてべき等性を保つ
- カラム削除・リネームは新テーブル作成＋データ移行方式で行う
- 外部キーは `ON DELETE CASCADE` を基本とする

---

## Git ブランチ・コミット規約

### ブランチ命名

```
feat/<機能名>-<issue番号>    例: feat/ai-service-67
fix/<バグ名>-<issue番号>     例: fix/export-bug-76
refactor/<対象>              例: refactor/database-service
```

### コミットメッセージ（Conventional Commits）

```
feat: 植物一括登録機能を追加 (#66)
fix: エクスポートファイル保存のバグを修正 (#76)
refactor: DatabaseServiceをリポジトリパターンに整理
docs: READMEにセットアップ手順を追加
chore: パッケージバージョンを更新
```

### PR規約

- タイトル: `feat: <機能概要> (#<issue番号>)`
- 本文: 変更内容・スクリーンショット（UI変更時）・テスト手順を記載
- **AIはPRの発行まで実施し、マージは原則ユーザーが行う**（例外: `/pr-review <N>` 実行時はAIがレビュー後にマージしてよい）

---

## 主要パッケージ一覧

| パッケージ | バージョン | 用途 |
|---|---|---|
| `provider` | `^6.1.1` | 状態管理 |
| `sqflite` | `^2.3.0` | ローカルDB |
| `path_provider` | `^2.1.1` | ファイルパス |
| `image_picker` | `^1.0.7` | 画像選択 |
| `crop_your_image` | `^1.0.0` | 画像クロップ |
| `flutter_local_notifications` | `^20.1.0` | プッシュ通知 |
| `table_calendar` | `^3.1.2` | カレンダーUI |
| `archive` | `^4.0.9` | ZIPバックアップ |
| `share_plus` | `^10.1.4` | OS共有シート |
| `file_picker` | `^10.3.10` | ファイル選択・インポート |
| `permission_handler` | `^11.2.0` | 実行時パーミッション |
| `uuid` | `^4.3.3` | UUID生成 |
| `intl` | `^0.20.2` | 日付・数値フォーマット |
| `timezone` | `^0.10.1` | タイムゾーン |
| `workmanager` | `^0.9.0` | バックグラウンドタスク |
