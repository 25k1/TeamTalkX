import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'log.dart';

class RotatingFileLogSink implements LogSink {
  RotatingFileLogSink(
    this.directory, {
    this.maxBytes = 512 * 1024,
    this.maxFiles = 3,
  }) : assert(maxFiles >= 1, 'keep at least the current file');

  static const baseName = 'teamtalkx';

  final Directory directory;
  final int maxBytes;
  final int maxFiles;

  RandomAccessFile? _file;
  int _size = 0;

  List<File> get files => [
    for (var i = maxFiles - 1; i >= 0; i--) _fileAt(i),
  ].where((f) => f.existsSync()).toList();

  File _fileAt(int index) => File(
    '${directory.path}${Platform.pathSeparator}'
    '${index == 0 ? baseName : '$baseName.$index'}.log',
  );

  @override
  void write(LogRecord record) {
    final bytes = utf8.encode('${record.format()}\n');
    var file = _file ?? _open();
    if (_size > 0 && _size + bytes.length > maxBytes) {
      _rotate();
      file = _open();
    }
    file.writeFromSync(bytes);
    _size += bytes.length;
  }

  RandomAccessFile _open() {
    directory.createSync(recursive: true);
    final file = _fileAt(0).openSync(mode: FileMode.append);
    _size = file.lengthSync();
    return _file = file;
  }

  void _rotate() {
    _file?.closeSync();
    _file = null;
    final oldest = _fileAt(maxFiles - 1);
    if (oldest.existsSync()) oldest.deleteSync();
    for (var i = maxFiles - 2; i >= 0; i--) {
      final f = _fileAt(i);
      if (f.existsSync()) f.renameSync(_fileAt(i + 1).path);
    }
    _size = 0;
  }

  @visibleForTesting
  void close() {
    _file?.closeSync();
    _file = null;
  }
}
