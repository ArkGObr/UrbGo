import 'dart:io';

import 'package:flutter/services.dart';

class DocumentPickerService {
  static const MethodChannel _channel = MethodChannel(
    'com.arkgo.app/document_picker',
  );

  Future<File?> pickPdf() async {
    try {
      final path = await _channel.invokeMethod<String>('pickPdf');
      if (path == null || path.isEmpty) return null;
      return File(path);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
