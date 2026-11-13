# TeamTalkX

[![CI](https://github.com/25k1/TeamTalkX/actions/workflows/ci.yml/badge.svg)](https://github.com/25k1/TeamTalkX/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/25k1/TeamTalkX?include_prereleases&label=release)](https://github.com/25k1/TeamTalkX/releases)
[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-blue)](LICENSE)
[![Donate with PayPal](https://img.shields.io/badge/donate-PayPal-00457C?logo=paypal)](https://paypal.me/gozaltech)

An accessible [TeamTalk 5](https://bearware.dk) client for Android, written in Flutter. It implements the TeamTalk 5 protocol itself and does not use the TeamTalk SDK.

Download the APK from [Releases](https://github.com/25k1/TeamTalkX/releases) (Minimum Supported android is Android 10+).

## Features

- Push-to-talk on hardware and media keys; voice activation (level or Silero vad)
- Encrypted servers (TLS)
- Channel and private chat with history, file transfers, recording
- User and channel administration
- Event sounds and sound packs
- Public server list, `.tt` files, `tt://` links, BearWare.dk login
- Settings export/import, in-app updates

## Building

Needs Flutter 3.47.9 and the Android SDK.

```sh
flutter pub get
scripts/build.sh --mode debug --abi arm64
scripts/check.sh
```

Release builds need the signing key in `android/key.properties`.

## Contributing

Open a pull request against `master` with a [Conventional Commits](https://www.conventionalcommits.org/) title; CI must pass.

## Contact

- [GitHub Issues](https://github.com/25k1/TeamTalkX/issues)
- Telegram: [@gozaltech](https://t.me/gozaltech)

## License

[GPL-3.0](LICENSE)
