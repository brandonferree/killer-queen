#!/usr/bin/env python3
"""Recompute subresource integrity hashes in the built index.html.

Trunk stamps `integrity` attributes on the preload links it generates, but the
hashes can end up stale: wasm-opt rewrites the wasm after trunk has already
computed its digest, and trunk's own JS digest has been observed not to match
the file it emits. Either way the browser blocks the resource and the game
never boots. Rehash whatever is actually on disk and rewrite the attributes.

Usage: fix-integrity.py <dist-dir>
"""

import base64
import hashlib
import pathlib
import re
import sys

LINK_WITH_INTEGRITY = re.compile(r'<link[^>]*\bintegrity="[^"]*"[^>]*>')


def sri(path: pathlib.Path) -> str:
    digest = hashlib.sha384(path.read_bytes()).digest()
    return "sha384-" + base64.b64encode(digest).decode("ascii")


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2

    dist = pathlib.Path(sys.argv[1])
    index = dist / "index.html"
    html = index.read_text(encoding="utf-8")
    changed = []

    def rewrite(match: re.Match) -> str:
        tag = match.group(0)
        href = re.search(r'href="([^"]+)"', tag)
        if not href:
            return tag
        target = dist / href.group(1).lstrip("./")
        if not target.is_file():
            print(f"  ! referenced file missing, leaving as-is: {href.group(1)}")
            return tag
        want = sri(target)
        have = re.search(r'integrity="([^"]*)"', tag).group(1)
        if want != have:
            changed.append(target.name)
        return tag.replace(f'integrity="{have}"', f'integrity="{want}"')

    fixed = LINK_WITH_INTEGRITY.sub(rewrite, html)

    if changed:
        index.write_text(fixed, encoding="utf-8")
        for name in changed:
            print(f"  fixed integrity hash: {name}")
    else:
        print("  all integrity hashes already correct")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
