#!/usr/bin/env python3
"""Build/verify offline PNG display copies of every pinned service mark.

The original SVG/PNG bytes and source metadata are never edited. Inkscape's
standard SVG renderer resolves original paths, gradients, CSS and filters on the
build host; Android only decodes PNG. All operations are local and deterministic.
Requires Inkscape 1.4 and Pillow for --render; --verify needs only Pillow.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET

from PIL import Image

SIZE = 384
GUTTER = 2
ROOT = Path(__file__).resolve().parents[1]
ORIGINAL = ROOT / 'assets/services/manifest.json'
OUTPUT = ROOT / 'assets/services/raster'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def dimension(value):
    match = re.fullmatch(r'([0-9.]+)(?:px)?', value or '')
    return float(match[1]) if match else None


def render_svg(source, temp):
    document = ET.fromstring(source.read_bytes())
    viewbox = [float(x) for x in re.split(r'[ ,]+', document.get('viewBox', '').strip()) if x]
    width = dimension(document.get('width'))
    height = dimension(document.get('height'))
    if width is None or height is None:
        if len(viewbox) != 4 or min(viewbox[2:]) <= 0:
            raise ValueError(f'Missing bounded SVG page: {source.name}')
        width, height = viewbox[2:]
    pixels = max(1, round((SIZE - 2 * GUTTER) * width / max(width, height)))
    result = subprocess.run([
        'inkscape', str(source), '--export-type=png', '--export-area-page',
        f'--export-filename={temp}', f'--export-width={pixels}',
    ], capture_output=True, text=True)
    if result.returncode:
        raise ValueError(f'Inkscape failed for {source.name}: {result.stderr[-400:]}')
    image = Image.open(temp).convert('RGBA')
    if max(image.size) > SIZE - 2 * GUTTER + 2:
        raise ValueError(f'Unexpected raster dimensions: {source.name} {image.size}')
    square = Image.new('RGBA', (SIZE, SIZE))
    square.alpha_composite(image, ((SIZE - image.width) // 2, (SIZE - image.height) // 2))
    out = io.BytesIO()
    square.save(out, format='PNG', optimize=True)
    return out.getvalue()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--render', action='store_true')
    mode.add_argument('--verify', action='store_true')
    args = parser.parse_args()
    original = json.loads(ORIGINAL.read_text())
    if args.render:
        if not shutil.which('inkscape'):
            raise SystemExit('Inkscape is required for --render')
        OUTPUT.mkdir(parents=True, exist_ok=True)
        records = []
        with tempfile.TemporaryDirectory(prefix='finance-service-raster-') as scratch:
            for item in original['items']:
                source = ROOT / item['assetPath']
                raw = source.read_bytes()
                if digest(raw) != item['sha256']:
                    raise ValueError(f'Original SHA mismatch: {item["id"]}')
                output = OUTPUT / f'{item["id"]}.png'
                if source.suffix == '.svg':
                    rendered = render_svg(source, Path(scratch) / 'render.png')
                    operation = 'Inkscape SVG page rendered proportionally with transparent gutter; original colors unchanged'
                else:
                    rendered = raw
                    operation = 'Original PNG copied byte-for-byte'
                output.write_bytes(rendered)
                image = Image.open(io.BytesIO(rendered))
                records.append({'id': item['id'], 'assetPath': str(output.relative_to(ROOT)),
                                'sourceAssetPath': item['assetPath'], 'sourceSha256': item['sha256'],
                                'sha256': digest(rendered), 'bytes': len(rendered),
                                'width': image.width, 'height': image.height, 'operation': operation})
        manifest = {'renderer': subprocess.check_output(['inkscape', '--version'], text=True).strip(),
                    'sourceManifestSha256': digest(ORIGINAL.read_bytes()), 'vectorCanvas': SIZE,
                    'gutter': GUTTER, 'items': records}
        (OUTPUT / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    manifest = json.loads((OUTPUT / 'manifest.json').read_text())
    assert manifest['sourceManifestSha256'] == digest(ORIGINAL.read_bytes())
    assert len(manifest['items']) == len(original['items'])
    sources = {x['id']: x for x in original['items']}
    for item in manifest['items']:
        original_item = sources[item['id']]
        assert item['sourceAssetPath'] == original_item['assetPath']
        assert item['sourceSha256'] == original_item['sha256']
        assert digest((ROOT / original_item['assetPath']).read_bytes()) == original_item['sha256']
        path = ROOT / item['assetPath']
        raw = path.read_bytes()
        assert digest(raw) == item['sha256'], item['id']
        image = Image.open(io.BytesIO(raw)).convert('RGBA')
        assert image.size == (item['width'], item['height'])
        assert image.getchannel('A').getextrema()[1] > 0, item['id']
        assert max(image.size) <= 1024, item['id']
    assert {x['id'] for x in manifest['items']} == set(sources)
    print(f'Verified {len(manifest["items"])} PNG display copies for {len(sources)} original service marks')


if __name__ == '__main__':
    main()
