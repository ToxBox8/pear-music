#!/bin/bash
# Uso: bench.sh <etiqueta> [nav|all]
PKG=app.libremusic.perf
A="timeout 20 adb shell"
echo "### $1"
$A dumpsys display | grep -o "renderFrameRate [0-9.]*" | head -1
if [ "$2" != "nav" ]; then
for i in 1 2 3; do $A am force-stop $PKG; sleep 1.5; $A am start -W -n $PKG/app.libremusic.MainActivity | grep -E "TotalTime"; done
sleep 5
fi
$A dumpsys gfxinfo $PKG reset >/dev/null
for r in 1 2 3; do for x in 658 890 192; do $A input tap $x 2317; sleep 0.9; done; done
for r in 1 2 3; do $A input swipe 540 1700 540 500 250; sleep 0.7; $A input swipe 540 500 540 1700 250; sleep 0.7; done
$A input tap 658 2317; sleep 1; $A input tap 790 780; sleep 1.3; $A input keyevent 4; sleep 1.1; $A input tap 300 780; sleep 1.3; $A input keyevent 4; sleep 1.1
$A input tap 890 2317; sleep 1; $A input tap 540 478; sleep 1.3; $A input keyevent 4; sleep 1.1
$A input tap 192 2317; sleep 1
$A dumpsys gfxinfo $PKG | grep -E "^Total frames|^Janky frames|percentile|^Number Slow UI|^Number Frame deadline" | head -9
if [ "$2" != "nav" ]; then
timeout 5 adb logcat -c
$A input tap 425 2317; sleep 12
for i in 1 2 3 4 5 6; do $A input swipe 540 1600 540 500 200; sleep 7; done
timeout 5 adb logcat -d -s LMPerf | grep reel_start
$A input tap 192 2317
fi
