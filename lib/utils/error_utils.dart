// 例外オブジェクトをユーザー向けの文言に整形するユーティリティ。

/// 例外 [e] をユーザー表示用の文字列に整形して返す。
///
/// `Object.toString()` の結果には `Exception: ` などの実装都合のプレフィックスが
/// 付くことがあり、そのままユーザーに見せると分かりにくい。まず代表的な通信系の
/// 例外を日本語の案内文に置き換え、該当しない場合は既知のプレフィックスを
/// 取り除いて読みやすい文言に整える（Issue #273）。
///
/// SnackBar 等でエラー内容をユーザーに提示する際は、生の `$e` を埋め込まず
/// 本関数を通すこと。
///
/// Web ビルドでも使えるよう `dart:io` には依存せず、型名と本文の照合で判定する。
String describeError(Object e) {
  final friendly = _describeCommonError(e);
  if (friendly != null) return friendly;

  var text = e.toString();
  // よくある実装都合のプレフィックスを除去する。
  const prefixes = ['Exception: ', 'FormatException: ', 'Error: '];
  for (final prefix in prefixes) {
    if (text.startsWith(prefix)) {
      text = text.substring(prefix.length);
      break;
    }
  }
  return text;
}

/// 代表的な通信・入出力系の例外を日本語の案内文に変換する。
///
/// 該当しない場合は null を返す。
String? _describeCommonError(Object e) {
  final typeName = e.runtimeType.toString();
  final text = e.toString();

  // 証明書エラーは端末の日付・時刻ずれが原因のことが多いため、そこを案内する
  if (typeName.contains('HandshakeException') ||
      text.contains('CERTIFICATE_VERIFY_FAILED')) {
    if (text.contains('certificate has expired')) {
      return '安全な通信を確立できませんでした。端末の日付・時刻の設定を確認してください';
    }
    return '安全な通信を確立できませんでした。通信環境を確認してください';
  }

  if (typeName.contains('TimeoutException')) {
    return '接続がタイムアウトしました。時間をおいて再度お試しください';
  }

  // SocketException / ClientException（http パッケージ）はいずれも接続不可
  if (typeName.contains('SocketException') ||
      typeName.contains('ClientException') ||
      text.contains('Failed host lookup')) {
    return 'ネットワークに接続できませんでした。通信環境を確認してください';
  }

  if (typeName.contains('HttpException')) {
    return '通信中にエラーが発生しました。時間をおいて再度お試しください';
  }

  // ファイル・ストレージ系
  if (typeName.contains('PathAccessException')) {
    return 'ファイルにアクセスできませんでした。保存先の権限を確認してください';
  }
  if (typeName.contains('PathNotFoundException')) {
    return '対象のファイルが見つかりませんでした';
  }
  if (typeName.contains('FileSystemException')) {
    return 'ファイルの読み書きに失敗しました。端末の空き容量と権限を確認してください';
  }

  return null;
}
