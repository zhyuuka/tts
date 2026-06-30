import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;

import '../models/attachment.dart';
import 'attachment_bytes_stub.dart'
    if (dart.library.io) 'attachment_bytes_io.dart'
    as io;

Future<Uint8List?> loadAttachmentBytes(Attachment a) async {
  if (a.dataBase64 != null && a.dataBase64!.isNotEmpty) {
    try {
      return base64Decode(a.dataBase64!);
    } catch (_) {
      return null;
    }
  }
  if (!kIsWeb && a.path != null && a.path!.isNotEmpty) {
    return io.readLocalPath(a.path!);
  }
  return null;
}
