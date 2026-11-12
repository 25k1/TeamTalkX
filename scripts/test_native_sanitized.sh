#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
lib=$PWD/build/native-asan/libtt_audio.so
cc=${CC:-cc}
runtimes=""
for name in libasan.so libubsan.so; do
  path=$("$cc" -print-file-name="$name")
  [ -f "$path" ] && runtimes="$runtimes $path"
done

export ASAN_OPTIONS=detect_leaks=0:abort_on_error=1:allocator_may_return_null=1
export UBSAN_OPTIONS=print_stacktrace=1:halt_on_error=1
LD_PRELOAD="${runtimes# }" flutter test --concurrency=1 \
  --dart-define=TT_NATIVE_LIB="$lib" test/native "$@"
