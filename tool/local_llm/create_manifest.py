#!/usr/bin/env python3
"""Refresh pinned, official MNN metadata; never downloads weights into the repo.

Review native text-only compatibility before changing these revisions. LFS SHA256
comes from HF's pinned tree; ordinary files are downloaded and hashed here.
"""
import hashlib
import json
from pathlib import Path
from urllib.request import urlopen

RUNTIME = "b0239771b07b317a258fbc384683bbd540741406"
MODELS = [
    ("qwen35-08b", "Qwen3.5-0.8B-MNN", "3208b55b2e3c948016c9d380a697be881a1f12f8", "Облегчённая · Qwen 0.8B", "tokenizer.txt"),
    ("qwen35-2b", "Qwen3.5-2B-MNN", "77cc78a9ec864f0a7067a4458c181a9c7c0f0378", "Стандартная · Qwen 2B", "tokenizer.mtok"),
]

def build():
    models = []
    for id_, name, revision, label, tokenizer in MODELS:
        repo = f"taobao-mnn/{name}"
        base = f"https://huggingface.co/{repo}/resolve/{revision}/"
        with urlopen(f"https://huggingface.co/api/models/{repo}/tree/{revision}?recursive=true") as r:
            tree = {f["path"]: f for f in json.load(r)}
        files = []
        for name in ["config.json", "llm_config.json", "llm.mnn", "llm.mnn.weight", tokenizer]:
            f = tree[name]
            checksum = f.get("lfs", {}).get("oid")
            if checksum is None:
                with urlopen(base + name) as r:
                    data = r.read()
                if len(data) != f["size"]:
                    raise ValueError(f"Size mismatch: {repo}/{name}")
                checksum = hashlib.sha256(data).hexdigest()
            files.append({"name": name, "size": f["size"], "sha256": checksum, "url": base + name})
        models.append({"id": id_, "label": label, "source": repo,
            "revision": revision, "format": "MNN-LLM", "quantization": "4-bit HQQ (block 64)",
            "license": "Apache-2.0", "runtime": "MNN 3.6.2", "runtimeRevision": RUNTIME,
            "files": files})
    return {"schemaVersion": 1, "models": models}

if __name__ == "__main__":
    target = Path(__file__).resolve().parents[2] / "assets/ai/local_models.json"
    target.write_text(json.dumps(build(), ensure_ascii=False, indent=2) + "\n")
    print(target)
