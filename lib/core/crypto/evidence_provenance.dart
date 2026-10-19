import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

class EvidenceProvenance {
  static Future<String> appVersion() async {
    final package = await PackageInfo.fromPlatform();
    return '${package.version}+${package.buildNumber}';
  }

  static Future<String>? _modelHash;
  static Future<String> modelHash() => _modelHash ??= () async {
    final asset = await rootBundle.load('assets/models/model.tflite');
    return sha256
        .convert(
          asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes),
        )
        .toString();
  }();
}
