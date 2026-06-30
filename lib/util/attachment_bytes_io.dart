import 'dart:io';
import 'dart:typed_data';

Future<Uint8List?> readLocalPath(String path) async {
  if (path.isEmpty) return null;
  try {
    final f = File(path);
    if (await f.exists()) return f.readAsBytes();
  } catch (_) {}
  return null;
}
