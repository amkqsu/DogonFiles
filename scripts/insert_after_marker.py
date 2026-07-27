#!/usr/bin/env python3
import sys


def find_marker(content, markers, start=0):
    best = -1
    matched = None
    for m in markers:
        idx = content.find(m, start)
        if idx != -1 and (best == -1 or idx < best):
            best = idx
            matched = m
    return best, matched


def main():
    args = sys.argv[1:]
    after_anchor = None
    if "--after-anchor" in args:
        i = args.index("--after-anchor")
        after_anchor = args[i + 1]
        del args[i:i + 2]

    if len(args) != 4:
        print("Kullanım: insert_after_marker.py <target> <snippet> <marker_ile_bosluk> <marker_bossuz> [--after-anchor TEXT]", file=sys.stderr)
        sys.exit(2)

    target_path, snippet_path, marker_a, marker_b = args

    with open(target_path, "r", encoding="utf-8") as f:
        content = f.read()

    with open(snippet_path, "r", encoding="utf-8") as f:
        snippet = f.read()

    snippet_lines = snippet.splitlines()
    code_lines = [ln for ln in snippet_lines if not ln.strip().startswith("//")]
    snippet_code = "\n".join(code_lines).strip("\n")

    search_start = 0
    if after_anchor:
        anchor_idx = content.find(after_anchor)
        if anchor_idx == -1:
            print(f"HATA: '{after_anchor}' içerikte bulunamadı.", file=sys.stderr)
            sys.exit(1)
        search_start = anchor_idx

    idx, matched = find_marker(content, [marker_a, marker_b], search_start)
    if idx == -1:
        print(f"HATA: '{marker_a}' / '{marker_b}' bulunamadı ({target_path}).", file=sys.stderr)
        sys.exit(1)

    insert_at = idx + len(matched)
    new_content = (
        content[:insert_at]
        + "\n"
        + snippet_code
        + "\n"
        + content[insert_at:]
    )

    with open(target_path, "w", encoding="utf-8") as f:
        f.write(new_content)


if __name__ == "__main__":
    main()
