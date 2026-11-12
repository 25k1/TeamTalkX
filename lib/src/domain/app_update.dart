library;

import 'dart:convert';

class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch, {this.beta});

  final int major;
  final int minor;
  final int patch;

  final int? beta;

  bool get isBeta => beta != null;

  static final _pattern = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)(?:-beta\.(\d+))?$');

  static AppVersion? tryParse(String text) {
    final m = _pattern.firstMatch(text.trim());
    if (m == null) return null;
    return AppVersion(
      int.parse(m[1]!),
      int.parse(m[2]!),
      int.parse(m[3]!),
      beta: m[4] == null ? null : int.parse(m[4]!),
    );
  }

  @override
  int compareTo(AppVersion other) {
    for (final (a, b) in [
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
    ]) {
      if (a != b) return a.compareTo(b);
    }
    final aBeta = beta;
    final bBeta = other.beta;
    if (aBeta == bBeta) return 0;
    if (aBeta == null) return 1;
    if (bBeta == null) return -1;
    return aBeta.compareTo(bBeta);
  }

  bool operator >(AppVersion other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) =>
      other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch, beta);

  @override
  String toString() =>
      '$major.$minor.$patch${beta == null ? '' : '-beta.$beta'}';
}

class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.url,
    required this.size,
  });

  final String name;
  final String url;
  final int size;
}

class AppRelease {
  const AppRelease({
    required this.version,
    required this.prerelease,
    required this.notes,
    required this.pageUrl,
    required this.assets,
  });

  final AppVersion version;
  final bool prerelease;

  final String notes;
  final String pageUrl;
  final List<ReleaseAsset> assets;

  ReleaseAsset? apkFor(List<String> abis) {
    ReleaseAsset? named(String abi) => assets
        .where((a) => a.name == 'TeamTalkX-$version-$abi.apk')
        .firstOrNull;
    for (final abi in abis) {
      final asset = named(abi);
      if (asset != null) return asset;
    }
    return named('universal');
  }

  ReleaseAsset? get checksums =>
      assets.where((a) => a.name == 'SHA256SUMS.txt').firstOrNull;
}

List<AppRelease> parseReleases(String json) {
  final list = jsonDecode(json);
  if (list is! List) throw const FormatException('Not a release list');
  return [
    for (final r in list.whereType<Map<String, Object?>>())
      if (r['draft'] != true)
        if (AppVersion.tryParse(r['tag_name'] as String? ?? '')
            case final version?)
          AppRelease(
            version: version,
            prerelease: r['prerelease'] == true,
            notes: r['body'] as String? ?? '',
            pageUrl: r['html_url'] as String? ?? '',
            assets: [
              for (final a
                  in (r['assets'] as List? ?? const [])
                      .whereType<Map<String, Object?>>())
                ReleaseAsset(
                  name: a['name'] as String? ?? '',
                  url: a['browser_download_url'] as String? ?? '',
                  size: (a['size'] as num?)?.toInt() ?? 0,
                ),
            ],
          ),
  ];
}

AppRelease? newestUpdate(
  List<AppRelease> releases,
  AppVersion current, {
  required bool betas,
}) {
  AppRelease? best;
  for (final r in releases) {
    if (r.prerelease && !betas) continue;
    if (!(r.version > current)) continue;
    if (best == null || r.version > best.version) best = r;
  }
  return best;
}

String? checksumFor(String sums, String fileName) {
  for (final line in const LineSplitter().convert(sums)) {
    final parts = line.trim().split(RegExp(r'\s+\*?'));
    if (parts.length == 2 && parts[1] == fileName) {
      return parts[0].toLowerCase();
    }
  }
  return null;
}
