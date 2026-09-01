import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../models/sensor_log.dart';

/// IoTデバイスから取得したセンサーデータ（生データ）
class SensorData {
  /// デバイスID
  final String deviceId;

  /// デバイス名
  final String deviceName;

  /// 温度（℃）
  final double? temperature;

  /// 湿度（%）
  final double? humidity;

  /// データ取得元
  final SensorSource source;

  const SensorData({
    required this.deviceId,
    required this.deviceName,
    this.temperature,
    this.humidity,
    this.source = SensorSource.manual,
  });
}

/// IoTセンサーデバイスとの API 通信を担うサービス。
///
/// Nature Remo と SwitchBot の REST API を呼び出し、
/// 温度・湿度データを [SensorData] のリストとして返す。
class IotService {
  static final IotService _instance = IotService._internal();
  factory IotService() => _instance;
  IotService._internal();

  static const Duration _timeout = Duration(seconds: 10);

  /// HTTPステータスコードをユーザー向けのエラーメッセージに変換する。
  ///
  /// [service] はサービス名（例: 'Nature Remo'）。認証エラーなど原因が分かる
  /// コードは具体的な文言にし、それ以外は汎用の HTTP エラー文言を返す。
  static String _httpErrorMessage(String service, int statusCode) {
    switch (statusCode) {
      case 401:
      case 403:
        return '$service のAPIトークンが正しくありません（HTTP $statusCode）';
      case 429:
        return '$service へのリクエストが多すぎます。しばらく待ってから再試行してください（HTTP $statusCode）';
      case 500:
      case 502:
      case 503:
        return '$service のサーバーが一時的に応答していません（HTTP $statusCode）';
      default:
        return '$service APIエラー: HTTP $statusCode';
    }
  }

  // ── Nature Remo ──────────────────────────────────────────────

  /// Nature Remo からすべてのデバイスのセンサーデータを取得する。
  ///
  /// [token] が空の場合は例外をスローする。
  Future<List<SensorData>> fetchNatureRemoData(String token) async {
    if (token.isEmpty) {
      throw Exception('Nature Remo のAPIトークンが設定されていません');
    }

    final response = await http
        .get(
          Uri.parse('https://api.nature.global/1/devices'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(_timeout);

    if (response.statusCode != 200) {
      throw Exception(_httpErrorMessage('Nature Remo', response.statusCode));
    }

    final List<dynamic> devices = jsonDecode(response.body) as List<dynamic>;

    return devices.map((d) {
      final map = d as Map<String, dynamic>;
      final events = map['newest_events'] as Map<String, dynamic>? ?? {};

      // 温度: newest_events.te.val
      final teEvent = events['te'] as Map<String, dynamic>?;
      final double? temperature = teEvent != null
          ? (teEvent['val'] as num?)?.toDouble()
          : null;

      // 湿度: newest_events.hu.val
      final huEvent = events['hu'] as Map<String, dynamic>?;
      final double? humidity = huEvent != null
          ? (huEvent['val'] as num?)?.toDouble()
          : null;

      return SensorData(
        deviceId: map['id'] as String? ?? '',
        deviceName: map['name'] as String? ?? '不明なデバイス',
        temperature: temperature,
        humidity: humidity,
        source: SensorSource.natureRemo,
      );
    }).toList();
  }

  // ── SwitchBot ────────────────────────────────────────────────

  /// SwitchBot からすべてのデバイスのセンサーデータを取得する。
  ///
  /// [token] または [secret] が空の場合は例外をスローする。
  Future<List<SensorData>> fetchSwitchBotData(
    String token,
    String secret,
  ) async {
    if (token.isEmpty || secret.isEmpty) {
      throw Exception('SwitchBot のトークンまたはシークレットが設定されていません');
    }

    // デバイス一覧を取得する
    final deviceListResponse = await http
        .get(
          Uri.parse('https://api.switch-bot.com/v1.1/devices'),
          headers: _buildSwitchBotHeaders(token, secret),
        )
        .timeout(_timeout);

    if (deviceListResponse.statusCode != 200) {
      throw Exception(
        _httpErrorMessage('SwitchBot', deviceListResponse.statusCode),
      );
    }

    final deviceListBody =
        jsonDecode(deviceListResponse.body) as Map<String, dynamic>;
    final deviceList =
        (deviceListBody['body'] as Map<String, dynamic>?)?['deviceList']
            as List<dynamic>? ??
        [];

    // 各デバイスのステータスを取得する
    final results = <SensorData>[];
    for (final d in deviceList) {
      final device = d as Map<String, dynamic>;
      final deviceId = device['deviceId'] as String? ?? '';
      final deviceName = device['deviceName'] as String? ?? '不明なデバイス';
      if (deviceId.isEmpty) continue;

      try {
        final statusResponse = await http
            .get(
              Uri.parse(
                'https://api.switch-bot.com/v1.1/devices/$deviceId/status',
              ),
              headers: _buildSwitchBotHeaders(token, secret),
            )
            .timeout(_timeout);

        if (statusResponse.statusCode != 200) continue;

        final statusBody =
            jsonDecode(statusResponse.body) as Map<String, dynamic>;
        final body = statusBody['body'] as Map<String, dynamic>? ?? {};

        final double? temperature = (body['temperature'] as num?)?.toDouble();
        final double? humidity = (body['humidity'] as num?)?.toDouble();

        // 温度か湿度のどちらかを持つデバイスのみ結果に含める
        if (temperature != null || humidity != null) {
          results.add(
            SensorData(
              deviceId: deviceId,
              deviceName: deviceName,
              temperature: temperature,
              humidity: humidity,
              source: SensorSource.switchBot,
            ),
          );
        }
      } catch (_) {
        // 個別デバイスの取得失敗は無視して次のデバイスへ
        continue;
      }
    }

    return results;
  }

  /// SwitchBot API 用の認証ヘッダーを生成する。
  ///
  /// 署名: HMAC-SHA256(token + timestamp + nonce, secret) をBase64エンコード
  Map<String, String> _buildSwitchBotHeaders(String token, String secret) {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final nonce = const Uuid().v4();
    final signData = '$token$timestamp$nonce';
    final hmac = Hmac(sha256, utf8.encode(secret));
    final sign = base64.encode(hmac.convert(utf8.encode(signData)).bytes);

    return {
      'Authorization': token,
      'sign': sign,
      't': timestamp,
      'nonce': nonce,
      'Content-Type': 'application/json',
    };
  }
}
