#!/usr/bin/env bash
set -euo pipefail

PROJ_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  echo "Build the TeamTalk Flutter Android app."
  echo
  echo "Usage: scripts/build.sh [options]"
  echo
  echo "Options:"
  echo "  --mode    release|debug|profile build mode (default: release)"
  echo "  --abi     all|arm64|arm|x64     target ABI (default: all: 3 splits + universal)"
  echo "  --install                       adb install the built APK afterwards"
  echo "  --no-prereqs                    skip flutter pub get"
  echo "  -h, --help                      show this help"
}

log() { echo "[build.sh] $*"; }
die() { echo "[build.sh] ERROR: $*" >&2; exit 1; }

IS_WSL=0
IS_WIN_SHELL=0
WIN_DIR=""
TT_ABI_FILTER=""

if grep -qi microsoft /proc/version 2>/dev/null && command -v cmd.exe >/dev/null 2>&1; then
  IS_WSL=1
  IS_WIN_SHELL=1
  WIN_DIR="$(wslpath -w "$PROJ_DIR")"
elif [ -n "${MSYSTEM:-}" ] || command -v cygpath >/dev/null 2>&1; then
  if command -v cmd.exe >/dev/null 2>&1; then
    IS_WIN_SHELL=1
    WIN_DIR="$(cygpath -w "$PROJ_DIR" 2>/dev/null || echo "$PROJ_DIR")"
  fi
fi

cmd() {
  if [ "$IS_WIN_SHELL" = "1" ]; then
    MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' command cmd.exe "$@"
  else
    command cmd.exe "$@"
  fi
}

win_path_exists() {
  cmd /c "if exist $1 echo OK" 2>/dev/null | grep -q '^OK$'
}

to_win_path() {
  cygpath -w "$1" 2>/dev/null || wslpath -w "$1"
}

run_flutter() {
  if [ "$IS_WIN_SHELL" = "1" ]; then
    local flutter_cmd="flutter"
    if ! cmd /c "where flutter >nul 2>nul" 2>/dev/null; then
      local candidate
      for candidate in \
        "C:\\dev\\flutter\\bin\\flutter.bat" \
        "C:\\flutter\\bin\\flutter.bat" \
        "C:\\ProgramData\\chocolatey\\bin\\flutter.bat" \
        "C:\\src\\flutter\\bin\\flutter.bat"; do
        if win_path_exists "$candidate"; then
          log "Found flutter at $candidate"
          flutter_cmd=$candidate
          break
        fi
      done
    fi
    cmd /c "cd /d $WIN_DIR && set TT_ABI_FILTER=$TT_ABI_FILTER && ${flutter_cmd} $*"
  else
    ( cd "$PROJ_DIR" && flutter $* )
  fi
}

MODE="release"
ABI="all"
INSTALL=0
SKIP_PREREQS=0

while [ $# -gt 0 ]; do
  case "$1" in
    --mode) MODE="$2"; shift 2 ;;
    --abi) ABI="$2"; shift 2 ;;
    --install) INSTALL=1; shift ;;
    --no-prereqs) SKIP_PREREQS=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

case "$ABI" in
  all) ABI_ARGS="" ;;
  arm64) ABI_ARGS="--target-platform=android-arm64"; TT_ABI_FILTER="arm64-v8a" ;;
  arm) ABI_ARGS="--target-platform=android-arm"; TT_ABI_FILTER="armeabi-v7a" ;;
  x64) ABI_ARGS="--target-platform=android-x64"; TT_ABI_FILTER="x86_64" ;;
  *) die "Unknown abi: $ABI" ;;
esac
export TT_ABI_FILTER

if [ "$SKIP_PREREQS" = "0" ]; then
  log "Running flutter pub get ..."
  run_flutter pub get >/dev/null
fi

echo
echo "==> Building mode=$MODE abi=$ABI"
rm -rf \
  "$PROJ_DIR/.dart_tool/flutter_build" \
  "$PROJ_DIR/build/app/intermediates/flutter" \
  "$PROJ_DIR/build/app/intermediates/merged_jni_libs" \
  "$PROJ_DIR/build/app/intermediates/merged_native_libs" \
  "$PROJ_DIR/build/app/intermediates/stripped_native_libs" \
  "$PROJ_DIR/build/app/outputs/apk/$MODE" \
  2>/dev/null || true

EXTRA=""
[ "$MODE" = "release" ] && EXTRA="--split-debug-info=build/app/outputs/symbols"
run_flutter build apk "--$MODE" $ABI_ARGS $EXTRA

OUT_DIR="$PROJ_DIR/build/app/outputs/apk/$MODE"
echo "Artifacts in $OUT_DIR:"
ls -1sh "$OUT_DIR"/*.apk 2>/dev/null || echo "  (no APKs found)"

if [ "$INSTALL" = "1" ]; then
  APK="$(ls -1 "$OUT_DIR"/*arm64*.apk 2>/dev/null | head -1)"
  [ -z "$APK" ] && APK="$(ls -1 "$OUT_DIR"/*.apk 2>/dev/null | head -1)"
  if [ -n "$APK" ]; then
    echo "Installing $APK"
    if [ "$IS_WIN_SHELL" = "1" ]; then
      cmd /c "cd /d $WIN_DIR && adb install -r $(to_win_path "$APK")"
    else
      adb install -r "$APK"
    fi
  fi
fi
