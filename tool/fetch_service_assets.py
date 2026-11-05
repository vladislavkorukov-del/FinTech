#!/usr/bin/env python3
"""Verify/retrieve the exact pinned, digest-checked service artwork."""
import argparse
import hashlib
import json
from pathlib import Path
import urllib.request


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--verify', action='store_true')
    mode.add_argument('--fetch', action='store_true')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    manifest = json.loads((root / 'assets/services/manifest.json').read_text())
    count = 0
    for entry in manifest['items']:
        if not entry['assetPath']:
            continue
        path = root / entry['assetPath']
        if args.fetch:
            request = urllib.request.Request(entry['svgUrl'], headers={'User-Agent': 'Finora-artwork-verifier/1.0'})
            with urllib.request.urlopen(request, timeout=45) as response:
                content = response.read(2 * 1024 * 1024)
        else:
            content = path.read_bytes()
        digest = hashlib.sha256(content).hexdigest()
        if digest != entry['sha256']:
            raise SystemExit(f'Digest mismatch: {entry["id"]}')
        if args.fetch:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
        count += 1
    print(f'Verified {count} exact SVG assets at commit {manifest["sourceCommit"]}')


if __name__ == '__main__':
    main()
