import 'package:flutter/services.dart';

/// 通过 Android Storage Access Framework 读写用户选择的文件。
/// 其他平台或测试环境会抛出 [DocumentStorageException]。
class DocumentStorage {
  const DocumentStorage();

  static const MethodChannel _channel = MethodChannel('yuying/documents');

  Future<String?> pickSaveLocation(String fileName) async {
    try {
      return await _channel.invokeMethod<String>('pickSaveLocation', {
        'fileName': fileName,
      });
    } on MissingPluginException {
      throw const DocumentStorageException('当前平台不支持系统文件保存');
    } on PlatformException catch (e) {
      throw DocumentStorageException(e.message ?? '无法打开系统文件选择器');
    }
  }

  Future<String?> pickOpenFile() async {
    try {
      return await _channel.invokeMethod<String>('pickOpenFile');
    } on MissingPluginException {
      throw const DocumentStorageException('当前平台不支持选择文件');
    } on PlatformException catch (e) {
      throw DocumentStorageException(e.message ?? '无法打开系统文件选择器');
    }
  }

  Future<String> readText(String uri) async {
    try {
      final content = await _channel.invokeMethod<String>('readText', {
        'uri': uri,
      });
      if (content == null) throw const DocumentStorageException('文件内容为空');
      return content;
    } on MissingPluginException {
      throw const DocumentStorageException('当前平台不支持读取文件');
    } on PlatformException catch (e) {
      throw DocumentStorageException(e.message ?? '读取文件失败');
    }
  }

  Future<void> writeText(String uri, String content) async {
    try {
      await _channel.invokeMethod<bool>('writeText', {
        'uri': uri,
        'content': content,
      });
    } on MissingPluginException {
      throw const DocumentStorageException('当前平台不支持写入文件');
    } on PlatformException catch (e) {
      throw DocumentStorageException(e.message ?? '写入文件失败');
    }
  }
}

class DocumentStorageException implements Exception {
  const DocumentStorageException(this.message);

  final String message;

  @override
  String toString() => message;
}
