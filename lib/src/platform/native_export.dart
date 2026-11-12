import 'native_channel.dart';

class PublishedFile {
  const PublishedFile({required this.uri, required this.path});

  final String uri;

  final String path;
}

abstract interface class Downloads {
  Future<String> saveText(String fileName, String content, {String mimeType});

  Future<bool> exists(String fileName);

  Future<void> remove(String fileName);

  Future<PublishedFile> publish(String path, String fileName);

  Future<bool> open(String uri);
}

class AndroidDownloads implements Downloads {
  final _channel = NativeChannel('export');

  @override
  Future<String> saveText(
    String fileName,
    String content, {
    String mimeType = '',
  }) async =>
      await _channel.invoke<String>('saveToDownloads', {
        'fileName': fileName,
        'content': content,
        'mimeType': mimeType,
      }) ??
      fileName;

  @override
  Future<bool> exists(String fileName) async =>
      await _channel.invoke<bool>('exists', {'fileName': fileName}) ?? false;

  @override
  Future<void> remove(String fileName) =>
      _channel.invoke<bool>('remove', {'fileName': fileName});

  @override
  Future<PublishedFile> publish(String path, String fileName) async {
    final result = await _channel.invoke<Map<Object?, Object?>>('publish', {
      'path': path,
      'fileName': fileName,
    });
    return PublishedFile(
      uri: result?['uri'] as String? ?? path,
      path: result?['path'] as String? ?? fileName,
    );
  }

  @override
  Future<bool> open(String uri) async =>
      await _channel.invoke<bool>('open', {'uri': uri}) ?? false;
}
