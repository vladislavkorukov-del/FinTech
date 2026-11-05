#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
python3 tool/fetch_service_assets.py --verify
python3 tool/render_service_assets.py --verify
python3 tool/bank_catalog.py --verify
flutter test --reporter expanded
flutter build apk --debug
