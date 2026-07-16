import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';

/// #199 の再現/検証用テスト。
///
/// ZipEncoder で作った ZIP を ZipDecoder で読み戻し、data.json を取り出せるか確認する。
void main() {
  test('ZipEncoder -> ZipDecoder round-trip で data.json を取得できる', () {
    // 実際のバックアップに近い、圧縮が効く程度の大きさの JSON を用意する
    final data = {
      'version': 3,
      'plants': List.generate(
        20,
        (i) => {
          'id': 'plant-$i',
          'name': 'Plant $i',
          'wateringIntervalDays': 7,
          'imagePath': null,
        },
      ),
    };
    final jsonBytes =
        utf8.encode(const JsonEncoder.withIndent('  ').convert(data));

    final archive = Archive();
    archive.addFile(ArchiveFile('data.json', jsonBytes.length, jsonBytes));

    final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive));

    final decoded = ZipDecoder().decodeBytes(zipBytes);
    final entry = decoded.findFile('data.json');

    expect(entry, isNotNull,
        reason: 'ZipEncoder が生成した ZIP から data.json を取得できること');
    final restored = utf8.decode(entry!.content as List<int>);
    expect(restored, equals(utf8.decode(jsonBytes)));
  });
}
