#!/usr/bin/env bash
# Build-time only. Never called by the app; native code ships inside the APK.
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
mnn_revision=b0239771b07b317a258fbc384683bbd540741406
mnn_dir="${FINORA_MNN_SOURCE:-$project_dir/.native/mnn-src}"
if [[ ! -d "$mnn_dir/.git" ]]; then
  mkdir -p "$mnn_dir"
  git -C "$mnn_dir" init -q
  git -C "$mnn_dir" remote add origin https://github.com/alibaba/MNN.git
fi
if [[ "$(git -C "$mnn_dir" rev-parse HEAD 2>/dev/null || true)" != "$mnn_revision" ]]; then
  if [[ -n "$(git -C "$mnn_dir" status --porcelain)" ]]; then
    echo "Refusing to replace modified MNN build sources: $mnn_dir" >&2
    exit 1
  fi
  git -C "$mnn_dir" fetch --depth=1 origin "$mnn_revision"
  git -C "$mnn_dir" checkout --detach FETCH_HEAD
fi
[[ "$(git -C "$mnn_dir" rev-parse HEAD)" == "$mnn_revision" ]]
printf 'Pinned MNN source ready: %s\n' "$mnn_dir"
