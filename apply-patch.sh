#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "==> DogonRoot native yaması uygulanıyor"

if [ ! -d "android" ]; then
  echo "HATA: android/ dizini bulunamadı. Bu adımdan önce 'npx cap add android' çalıştırılmış olmalı." >&2
  exit 1
fi

PATCH_SRC="android-patch"
JAVA_PKG_DIR="app/src/main/java/lol/dogon/files"

mkdir -p "android/${JAVA_PKG_DIR}"
cp -f "${PATCH_SRC}/app/src/main/java/lol/dogon/files/DogonRootPlugin.java" \
      "android/${JAVA_PKG_DIR}/DogonRootPlugin.java"
cp -f "${PATCH_SRC}/app/src/main/java/lol/dogon/files/MainActivity.java" \
      "android/${JAVA_PKG_DIR}/MainActivity.java"
echo "  - Java plugin dosyaları kopyalandı"

MANIFEST="android/app/src/main/AndroidManifest.xml"
if [ ! -f "$MANIFEST" ]; then
  echo "HATA: $MANIFEST bulunamadı." >&2
  exit 1
fi

if grep -q "moe.shizuku.manager.permission.API_V23" "$MANIFEST"; then
  echo "  - AndroidManifest.xml zaten yamalanmış, atlanıyor"
else
  python3 "${SCRIPT_DIR}/scripts/apply_manifest_patch.py" \
    "$MANIFEST" "${PATCH_SRC}/AndroidManifest.snippet.xml"
  echo "  - AndroidManifest.xml yamalandı"
fi

APP_GRADLE="android/app/build.gradle"
if [ ! -f "$APP_GRADLE" ]; then
  echo "HATA: $APP_GRADLE bulunamadı." >&2
  exit 1
fi

if grep -q "dev.rikka.shizuku" "$APP_GRADLE"; then
  echo "  - app/build.gradle zaten yamalanmış, atlanıyor"
else
  python3 "${SCRIPT_DIR}/scripts/insert_after_marker.py" \
    "$APP_GRADLE" "${PATCH_SRC}/build.gradle.snippet" "dependencies {" "dependencies{"
  echo "  - app/build.gradle yamalandı (Shizuku + libsu bağımlılıkları eklendi)"
fi

SETTINGS_GRADLE="android/settings.gradle"
ROOT_GRADLE="android/build.gradle"

if grep -q "jitpack.io" "$SETTINGS_GRADLE" 2>/dev/null || grep -q "jitpack.io" "$ROOT_GRADLE" 2>/dev/null; then
  echo "  - jitpack reposu zaten eklenmiş, atlanıyor"
elif [ -f "$SETTINGS_GRADLE" ] && grep -q "dependencyResolutionManagement" "$SETTINGS_GRADLE" && grep -q "repositories {" "$SETTINGS_GRADLE"; then
  python3 "${SCRIPT_DIR}/scripts/insert_after_marker.py" \
    "$SETTINGS_GRADLE" "${PATCH_SRC}/root-build.gradle.snippet" "repositories {" "repositories{" \
    --after-anchor "dependencyResolutionManagement"
  echo "  - jitpack reposu settings.gradle içine eklendi"
elif [ -f "$ROOT_GRADLE" ] && grep -q "allprojects" "$ROOT_GRADLE"; then
  python3 "${SCRIPT_DIR}/scripts/insert_after_marker.py" \
    "$ROOT_GRADLE" "${PATCH_SRC}/root-build.gradle.snippet" "repositories {" "repositories{" \
    --after-anchor "allprojects"
  echo "  - jitpack reposu android/build.gradle içine eklendi"
else
  echo "UYARI: jitpack reposu eklenecek uygun bir repositories{} bloğu bulunamadı." >&2
  echo "        Elle 'maven { url \"https://jitpack.io\" }' satırını android/build.gradle" >&2
  echo "        veya android/settings.gradle içindeki repositories{} bloğuna ekleyin." >&2
fi

echo "==> Native yama tamamlandı"
