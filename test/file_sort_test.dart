import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/app/files/file_providers.dart';
import 'package:teamtalkx/src/app/files/sort.dart';
import 'package:teamtalkx/src/domain/models.dart';

TtRemoteFile file(
  String name, {
  int size = 0,
  String owner = '',
  String uploaded = '',
}) => TtRemoteFile(
  channelId: 1,
  fileId: name.hashCode,
  fileName: name,
  fileSize: size,
  username: owner,
  uploadTime: uploaded,
);

List<String> names(List<TtRemoteFile> files) =>
    files.map((f) => f.fileName).toList();

void main() {
  final files = [
    file('banana.txt', size: 300, owner: 'carol', uploaded: '2026/01/03 10:00'),
    file('Apple.txt', size: 100, owner: 'alice', uploaded: '2026/03/01 09:00'),
    file('cherry.txt', size: 200, owner: 'bob', uploaded: '2026/02/02 08:00'),
  ];

  group('sortAndFilterFiles sorting', () {
    test('by name is case-insensitive ascending', () {
      expect(
        names(
          sortAndFilterFiles(files, const SortState(FileSortField.name), ''),
        ),
        ['Apple.txt', 'banana.txt', 'cherry.txt'],
      );
    });

    test('by name descending reverses', () {
      expect(
        names(
          sortAndFilterFiles(
            files,
            const SortState(FileSortField.name, ascending: false),
            '',
          ),
        ),
        ['cherry.txt', 'banana.txt', 'Apple.txt'],
      );
    });

    test('by size ascending', () {
      expect(
        names(
          sortAndFilterFiles(files, const SortState(FileSortField.size), ''),
        ),
        ['Apple.txt', 'cherry.txt', 'banana.txt'],
      );
    });

    test('by owner ascending', () {
      expect(
        names(
          sortAndFilterFiles(files, const SortState(FileSortField.owner), ''),
        ),
        ['Apple.txt', 'cherry.txt', 'banana.txt'],
      );
    });

    test('by upload date ascending (year-first string order)', () {
      expect(
        names(
          sortAndFilterFiles(files, const SortState(FileSortField.date), ''),
        ),
        ['banana.txt', 'cherry.txt', 'Apple.txt'],
      );
    });

    test('ties break by name for stability', () {
      final tied = [
        file('zed.txt', size: 100),
        file('alpha.txt', size: 100),
        file('mid.txt', size: 100),
      ];
      expect(
        names(
          sortAndFilterFiles(tied, const SortState(FileSortField.size), ''),
        ),
        ['alpha.txt', 'mid.txt', 'zed.txt'],
      );
    });
  });

  group('sortAndFilterFiles filtering', () {
    test('matches a case-insensitive substring of the name', () {
      expect(
        names(
          sortAndFilterFiles(files, const SortState(FileSortField.name), 'ERR'),
        ),
        ['cherry.txt'],
      );
    });

    test('blank query returns everything', () {
      expect(
        sortAndFilterFiles(files, const SortState(FileSortField.name), '   '),
        hasLength(3),
      );
    });

    test('no match returns empty', () {
      expect(
        sortAndFilterFiles(files, const SortState(FileSortField.name), 'xyz'),
        isEmpty,
      );
    });
  });
}
