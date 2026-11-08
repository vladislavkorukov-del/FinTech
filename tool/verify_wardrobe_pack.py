#!/usr/bin/env python3
"""Verify the five-part wardrobe bundle without changing original PNGs."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import zipfile

ROOT = Path(__file__).resolve().parents[1]
META = ROOT / 'assets/finora/wardrobe_pack'


def verify(apk=None):
    sources = json.loads((META / 'source-manifest.json').read_text())
    companions = json.loads((META / 'companions.json').read_text())
    capes = json.loads((META / 'capes.json').read_text())
    placement = json.loads((META / 'cape_placement.json').read_text())
    assert len(sources['archives']) == 5
    assert len(companions) == sources['companions'] == 13
    assert len(capes) == sources['capes'] == 15
    assert placement['canvas'] == {'width': 1536, 'height': 1024}
    assert placement['finora_body_rect_on_canvas'] == {'x': 390, 'y': 130, 'width': 756, 'height': 756}
    assert placement['layer'] == 'behind_character'
    records = companions + capes
    assert len({r['id'] for r in records}) == 28
    originals = {r['asset']: r for r in sources['items']}
    assert len(originals) == 28
    assert set(originals) == {r['file'] for r in records}
    archive_names = {r['name'] for r in sources['archives']}
    for item in records:
        path = (ROOT / item['file']).resolve()
        assert path.is_relative_to(ROOT / 'assets'), item['id']
        raw = path.read_bytes()
        source = originals[item['file']]
        assert source['archive'] in archive_names
        assert len(raw) == source['bytes']
        assert hashlib.sha256(raw).hexdigest() == source['sha256'], item['id']
        assert raw[:8] == b'\x89PNG\r\n\x1a\n' and raw[12:16] == b'IHDR'
        assert struct.unpack('>II', raw[16:24]) == (item['width'], item['height'])
        assert raw[25] == 6, f'{item["id"]}: source must retain RGBA'
        if item in capes:
            assert item['layer'] == 'behind_character'
            assert (item['width'], item['height']) == (1536, 1024)
    assert set(placement['items']) == {Path(c['file']).name for c in capes}
    if apk is not None:
        with zipfile.ZipFile(apk) as bundle:
            assert bundle.testzip() is None
            for source in sources['items']:
                raw = bundle.read('assets/flutter_assets/' + source['asset'])
                assert hashlib.sha256(raw).hexdigest() == source['sha256'], source['asset']
            for name in ['companions.json', 'capes.json', 'cape_placement.json', 'source-manifest.json']:
                relative = 'assets/finora/wardrobe_pack/' + name
                assert bundle.read('assets/flutter_assets/' + relative) == (ROOT / relative).read_bytes()
            for legacy in (ROOT / 'assets/finora/wardrobe').glob('*.png'):
                relative = legacy.relative_to(ROOT).as_posix()
                assert bundle.read('assets/flutter_assets/' + relative) == legacy.read_bytes()
            assert not any(name.endswith(('.jks', '/key.properties')) for name in bundle.namelist())
        print('APKverified:28unchangedpackPNG+4legacyPNG,sourceJSON,CRC,no signing files')
    print('Verified5archives:13companions+15capes;28unchangedRGBA PNG;sharedcapegeometry')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path)
    verify(parser.parse_args().apk)
