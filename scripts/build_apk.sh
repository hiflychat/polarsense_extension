#!/usr/bin/env bash
set -e

echo "=========================================="
echo " PolarSense Extension - APK Build Script"
echo "=========================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_DIR"

if ! command -v flutter &> /dev/null; then
    echo "❌ Error: 'flutter' command not found."
    echo "Please install Flutter SDK (https://flutter.dev/docs/get-started/install)"
    echo "or use the GitHub Actions CI workflow in .github/workflows/build_apk.yml."
    exit 1
fi

echo "📦 Fetching Flutter dependencies..."
flutter pub get

echo "🧪 Running unit tests..."
flutter test

echo "🔨 Building Release APK..."
flutter build apk --release

APK_PATH="$PROJECT_DIR/build/app/outputs/flutter-apk/app-release.apk"

if [ -f "$APK_PATH" ]; then
    echo "=========================================="
    echo "✅ APK successfully generated at:"
    echo "$APK_PATH"
    echo "=========================================="
    ls -lh "$APK_PATH"
else
    echo "❌ Build finished but APK was not found at expected path."
    exit 1
fi
