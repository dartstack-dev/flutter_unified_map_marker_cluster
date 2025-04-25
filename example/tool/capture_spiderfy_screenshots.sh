#!/bin/sh
# Captures screenshots of the demo app's Spiderfy page while spiderfy_screenshot_test.dart runs:
# the cluster before the tap, the open spider, the closed spider.
#
#   example/tool/capture_spiderfy_screenshots.sh <ios-udid|macos> [output-dir]
#
# On an iOS simulator the device is captured with `simctl io screenshot`; on macOS the whole screen
# is captured with `screencapture` (the test keeps its window in front), so run it on the machine.
set -e
UDID=${1:?usage: capture_spiderfy_screenshots.sh <ios-udid|macos> [output-dir]}
OUT=${2:-$(dirname "$0")/../../screenshots}
LOG=/tmp/spiderfy_screenshots.log
mkdir -p "$OUT"
cd "$(dirname "$0")/.."

if [ "$UDID" = "macos" ]; then
  flutter test integration_test/spiderfy_screenshot_test.dart -d macos > $LOG 2>&1 &
else
  flutter test integration_test/spiderfy_screenshot_test.dart -d $UDID > $LOG 2>&1 &
fi
TEST_PID=$!

snap() {
  if [ "$UDID" = "macos" ]; then
    screencapture -x "$OUT/$2"
  else
    xcrun simctl io $UDID screenshot "$OUT/$2"
  fi
  echo "captured $2"
}

wait_for() {
  i=0
  while ! grep -q "$1" $LOG 2>/dev/null; do
    sleep 1
    i=$((i+1))
    if [ $i -gt 240 ]; then echo "timeout waiting for $1"; exit 1; fi
  done
}

wait_for CLUSTER-READY
sleep 6
snap "$OUT" spiderfy-cluster.png

wait_for SPIDER-READY
sleep 4
snap "$OUT" spiderfy-open.png

wait_for SPIDER-CLOSED
sleep 4
snap "$OUT" spiderfy-closed.png

wait $TEST_PID
echo "test finished"
tail -5 $LOG
