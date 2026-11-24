import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// 选图时的最大边长（像素），UI 与存储共用。
const int kImageMaxSide = 1280;

/// 选图时的压缩质量，UI 与存储共用。
const int kImageQuality = 82;

/// 排便图片目录名。
const String kStoolImageFolder = 'stool';

/// 儿保检查图片目录名。
const String kCheckupImageFolder = 'checkup';

/// 应用私有目录下的图片存储。
///
/// 数据库只保存相对路径（例如 `stool/xxx.jpg`），图片文件位于
/// 应用文档目录的 `images/` 子目录中。
class ImageStore {
  ImageStore._();

  static const Uuid _uuid = Uuid();

  static Future<Directory> _root() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, 'images'));
  }

  static String _normalize(String relativePath) =>
      relativePath.replaceAll('\\', '/').replaceFirst(RegExp(r'^/+'), '');

  static Future<File> _resolve(String relativePath) async {
    final root = await _root();
    final segments = _normalize(relativePath).split('/');
    return File(p.joinAll([root.path, ...segments]));
  }

  /// 把 [sourcePath]（image_picker 返回的临时文件）复制到
  /// `images/<folder>/<uuid>.jpg`，返回相对路径。
  static Future<String> save(
    String sourcePath, {
    required String folder,
  }) async {
    final dir = Directory(p.join((await _root()).path, folder));
    await dir.create(recursive: true);
    final name = '${_uuid.v4()}.jpg';
    final target = File(p.join(dir.path, name));
    await File(sourcePath).copy(target.path);
    return '$folder/$name';
  }

  /// 返回相对路径对应的文件，不存在时返回 null。
  static Future<File?> file(String relativePath) async {
    if (relativePath.trim().isEmpty) return null;
    final target = await _resolve(relativePath);
    return await target.exists() ? target : null;
  }

  /// 删除图片文件；文件不存在时忽略。
  static Future<void> delete(String relativePath) async {
    if (relativePath.trim().isEmpty) return;
    final target = await _resolve(relativePath);
    if (await target.exists()) {
      await target.delete();
    }
  }

  /// 删除整类图片目录（如 `stool`）。
  static Future<void> deleteFolder(String folder) async {
    final dir = Directory(p.join((await _root()).path, folder));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// 递归读取 `images/` 下所有图片，key 为使用 `/` 分隔的相对路径。
  static Future<Map<String, String>> readAllAsBase64() async {
    final root = await _root();
    if (!await root.exists()) return {};
    final result = <String, String>{};
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relative = p
          .relative(entity.path, from: root.path)
          .replaceAll('\\', '/');
      result[relative] = base64Encode(await entity.readAsBytes());
    }
    return result;
  }

  /// 先清空 `images/`，再按相对路径写回图片。
  static Future<void> restoreAllFromBase64(Map<String, String> data) async {
    final root = await _root();
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
    await root.create(recursive: true);
    for (final entry in data.entries) {
      final relative = _normalize(entry.key);
      if (relative.isEmpty) continue;
      final target = await _resolve(relative);
      await target.parent.create(recursive: true);
      await target.writeAsBytes(base64Decode(entry.value), flush: true);
    }
  }

  /// 删除不再被任何记录引用的图片。
  static Future<void> pruneOrphans(Set<String> keepRelativePaths) async {
    final keep = keepRelativePaths.map(_normalize).toSet();
    final root = await _root();
    if (!await root.exists()) return;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relative = p
          .relative(entity.path, from: root.path)
          .replaceAll('\\', '/');
      if (keep.contains(relative)) continue;
      try {
        await entity.delete();
      } on FileSystemException {
        // 单个文件删除失败时忽略，避免影响其他文件清理。
      }
    }
  }

  /// 打开相机或相册选图并保存，返回相对路径；用户取消时返回 null。
  static Future<String?> pickAndSave({
    required String folder,
    bool camera = false,
  }) async {
    final XFile? picked;
    try {
      picked = await ImagePicker().pickImage(
        source: camera ? ImageSource.camera : ImageSource.gallery,
        maxWidth: kImageMaxSide.toDouble(),
        maxHeight: kImageMaxSide.toDouble(),
        imageQuality: kImageQuality,
      );
    } on PlatformException catch (e) {
      throw ImageStoreException(e.message ?? '无法打开相机或相册');
    } on MissingPluginException {
      throw const ImageStoreException('当前平台不支持拍照或选图');
    }
    if (picked == null) return null;
    return save(picked.path, folder: folder);
  }
}

class ImageStoreException implements Exception {
  const ImageStoreException(this.message);

  final String message;

  @override
  String toString() => message;
}
