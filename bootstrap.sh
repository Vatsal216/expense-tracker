#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
BACKUP="$(mktemp -d)"
cp -R "$ROOT/lib" "$BACKUP/lib"
cp "$ROOT/pubspec.yaml" "$BACKUP/pubspec.yaml"
cp "$ROOT/README.md" "$BACKUP/README.md"
mkdir -p "$BACKUP/android_app_src"
cp -R "$ROOT/android/app/src/main" "$BACKUP/android_app_src/main"
cd "$ROOT"
flutter create . --project-name expense_tracker --org com.example --platforms android --overwrite
rm -rf "$ROOT/lib"
cp -R "$BACKUP/lib" "$ROOT/lib"
cp "$BACKUP/pubspec.yaml" "$ROOT/pubspec.yaml"
cp "$BACKUP/README.md" "$ROOT/README.md"
rm -rf "$ROOT/android/app/src/main"
cp -R "$BACKUP/android_app_src/main" "$ROOT/android/app/src/main"
rm -rf "$BACKUP"
echo "Bootstrap complete. Run: flutter pub get && flutter run"
