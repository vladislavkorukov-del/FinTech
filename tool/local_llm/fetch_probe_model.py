#!/usr/bin/env python3
"""Developer-only synthetic smoke-test helper; never executed by Finora.
Fetches one model from the same pinned manifest used by the app, verifies the
complete set, then derives the tested CPU text-only configuration. No weights
are placed in assets, source control, or the APK.
"""
import argparse
import hashlib
import json
from pathlib import Path
import urllib.request

parser = argparse.ArgumentParser()
parser.add_argument('model_id', choices=['qwen35-08b', 'qwen35-2b'])
parser.add_argument('destination', type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[2]
manifest = json.loads((root / 'assets/ai/local_models.json').read_text())
model = next(m for m in manifest['models'] if m['id'] == args.model_id)
args.destination.mkdir(parents=True, exist_ok=True)
for entry in model['files']:
    dest = args.destination / entry['name']
    def valid(path):
        if not path.is_file() or path.stat().st_size != entry['size']:
            return False
        with path.open('rb') as stream:
            return hashlib.file_digest(stream, 'sha256').hexdigest() == entry['sha256']
    if not valid(dest):
        partial = dest.with_name(dest.name + '.part')
        print('Downloading', entry['name'], entry['size'], flush=True)
        urllib.request.urlretrieve(entry['url'], partial)
        if not valid(partial):
            partial.unlink(missing_ok=True)
            raise SystemExit('Size/SHA-256 mismatch: ' + entry['name'])
        partial.replace(dest)
    print('Verified', entry['name'], entry['sha256'], flush=True)
metadata = json.loads((args.destination / 'llm_config.json').read_text())
metadata['is_visual'] = False
metadata.setdefault('jinja', {})['context'] = {'enable_thinking': False}
(args.destination / 'finora_llm_config.json').write_text(json.dumps(metadata))
config = json.loads((args.destination / 'config.json').read_text())
config.update(llm_config='finora_llm_config.json', backend_type='cpu', thread_num=4,
              tokenizer_file=next(x['name'] for x in model['files'] if x['name'].startswith('tokenizer.')),
              max_new_tokens=256, sampler_type='greedy', timeout_ms=120000, reuse_kv=False, prompt_cache=False)
config['jinja'] = metadata['jinja']
(args.destination / 'finora_config.json').write_text(json.dumps(config))
print(args.destination / 'finora_config.json')
