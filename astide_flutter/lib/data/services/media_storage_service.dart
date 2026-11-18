import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Persists picked images, documents, avatars, and imported DeepSeek assets inside app storage.
class MediaStorageService {
  MediaStorageService({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;
  Directory? _rootDir;

  Future<Directory> _ensureSubdir(String name) async {
    final root = _rootDir ??= Directory(
      p.join((await getApplicationDocumentsDirectory()).path, 'astide_media'),
    );
    final sub = Directory(p.join(root.path, name));
    if (!await sub.exists()) {
      await sub.create(recursive: true);
    }
    return sub;
  }

  Future<String> saveFileCopy(String sourcePath, {String category = 'files'}) async {
    final source = File(sourcePath);
    final dir = await _ensureSubdir(category);
    final ext = p.extension(sourcePath);
    final destPath = p.join(dir.path, '${_uuid.v4()}$ext');
    await source.copy(destPath);
    return destPath;
  }

  Future<String> saveBytes(
    Uint8List bytes, {
    required String fileName,
    String category = 'images',
  }) async {
    final dir = await _ensureSubdir(category);
    final ext = p.extension(fileName).isNotEmpty ? p.extension(fileName) : '.bin';
    final destPath = p.join(dir.path, '${_uuid.v4()}$ext');
    await File(destPath).writeAsBytes(bytes, flush: true);
    return destPath;
  }

  Future<int> calculateTotalBytes() async {
    final root = _rootDir ??= Directory(
      p.join((await getApplicationDocumentsDirectory()).path, 'astide_media'),
    );
    if (!await root.exists()) return 0;
    var total = 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }

  Future<void> deleteFileIfExists(String? path) async {
    if (path == null || path.isEmpty) return;
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> clearAllMedia() async {
    final root = _rootDir ??= Directory(
      p.join((await getApplicationDocumentsDirectory()).path, 'astide_media'),
    );
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  }
}
