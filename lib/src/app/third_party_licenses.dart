import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

@visibleForTesting
typedef ThirdPartyLicense = ({
  List<String> packages,
  String? copyright,
  List<String> files,
});

@visibleForTesting
const thirdPartyLicenses = <ThirdPartyLicense>[
  (packages: ['Opus'], copyright: null, files: ['opus.txt']),
  (packages: ['Speex'], copyright: null, files: ['speex.txt']),
  (packages: ['RNNoise'], copyright: null, files: ['rnnoise.txt']),
  (
    packages: ['Oboe'],
    copyright: 'Copyright 2015 The Android Open Source Project',
    files: ['apache-2.0.txt'],
  ),
  (
    packages: ['Sonic'],
    copyright: 'Copyright 2010 Bill Cox',
    files: ['apache-2.0.txt'],
  ),
  (packages: ['Silero VAD'], copyright: null, files: ['silero-vad.txt']),
  (
    packages: ['AndroidX', 'Kotlin standard library'],
    copyright: null,
    files: ['apache-2.0.txt'],
  ),
];

const _dir = 'assets/licenses';

void registerThirdPartyLicenses({AssetBundle? bundle}) {
  LicenseRegistry.addLicense(() => _load(bundle ?? rootBundle));
}

Stream<LicenseEntry> _load(AssetBundle bundle) async* {
  yield LicenseEntryWithLineBreaks(const [
    'TeamTalkX',
  ], await bundle.loadString('LICENSE', cache: false));
  for (final license in thirdPartyLicenses) {
    final texts = [
      ?license.copyright,
      for (final file in license.files)
        await bundle.loadString('$_dir/$file', cache: false),
    ];
    yield LicenseEntryWithLineBreaks(license.packages, texts.join('\n\n'));
  }
}
