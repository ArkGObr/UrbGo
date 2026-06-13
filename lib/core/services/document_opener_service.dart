import 'dart:io';

import 'package:flutter/services.dart';

class DocumentOpenerService {
  static const MethodChannel _channel = MethodChannel(
    'com.arkgo.app/document_opener',
  );

  Future<void> openAssetPdf({
    required String assetPath,
    required String fileName,
  }) async {
    final bytes = await _loadAssetBytes(assetPath);
    final file = await _writeTempFile(fileName: fileName, bytes: bytes);

    await _channel.invokeMethod<void>('openDocument', {
      'path': file.path,
      'mimeType': 'application/pdf',
    });
  }

  Future<Uint8List> _loadAssetBytes(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    return data.buffer.asUint8List();
  }

  Future<File> _writeTempFile({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final safeFileName = fileName.endsWith('.pdf') ? fileName : '$fileName.pdf';
    final file = File('${Directory.systemTemp.path}/$safeFileName');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}
