### Downloads

Pick the APK for your phone's processor: `arm64-v8a` for almost all current phones, `armeabi-v7a` for older 32-bit ones, `x86_64` for emulators. `universal` works everywhere but is larger. TeamTalkX needs Android 10 or newer.

Once installed, TeamTalkX checks this page for updates itself (Settings → Updates; turn on "Include beta versions" to get betas too).

### Verifying a download

`SHA256SUMS.txt` lists each APK's checksum:

```sh
sha256sum --check --ignore-missing SHA256SUMS.txt
```

Each APK also carries a build provenance attestation, which proves it was built from this repository's {tag} by its release workflow:

```sh
gh attestation verify TeamTalkX-{version}-arm64-v8a.apk --repo 25k1/TeamTalkX
```

`TeamTalkX-{version}-debug-symbols.zip` decodes stack traces from this version's logs and diagnostics exports (`flutter symbolize`).

### Upgrading from TeamTalkX 1.x

Versions before 2.0 were signed with a different key, so Android won't install 2.x over them: uninstall the old app first, then install this one. TeamTalkX 1.x can't export its settings, so add your servers and set your preferences again; chat history isn't carried over. From 2.0 on, Settings → Settings file → Export settings saves your settings and servers (with a passphrase, also their passwords) for the next time you move.
