#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
finora_flutter_revision=c197ca5199e9ee5661e865596c9c07294dfab51c
if [[ ! -d /workspace/flutter-sdk/.git ]]; then
  if [[ -e /workspace/flutter-sdk ]]; then
    echo 'Existing /workspace/flutter-sdk is not the expected Git SDK; preserve it and inspect before proceeding.' >&2
    exit 1
  fi
  git clone --depth 1 --branch 3.47.9 https://github.com/flutter/flutter.git /workspace/flutter-sdk
fi
if [[ "$(git -C /workspace/flutter-sdk rev-parse HEAD)" != "$finora_flutter_revision" ]]; then
  echo 'Flutter SDK revision differs from the tested project target; inspect before changing an existing SDK.' >&2
  exit 1
fi
python3 tool/bootstrap_jdk.py
source tool/cloud_env.sh
python3 tool/bootstrap_android.py
# Uses the official Flutter download route and inherited verified CA trust.
flutter config --no-analytics
flutter precache --android
flutter pub get
flutter --version
