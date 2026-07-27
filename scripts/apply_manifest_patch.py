#!/usr/bin/env python3
import re
import sys


def main():
    if len(sys.argv) != 3:
        print("Kullanım: apply_manifest_patch.py <manifest> <snippet>", file=sys.stderr)
        sys.exit(2)

    manifest_path, snippet_path = sys.argv[1], sys.argv[2]

    with open(manifest_path, "r", encoding="utf-8") as f:
        manifest = f.read()

    with open(snippet_path, "r", encoding="utf-8") as f:
        snippet = f.read()

    snippet_xml = re.sub(r"<!--.*?-->", "", snippet, flags=re.DOTALL).strip()

    match = re.search(r"<application\b[^>]*>", manifest, flags=re.DOTALL)
    if not match:
        print("HATA: <application> etiketi bulunamadı.", file=sys.stderr)
        sys.exit(1)

    insert_at = match.end()
    new_manifest = (
        manifest[:insert_at]
        + "\n\n"
        + snippet_xml
        + "\n"
        + manifest[insert_at:]
    )

    with open(manifest_path, "w", encoding="utf-8") as f:
        f.write(new_manifest)


if __name__ == "__main__":
    main()
