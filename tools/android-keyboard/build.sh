#!/bin/sh
set -eu
: "${R8_JAR:?Set R8_JAR to the official r8.jar download}"
TASK_JAVA_BIN=${TASK_JAVA_BIN:-/opt/homebrew/opt/openjdk/bin}
TASK_REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
TASK_BUILD_DIR=$(mktemp -d)
trap 'rm -rf "$TASK_BUILD_DIR"' EXIT
"$TASK_JAVA_BIN/javac" --release 8 -d "$TASK_BUILD_DIR" "$TASK_REPO_ROOT/tools/android-keyboard/KeyboardLayoutBridge.java"
"$TASK_JAVA_BIN/java" -cp "$R8_JAR" com.android.tools.r8.D8 --min-api 26 --output "$TASK_BUILD_DIR" "$TASK_BUILD_DIR/com/airsync/KeyboardLayoutBridge.class"
"$TASK_JAVA_BIN/jar" cf "$TASK_REPO_ROOT/airsync-mac/Resources/KeyboardLayoutBridge.jar" -C "$TASK_BUILD_DIR" classes.dex
