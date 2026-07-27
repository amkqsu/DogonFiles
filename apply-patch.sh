#!/usr/bin/env bash
# ================================================================
# DogonFiles — android-patch/ içeriğini android/ klasörüne uygular.
# ÖNCE çalıştırılması gereken komut: npx cap add android
# Kullanım:  bash apply-patch.sh
# ================================================================
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -d "android" ]; then
  echo "HATA: android/ klasörü yok. Önce şunu çalıştırın: npx cap add android"
  exit 1
fi

APP_MANIFEST="android/app/src/main/AndroidManifest.xml"
APP_GRADLE="android/app/build.gradle"
ROOT_GRADLE="android/build.gradle"
JAVA_DEST="android/app/src/main/java/lol/dogon/files"

echo "1) Native Java kaynak dosyaları kopyalanıyor..."
mkdir -p "$JAVA_DEST"
cp android-patch/app/src/main/java/lol/dogon/files/*.java "$JAVA_DEST/"

echo "2) AndroidManifest.xml düzenleniyor..."
if ! grep -q 'ShizukuProvider' "$APP_MANIFEST"; then
  python3 - "$APP_MANIFEST" <<'PYEOF'
import re, sys
path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1) <manifest ...> kök etiketinin hemen içine uses-permission ekle (application İÇİNE DEĞİL)
if 'moe.shizuku.manager.permission.API_V23' not in content:
    content = re.sub(
        r'(<manifest[^>]*>)',
        r'\1\n    <uses-permission android:name="moe.shizuku.manager.permission.API_V23" />',
        content, count=1
    )

# 2) <application ...> etiketine hardwareAccelerated ekle
if 'android:hardwareAccelerated' not in content:
    content = content.replace('<application', '<application\n        android:hardwareAccelerated="true"', 1)

# 3) <application ...> etiketinin İÇİNE (provider burada olmalı) ShizukuProvider ekle
provider_block = '''
        <provider
            android:name="rikka.shizuku.ShizukuProvider"
            android:authorities="${applicationId}.shizuku"
            android:multiprocess="false"
            android:enabled="true"
            android:exported="true"
            android:permission="android.permission.INTERACT_ACROSS_USERS_FULL" />'''
content = re.sub(r'(<application[^>]*>)', r'\1' + provider_block, content, count=1)

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
print("AndroidManifest.xml güncellendi.")
PYEOF
else
  echo "   (zaten uygulanmış, atlanıyor)"
fi

echo "3) app/build.gradle içine Shizuku/libsu bağımlılıkları ekleniyor..."
if ! grep -q 'dev.rikka.shizuku' "$APP_GRADLE"; then
  python3 - "$APP_GRADLE" <<'PYEOF'
import re, sys
path = sys.argv[1]
with open(path, encoding='utf-8') as f:
    content = f.read()
snippet = open('android-patch/build.gradle.snippet', encoding='utf-8').read()
content = re.sub(r'(dependencies\s*\{)', r'\1\n' + snippet, content, count=1)
with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
print("app/build.gradle güncellendi.")
PYEOF
else
  echo "   (zaten uygulanmış, atlanıyor)"
fi

echo "4) Kök build.gradle içine JitPack repository ekleniyor..."
if ! grep -q 'jitpack.io' "$ROOT_GRADLE"; then
  python3 - "$ROOT_GRADLE" <<'PYEOF'
import re, sys
path = sys.argv[1]
with open(path, encoding='utf-8') as f:
    content = f.read()
snippet = open('android-patch/root-build.gradle.snippet', encoding='utf-8').read()
content = re.sub(r'(allprojects\s*\{\s*repositories\s*\{)', r'\1\n' + snippet, content, count=1)
with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
print("build.gradle (root) güncellendi.")
PYEOF
else
  echo "   (zaten uygulanmış, atlanıyor)"
fi

echo ""
echo "5) minSdkVersion 26'ya yükseltiliyor (Shizuku en az 23 istiyor, proje 26 hedefliyor)..."
VARS_GRADLE="android/variables.gradle"
if [ -f "$VARS_GRADLE" ]; then
  sed -i -E 's/minSdkVersion = [0-9]+/minSdkVersion = 26/' "$VARS_GRADLE"
  echo "   android/variables.gradle güncellendi."
fi

echo ""
echo "Yama tamamlandı. Şimdi derleyebilirsiniz:"
echo "  cd android && ./gradlew assembleDebug"
