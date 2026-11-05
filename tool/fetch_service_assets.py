#!/usr/bin/env python3
"""Verify or restore original service artwork using its pinned SHA-256 digest.

All network access is a developer-only opt-in (--fetch). The app uses bundled
files. Simple Icons and official brand sources retain separate provenance.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

MAX_BYTES = 2 * 1024 * 1024


def validate_artwork(path, content):
    if not content or len(content) > MAX_BYTES:
        raise ValueError(f'Invalid artwork size: {path.name}')
    suffix = path.suffix.lower()
    if suffix == '.svg':
        # A standard PUBLIC SVG DOCTYPE is retained in original source files.
        # ElementTree does not retrieve external DTDs; entity declarations are
        # forbidden, and every accepted original is pinned by its SHA-256.
        if b'<!ENTITY' in content.upper():
            raise ValueError(f'External XML declarations are not allowed: {path.name}')
        document = ET.fromstring(content)
        if document.tag.rsplit('}', 1)[-1] != 'svg':
            raise ValueError(f'Not SVG artwork: {path.name}')
    elif suffix == '.png':
        if not content.startswith(b'\x89PNG\r\n\x1a\n') or len(content) < 24:
            raise ValueError(f'Not PNG artwork: {path.name}')
        width, height = struct.unpack('>II', content[16:24])
        if not width or not height or width > 8192 or height > 8192:
            raise ValueError(f'Invalid image dimensions: {path.name}')
    elif suffix == '.webp':
        if content[:4] != b'RIFF' or content[8:12] != b'WEBP':
            raise ValueError(f'Not WebP artwork: {path.name}')
    else:
        raise ValueError(f'Unsupported artwork type: {path.name}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--verify', action='store_true')
    mode.add_argument('--fetch', action='store_true')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    directory = (root / 'assets/services').resolve()
    manifest = json.loads((directory / 'manifest.json').read_text())
    count = 0
    files = set()
    for entry in manifest['items']:
        if not entry.get('assetPath'):
            continue
        path = (root / entry['assetPath']).resolve()
        if not path.is_relative_to(directory):
            raise ValueError(f'Artwork path escapes asset directory: {entry["id"]}')
        url = entry.get('downloadUrl') or entry.get('svgUrl')
        if not url or urllib.parse.urlparse(url).scheme != 'https':
            raise ValueError(f'Missing HTTPS provenance URL: {entry["id"]}')
        if not entry.get('source') or not entry.get('license'):
            raise ValueError(f'Missing source/license metadata: {entry["id"]}')
        if args.fetch:
            request = urllib.request.Request(
                url, headers={'User-Agent': 'Finance-artwork-verifier/1.3'})
            with urllib.request.urlopen(request, timeout=45) as response:
                if urllib.parse.urlparse(response.url).scheme != 'https':
                    raise ValueError('Artwork redirected outside HTTPS')
                content = response.read(MAX_BYTES + 1)
        else:
            content = path.read_bytes()
        validate_artwork(path, content)
        digest = hashlib.sha256(content).hexdigest()
        if digest != entry['sha256']:
            raise SystemExit(f'Digest mismatch: {entry["id"]}')
        if args.fetch:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
        count += 1
        files.add(path)
    print(f'Verified {count} service records / {len(files)} original artwork files')


if __name__ == '__main__':
    main()
