#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
BACKUP="$(mktemp -d)"
cp -R "$ROOT/lib" "$BACKUP/lib"
cp -R "$ROOT/assets" "$BACKUP/assets"
cp "$ROOT/pubspec.yaml" "$BACKUP/pubspec.yaml"
mkdir -p "$BACKUP/android_main"
cp -R "$ROOT/android/app/src/main/." "$BACKUP/android_main/"
cd "$ROOT"
flutter create . --project-name expense_tracker --org com.example --platforms android --overwrite
rm -rf "$ROOT/lib" "$ROOT/assets"
cp -R "$BACKUP/lib" "$ROOT/lib"
cp -R "$BACKUP/assets" "$ROOT/assets"
cp "$BACKUP/pubspec.yaml" "$ROOT/pubspec.yaml"
cp -R "$BACKUP/android_main/." "$ROOT/android/app/src/main/"
rm -rf "$BACKUP"
echo "Bootstrap complete."
