リリースビルド（APK）を作成し、Google Drive にアップロードする。

## 前提ツール

| ツール | 用途 | 確認コマンド |
|---|---|---|
| Android キーストア | APK への署名 | `ls android/key.properties` |
| rclone | Google Drive へのアップロード | `rclone version` |

どちらかが未設定の場合は **初回セットアップ手順** を案内して停止する。

---

## 初回セットアップ（未設定の場合のみ）

### A. 署名キーストアの作成

> ⚠️ キーストアファイルは **絶対に git に含めない**。紛失するとアプリの更新が不可能になるので安全な場所にバックアップする。

**1. キーストアを生成する（1回のみ）**

```bash
keytool -genkey -v \
  -keystore "$HOME/botanote-upload-keystore.jks" \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload
```

対話形式で名前・組織・パスワードを入力する。パスワードは控えておく。

**2. `android/key.properties` を作成する**

```
storePassword=<キーストアのパスワード>
keyPassword=<キーのパスワード>
keyAlias=upload
storeFile=C:/Users/zorn5/botanote-upload-keystore.jks
```

> `key.properties` は `.gitignore` に追加されていることを確認する。

**3. `android/app/build.gradle.kts` に署名設定を追加する**

ファイル冒頭に追記:
```kotlin
import java.util.Properties

val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties()
if (keyPropertiesFile.exists()) {
    keyProperties.load(keyPropertiesFile.inputStream())
}
```

`android { ... }` ブロック内に `signingConfigs` を追加し、`buildTypes.release` を更新:
```kotlin
signingConfigs {
    create("release") {
        keyAlias = keyProperties["keyAlias"] as String?
        keyPassword = keyProperties["keyPassword"] as String?
        storeFile = keyProperties["storeFile"]?.let { file(it as String) }
        storePassword = keyProperties["storePassword"] as String?
    }
}

buildTypes {
    release {
        signingConfig = if (keyPropertiesFile.exists())
            signingConfigs.getByName("release")
        else
            signingConfigs.getByName("debug")
    }
}
```

**4. `.gitignore` に追記する（まだなければ）**

```
android/key.properties
*.jks
*.keystore
```

---

### B. rclone のインストールと Google Drive 設定

**1. rclone をインストールする**

```bash
winget install Rclone.Rclone
```

インストール後、新しいターミナルを開いて `rclone version` で確認。

**2. Google Drive のリモートを設定する（1回のみ、ブラウザ操作が必要）**

```bash
rclone config
```

対話形式で進める:
- `n` → 新規リモート作成
- name: `gdrive`
- Storage: `drive`（Google Drive）
- client_id / client_secret: 空白のままEnter（共有クライアントを使用）
- scope: `1`（フルアクセス）
- ブラウザが開くので Google アカウントでログインして認証する
- team drive: `n`

設定後 `rclone lsd gdrive:` でドライブの内容が表示されれば成功。

**3. アップロード先フォルダを Google Drive に作成する**

Google Drive 上に `Botanote/releases/` フォルダを作成しておく（Web UI で作成してよい）。

---

## 実行手順（毎回）

### ステップ1: 前提チェック

```bash
# キーストア設定の確認
ls android/key.properties

# rclone の確認
rclone version

# Google Drive リモートの確認
rclone lsd gdrive:
```

いずれか失敗した場合は初回セットアップを案内して停止する。

### ステップ2: バージョン番号の確認

`pubspec.yaml` の `version:` を確認し、ユーザーに現在のバージョンを伝える。
必要であればビルド前にバージョンを更新する（例: `1.0.0+1` → `1.0.1+2`）。

バージョン形式: `<versionName>+<versionCode>`
- versionName: ユーザー向け表示（例: `1.2.0`）
- versionCode: Google Play 用の整数、毎回インクリメント（例: `3`）

### ステップ3: リリース APK をビルドする

```bash
flutter build apk --release
```

成功すると `build/app/outputs/flutter-apk/app-release.apk` が生成される。

ファイルサイズを確認する:
```bash
ls -lh build/app/outputs/flutter-apk/app-release.apk
```

### ステップ4: Google Drive にアップロードする

ファイル名にバージョンと日付を付けてアップロードする:

```bash
# バージョン・日付入りのファイル名でコピー
VERSION=$(grep '^version:' pubspec.yaml | sed 's/version: //' | sed 's/+.*//')
DATE=$(date +%Y%m%d)
FILENAME="botanote_${VERSION}_${DATE}.apk"

cp build/app/outputs/flutter-apk/app-release.apk "/tmp/${FILENAME}"
rclone copy "/tmp/${FILENAME}" "gdrive:Botanote/releases/"
```

### ステップ5: アップロード確認と共有リンクの取得

```bash
# アップロードされたファイルを確認
rclone ls "gdrive:Botanote/releases/"
```

アップロード成功を確認したら、Google Drive の Web UI でファイルの共有リンクを取得してユーザーに報告する。

### ステップ6: 完了報告

以下の形式でユーザーに報告する:

```
## リリースビルド完了

- バージョン: <versionName> (build <versionCode>)
- ファイル名: botanote_<version>_<date>.apk
- ファイルサイズ: XX MB
- アップロード先: Google Drive / Botanote / releases /
- ビルド日時: <日時>

Google Drive の Web UI からファイルを選択して共有リンクを取得してください。
```

---

## 注意事項

- `key.properties` と `.jks` ファイルは **git に含めない**（`.gitignore` で除外）
- キーストアを紛失すると同じ `applicationId` でのアップロードができなくなる
- Google Play Store に提出する場合は APK ではなく AAB（`flutter build appbundle --release`）を使用する
- 署名には時間がかかる場合があるため、ビルド完了まで待つ
