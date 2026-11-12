#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
out=build/native-host
flags=(-DCMAKE_BUILD_TYPE=Release)
if [ "${1:-}" = "--sanitize" ]; then
  out=build/native-asan
  flags=(-DCMAKE_BUILD_TYPE=RelWithDebInfo -DTT_SANITIZE=ON)
fi
cmake -S native -B "$out" "${flags[@]}"
cmake --build "$out" --parallel
