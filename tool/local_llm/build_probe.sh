#!/usr/bin/env bash
set -euo pipefail
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
"$project_dir/tool/local_llm/prepare_mnn.sh"
mnn_dir="${FINORA_MNN_SOURCE:-$project_dir/.native/mnn-src}"
probe_build="${FINORA_PROBE_BUILD:-$project_dir/.native/host}"
cmake_bin="${CMAKE_BIN:-cmake}"
"$cmake_bin" -S "$mnn_dir" -B "$probe_build" -DCMAKE_BUILD_TYPE=Release \
  -DMNN_BUILD_LLM=ON -DMNN_BUILD_LLM_OMNI=OFF -DMNN_BUILD_SHARED_LIBS=ON \
  -DMNN_SEP_BUILD=OFF -DMNN_BUILD_TOOLS=OFF -DMNN_BUILD_CONVERTER=OFF \
  -DMNN_BUILD_QUANTOOLS=OFF -DMNN_LLM_BUILD_DEMO=OFF -DLLM_SUPPORT_HTTP_RESOURCE=OFF
"$cmake_bin" --build "$probe_build" --target MNN -j"${FINORA_BUILD_JOBS:-4}"
"${CXX:-c++}" -std=c++17 -O2 -I"$project_dir/android/app/src/main/cpp/local_llm" \
  -I"$mnn_dir/include" -I"$mnn_dir/transformers/llm/engine/include" \
  -I"$mnn_dir/transformers/llm/engine/src" -I"$mnn_dir/3rd_party" \
  "$project_dir/tool/local_llm/probe.cpp" "$project_dir/android/app/src/main/cpp/local_llm/session.cpp" \
  -L"$probe_build" -Wl,-rpath,"$probe_build" -lMNN -pthread -o "$probe_build/finora_llm_probe"
"${CXX:-c++}" -std=c++17 -O2 -I"$project_dir/android/app/src/main/cpp/local_llm" \
  -I"$mnn_dir/include" -I"$mnn_dir/transformers/llm/engine/include" \
  -I"$mnn_dir/transformers/llm/engine/src" -I"$mnn_dir/3rd_party" \
  "$project_dir/tool/local_llm/lifecycle_probe.cpp" "$project_dir/android/app/src/main/cpp/local_llm/session.cpp" \
  -L"$probe_build" -Wl,-rpath,"$probe_build" -lMNN -pthread -o "$probe_build/finora_lifecycle_probe"
printf 'Probe executables: %s\n' "$probe_build/finora_llm_probe" "$probe_build/finora_lifecycle_probe"
