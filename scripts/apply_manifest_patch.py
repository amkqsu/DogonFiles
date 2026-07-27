#!/usr/bin/env python3
"""
apply_manifest_patch.py <AndroidManifest.xml> <AndroidManifest.snippet.xml>

android-patch/AndroidManifest.snippet.xml icerigini hedef AndroidManifest.xml'e
DOGRU yerlere boler:
  - <uses-permission .../>  -> <manifest> kok seviyesine, <application ...>
                               acilis etiketinden HEMEN ONCE (kardes oge).
  - <provider>...</provider> (ve diger her sey) -> <application ...> acilis
                               etiketinin HEMEN ICINE.

Android <uses-permission> her zaman <manifest>'in dogrudan alt ogesi olmalidir;
<application> icine konursa AAPT "unexpected element <uses-permission> found
in <manifest><application>" hatasi verir.
"""
import re
import sys


def main():
    if len(sys.argv) != 3:
        print("Kullanim: apply_manifest_patch.py <manifest> <snippet>", file=sys.stderr)
        sys.exit(2)

    manifest_path, snippet_path = sys.argv[1], sys.argv[2]

    with open(manifest_path, "r", encoding="utf-8") as f:
        manifest = f.read()

    with open(snippet_path, "r", encoding="utf-8") as f:
        snippet = f.read()

    snippet_xml = re.sub(r"<!--.*?-->", "", snippet, flags=re.DOTALL).strip()

    permission_pattern = re.compile(r"<uses-permission\b[^>]*/>", flags=re.DOTALL)
    permissions = permission_pattern.findall(snippet_xml)
    rest_xml = permission_pattern.sub("", snippet_xml).strip()

    match = re.search(r"<application\b[^>]*>", manifest, flags=re.DOTALL)
    if not match:
        print("HATA: <application> etiketi bulunamadi.", file=sys.stderr)
        sys.exit(1)

    app_tag_start = match.start()
    app_tag_end = match.end()

    new_manifest = manifest

    if rest_xml:
        new_manifest = (
            new_manifest[:app_tag_end]
            + "\n\n"
            + rest_xml
            + "\n"
            + new_manifest[app_tag_end:]
        )

    if permissions:
        perm_block = "\n".join(permissions)
        new_manifest = (
            new_manifest[:app_tag_start]
            + perm_block
            + "\n\n    "
            + new_manifest[app_tag_start:]
        )

    with open(manifest_path, "w", encoding="utf-8") as f:
        f.write(new_manifest)


if __name__ == "__main__":
    main()
