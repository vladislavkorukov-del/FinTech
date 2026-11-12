#!/usr/bin/env python3
"""Verify all source Match-3 PNG records, shared paths and optional APK bytes."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import zipfile
import zlib


def png_size(data):
    assert data[:8] == b'\x89PNG\r\n\x1a\n', 'not PNG'
    offset = 8
    size = None
    while offset < len(data):
        length = struct.unpack('>I', data[offset:offset + 4])[0]
        kind = data[offset + 4:offset + 8]
        body = data[offset + 8:offset + 8 + length]
        crc = struct.unpack('>I', data[offset + 8 + length:offset + 12 + length])[0]
        assert zlib.crc32(kind + body) & 0xffffffff == crc, 'PNG chunk CRC mismatch'
        if kind == b'IHDR':
            size = struct.unpack('>II', body[:8])
            assert body[9] in (2, 6), 'Expected RGB background or RGBA original'
        offset += 12 + length
        if kind == b'IEND':
            assert offset == len(data), 'trailing bytes after PNG'
            break
    assert size is not None
    return size


def verify(apk=None):
    root = Path(__file__).resolve().parents[1]
    index = json.loads((root / 'docs/match3_pack/asset_index.json').read_text())
    records = index['assets']
    assert len(records) == index['original_entries'] == 86
    assert len({record['id'] for record in records}) == 86
    paths = {record['path'] for record in records}
    assert len(paths) == index['unique_original_png'] == 80
    hashes = {}
    expected = {}
    pubspec = (root / 'pubspec.yaml').read_text()
    for record in records:
        relative = Path(record['path'])
        assert relative.parts[:3] == ('assets', 'finora', 'match3')
        assert '..' not in relative.parts
        data = (root / relative).read_bytes()
        digest = hashlib.sha256(data).hexdigest()
        assert digest == record['sha256'], record['id']
        assert len(data) == record['bytes'], record['id']
        assert png_size(data) == (record['width'], record['height']), record['id']
        assert f'- {relative.parent.as_posix()}/' in pubspec, relative
        if record['preserve_square'] and not record['id'].startswith('map_bg_'):
            assert record['width'] == record['height'] == 1024
            assert record['bounds'] == [0, 0, 1024, 1024]
        if relative.as_posix() in hashes:
            assert hashes[relative.as_posix()] == digest
        hashes[relative.as_posix()] = digest
        expected[f'assets/flutter_assets/{relative.as_posix()}'] = data
    source_layout = root / 'docs/match3_pack/Finora_Match3_Terrace_Map/map_layout.json'
    runtime_layout = root / 'assets/finora/match3/map/map_layout.json'
    assert source_layout.read_bytes() == runtime_layout.read_bytes()
    expected[f'assets/flutter_assets/{runtime_layout.relative_to(root).as_posix()}'] = runtime_layout.read_bytes()
    if apk:
        with zipfile.ZipFile(apk) as bundle:
            assert bundle.testzip() is None, 'APK CRC failure'
            for path, data in expected.items():
                assert bundle.read(path) == data, f'APK bytes changed: {path}'
            for path in bundle.namelist():
                if path.startswith('assets/flutter_assets/assets/finora/match3/'):
                    assert '/preview/' not in path
                    assert not path.endswith('.tmp')
    print('86 source PNG records / 80 unique unchanged originals verified; 6 aliases shared; '
          'full board squares and map layout preserved' + ('; APK bytes and CRC verified' if apk else ''))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--apk')
    verify(parser.parse_args().apk)
