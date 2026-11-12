library;

enum RecordingMode { mixed, perUser }

enum RecordingFormat {
  wav('wav'),
  oggOpus('ogg');

  const RecordingFormat(this.extension);

  final String extension;
}

const int mixedRecordingUserId = 0;

String recordingFileName(int userId, RecordingFormat format) =>
    userId == mixedRecordingUserId
    ? 'mixed.${format.extension}'
    : 'user-$userId.${format.extension}';

int? recordingFileUserId(String name) {
  final match = RegExp(r'^user-(\d+)\.\w+$').firstMatch(name);
  return match == null ? null : int.parse(match.group(1)!);
}
