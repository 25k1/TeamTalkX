#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

usage() {
  echo "Run the checks CI runs, before pushing."
  echo
  echo "Usage: scripts/check.sh [--quick] [--e2e]"
  echo
  echo "  --quick  format and analyze only"
  echo "  --e2e    also the E2E tests, against the teamtalkx-e2e Docker container"
}

QUICK=0
E2E=0
while [ $# -gt 0 ]; do
  case "$1" in
    --quick) QUICK=1 ;;
    --e2e) E2E=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

WINDOWS=0
WIN_ROOT=""
if grep -qi microsoft /proc/version 2>/dev/null && command -v cmd.exe > /dev/null 2>&1; then
  WINDOWS=1
  WIN_ROOT="$(wslpath -w "$ROOT")"
elif [ -n "${MSYSTEM:-}" ] || command -v cygpath > /dev/null 2>&1; then
  WINDOWS=1
  WIN_ROOT="$(cygpath -w "$ROOT")"
fi

on_windows() {
  MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' cmd.exe /c "cd /d $WIN_ROOT && $*"
}

tool() {
  if [ "$WINDOWS" = "1" ]; then on_windows "$*"; else "$@"; fi
}

step() {
  echo
  echo "==> $*"
}

skipped=()

step "Format"
tool dart format --output=none --set-exit-if-changed lib test tool

step "Analyze"
tool flutter analyze

if [ "$QUICK" = "1" ]; then
  echo
  echo "Quick checks passed."
  exit 0
fi

step "Native module for the host"
if [ "$WINDOWS" = "1" ]; then
  on_windows 'scripts\build_native_host.bat'
  NATIVE_LIB="$WIN_ROOT\\build\\native-host\\tt_audio.dll"
else
  bash scripts/build_native_host.sh
  NATIVE_LIB="$ROOT/build/native-host/libtt_audio.so"
fi

step "Tests"
tool flutter test --dart-define=TT_NATIVE_LIB="$NATIVE_LIB"

step "Kotlin unit tests and Android Lint"
if [ -f android/local.properties ] && [ -f android/gradlew ]; then
  if [ "$WINDOWS" = "1" ]; then
    on_windows 'cd android && gradlew.bat :app:testDebugUnitTest :app:lintDebug --console=plain -q'
  else
    (cd android && ./gradlew :app:testDebugUnitTest :app:lintDebug --console=plain -q)
  fi
else
  skipped+=("Kotlin tests and Lint: build the app once with scripts/build.sh first")
fi

step "Workflow lint"
if command -v actionlint > /dev/null 2>&1; then
  actionlint
else
  skipped+=("actionlint: not installed (https://github.com/rhysd/actionlint)")
fi

if [ "$E2E" = "1" ]; then
  step "E2E"
  started=0
  if [ -z "$(docker ps -q --filter name='^teamtalkx-e2e$')" ]; then
    docker image inspect teamtalkx-e2e > /dev/null 2>&1 ||
      docker build -t teamtalkx-e2e test/e2e/server
    docker rm -f teamtalkx-e2e > /dev/null 2>&1 || true
    docker run -d --name teamtalkx-e2e \
      -p 10333:10333 -p 10333:10333/udp -p 10443:10443 teamtalkx-e2e > /dev/null
    started=1
    trap 'docker rm -f teamtalkx-e2e > /dev/null 2>&1 || true' EXIT
    sleep 3
  fi
  tool flutter test --dart-define=TT_E2E_HOST=127.0.0.1 \
    --dart-define=TT_NATIVE_LIB="$NATIVE_LIB" test/e2e
  [ "$started" = "1" ] && echo "Stopping the teamtalkx-e2e container."
fi

echo
echo "All checks passed."
for s in "${skipped[@]}"; do
  echo "Skipped: $s"
done
