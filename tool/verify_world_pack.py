#!/usr/bin/env python3
"""Check the29 supplied workingPNG originals and optional APK bundle bytes."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import zipfile


def verify(apk=None):
    root = Path(__file__).resolve().parents[1]
    index = json.loads((root / 'docs/world_pack/asset_index.json').read_text())
    assets = index['assets']
    assert len(assets) == index['count'] == 29
    assert len({a['id'] for a in assets}) == 29
    counts = {}
    expected = {}
    pubspec = (root / 'pubspec.yaml').read_text()
    for asset in assets:
        original = Path(asset['file'])
        assert original.parts[0] == 'assets' and '..' not in original.parts
        target = Path('assets/finora/world') / original.relative_to('assets')
        data = (root / target).read_bytes()
        assert hashlib.sha256(data).hexdigest() == asset['sha256'], target
        assert len(data) == asset['bytes'], target
        assert data[:8] == b'\x89PNG\r\n\x1a\n'
        width, height = struct.unpack('>II', data[16:24])
        assert (width, height) == (asset['width'], asset['height']), target
        if asset['has_transparency']:
            assert data[25] == 6, f'{target}: expected RGBA'
        assert f'- {target.parent.as_posix()}/' in pubspec, target
        expected[f'assets/flutter_assets/{target.as_posix()}'] = data
        counts[asset['group']] = counts.get(asset['group'], 0) + 1
    if apk:
        with zipfile.ZipFile(apk) as bundle:
            assert bundle.testzip() is None, 'APK CRC failure'
            for path, data in expected.items():
                assert bundle.read(path) == data, f'APK changed original: {path}'
            assert not any('/references/' in p for p in bundle.namelist())
    print(f'29 original PNG verified: {counts};' + (' APK bytes and CRC verified' if apk else ' registered local paths verified'))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--apk')
    verify(parser.parse_args().apk)
