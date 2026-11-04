#!/usr/bin/env bash
# Source this file; it initializes the retained toolchains for each cloud task.
export FLUTTER_ROOT=/workspace/flutter-sdk
export ANDROID_HOME=/workspace/android-sdk
export ANDROID_SDK_ROOT=/workspace/android-sdk
export GRADLE_USER_HOME=/workspace/gradle-cache
if [[ -x /workspace/jdk-21/bin/javac ]]; then
  export JAVA_HOME=/workspace/jdk-21
  export PATH="$JAVA_HOME/bin:$PATH"
fi
export PATH="$FLUTTER_ROOT/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"
if [[ -n "${HTTPS_PROXY:-${HTTP_PROXY:-}}" ]]; then
  read -r finora_proxy_host finora_proxy_port < <(python3 - <<'PY'
import os, urllib.parse
p=urllib.parse.urlsplit(os.environ.get('HTTPS_PROXY',os.environ.get('HTTP_PROXY','')))
print(p.hostname or '', p.port or 80)
PY
)
  if [[ -n "$finora_proxy_host" && "${GRADLE_OPTS:-}" != *'-Dhttps.proxyHost='* ]]; then
    export GRADLE_OPTS="${GRADLE_OPTS:-} -Dhttp.proxyHost=$finora_proxy_host -Dhttp.proxyPort=$finora_proxy_port -Dhttps.proxyHost=$finora_proxy_host -Dhttps.proxyPort=$finora_proxy_port"
  fi
  unset finora_proxy_host finora_proxy_port
fi
