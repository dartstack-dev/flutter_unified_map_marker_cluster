#!/usr/bin/env bash
# Runs each file of integration_test/ in its own `flutter test` on one device and sums up. On macOS the Flutter tool
# cannot launch the desktop app again for the second file of a single `flutter test integration_test -d macos`.
#
#   example/tool/integration_tests.sh <device> [file ...]
set -u
cd "$(dirname "$0")/.." || exit 1
device=${1:?usage: tool/integration_tests.sh <device> [integration_test/<file> ...]}
shift
files=("$@")
if [ ${#files[@]} -eq 0 ]; then files=(integration_test/*_test.dart); fi

failed=()
for file in "${files[@]}"; do
  echo "=== $file on $device"
  started=$(date +%s)
  if flutter test "$file" -d "$device"; then
    echo "=== $file passed in $(($(date +%s) - started)) s"
  else
    echo "=== $file FAILED after $(($(date +%s) - started)) s"
    failed+=("$file")
  fi
  if [ "$device" = macos ]; then
    # The test app must be gone before the next launch.
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      pgrep -f 'flutter_unified_map_marker_cluster_example.app/Contents/MacOS' >/dev/null || break
      sleep 1
    done
    pkill -f 'flutter_unified_map_marker_cluster_example.app/Contents/MacOS' 2>/dev/null || true
  fi
done

echo "=== ${#files[@]} files, ${#failed[@]} failed ${failed[*]:-}"
[ ${#failed[@]} -eq 0 ]
