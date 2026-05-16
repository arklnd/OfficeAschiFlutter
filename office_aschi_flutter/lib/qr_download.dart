import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:qr_flutter/qr_flutter.dart';

// Web-only imports via conditional
import 'qr_download_stub.dart'
    if (dart.library.html) 'qr_download_web.dart'
    as platform;

Future<String?> downloadQrImage(String data, String filename) async {
  final qrPainter = QrPainter(
    data: data,
    version: QrVersions.auto,
    eyeStyle: const QrEyeStyle(
      eyeShape: QrEyeShape.square,
      color: ui.Color(0xFF1a237e),
    ),
    dataModuleStyle: const QrDataModuleStyle(
      dataModuleShape: QrDataModuleShape.square,
      color: ui.Color(0xFF1a237e),
    ),
  );

  final image = await qrPainter.toImage(300);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  if (byteData == null) return null;
  final bytes = byteData.buffer.asUint8List();
  return await platform.saveBytes(bytes, filename);
}
