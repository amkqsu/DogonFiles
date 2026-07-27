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
# hardwareAccelerated + provider/permission enjekte et (idempotent: zaten varsa tekrar eklemez)
if ! grep -q 'ShizukuProvider' "$APP_MANIFEST"; then
  python3 - "$APP_MANIFEST" <<'PYEOF'
import re, sys
path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# application etiketine hardwareAccelerated ekle
if 'android:hardwareAccelerated' not in content:
    content = content.replace('<application', '<application\n        android:hardwareAccelerated="true"', 1)

snippet = open('android-patch/AndroidManifest.snippet.xml', encoding='utf-8').read()
snippet_body = '\n'.join(l for l in snippet.splitlines() if not l.strip().startswith('<!--') and '===' not in l and not l.strip().startswith('Bu blok') and not l.strip().startswith('Manuel'))
# application açılış tagının hemen sonrasına ekle
content = re.sub(r'(<application[^>]*>)', r'\1\n' + snippet_body, content, count=1)

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
echo "Yama tamamlandı. Şimdi derleyebilirsiniz:"
echo "  cd android && ./gradlew assembleDebug"
