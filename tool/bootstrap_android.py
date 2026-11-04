#!/usr/bin/env python3
"""Install the Android toolchain used by Finora without changing tracked files.

Run: python3 tool/bootstrap_android.py [--sdk-root /workspace/android-sdk]
Archives retain TLS and official published checksum verification. Network access
must permit dl.google.com. Android CLI displays Google's SDK terms during setup.
"""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import urllib.parse
import urllib.request
import zipfile


# From Google's repository2-1.xml for cmdline-tools;23.0, Linux x86_64.
TOOLS_URL = (
    "https://dl.google.com/android/repository/"
    "commandlinetools-linux-16111833_latest.zip"
)
TOOLS_SIZE = 181052239
TOOLS_SHA1 = "e025545c62a8e64c7559119566a569fb1dec5f60"
PACKAGES = (
    ("cmake/3.22.1@3.22.1", "cmake/3.22.1/source.properties", "Pkg.Revision", "3.22.1"),
    ("platforms/android-35@2.0.0", "platforms/android-35/source.properties", "Pkg.Revision", "2"),
    ("platforms/android-34@3.0.0", "platforms/android-34/source.properties", "Pkg.Revision", "3"),
    ("platforms/android-36@2.0.0", "platforms/android-36/source.properties", "Pkg.Revision", "2"),
    ("build-tools/36.0.0@36.0.0", "build-tools/36.0.0/source.properties", "Pkg.Revision", "36.0.0"),
    ("platform-tools@37.0.1", "platform-tools/source.properties", "Pkg.Revision", "37.0.1"),
    ("ndk/28.2.13676358@28.2.13676358", "ndk/28.2.13676358/source.properties", "Pkg.Revision", "28.2.13676358"),
)


def properties(path: Path) -> dict[str, str]:
    if not path.is_file():
        return {}
    return {
        key.strip(): value.strip()
        for line in path.read_text().splitlines()
        if not line.lstrip().startswith("#") and "=" in line
        for key, value in [line.split("=", 1)]
    }


def checked_archive(path: Path) -> bool:
    if not path.is_file() or path.stat().st_size != TOOLS_SIZE:
        return False
    digest = hashlib.sha1()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest() == TOOLS_SHA1


def install_tools(sdk: Path, cache: Path) -> None:
    target = sdk / "cmdline-tools/latest"
    if (properties(target / "source.properties").get("Pkg.Revision") == "23.0"
            and (target / "bin/android").is_file()):
        return
    if target.exists():
        raise RuntimeError(
            f"{target} already exists with another or incomplete SDK version; "
            "preserve it and select a separate --sdk-root."
        )
    cache.mkdir(parents=True, exist_ok=True)
    archive = cache / "commandlinetools-linux-16111833_latest.zip"
    if not checked_archive(archive):
        partial = archive.with_suffix(".download")
        print("Downloading official Android command-line tools 23.0...", flush=True)
        with urllib.request.urlopen(TOOLS_URL, timeout=60) as response:
            with partial.open("wb") as output:
                shutil.copyfileobj(response, output)
        if not checked_archive(partial):
            partial.unlink(missing_ok=True)
            raise RuntimeError("Android tools archive failed published size/SHA-1 verification")
        partial.replace(archive)
    print("Android tools archive: official size and SHA-1 verified", flush=True)
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="finora-android-", dir=cache) as temporary:
        root = Path(temporary)
        with zipfile.ZipFile(archive) as bundle:
            for member in bundle.infolist():
                destination = (root / member.filename).resolve()
                if not destination.is_relative_to(root.resolve()):
                    raise RuntimeError("Unsafe path in Android tools archive")
            bundle.extractall(root)
            for member in bundle.infolist():
                permissions = (member.external_attr >> 16) & 0o777
                if permissions:
                    (root / member.filename).chmod(permissions)
        shutil.move(str(root / "cmdline-tools"), target)


def java_environment() -> dict[str, str]:
    result = dict(os.environ)
    # Java does not automatically use HTTPS_PROXY. Add route selectors only;
    # credentials, inherited runtime headers and TLS trust stay untouched.
    proxy = urllib.parse.urlsplit(result.get("HTTPS_PROXY", result.get("HTTP_PROXY", "")))
    if proxy.hostname:
        existing = result.get("JAVA_TOOL_OPTIONS", "")
        options = []
        for scheme in ("http", "https"):
            if f"-D{scheme}.proxyHost=" not in existing:
                options += [f"-D{scheme}.proxyHost={proxy.hostname}",
                            f"-D{scheme}.proxyPort={proxy.port or 80}"]
        if options:
            result["JAVA_TOOL_OPTIONS"] = " ".join([existing, *options]).strip()
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sdk-root", type=Path, default=Path("/workspace/android-sdk"))
    parser.add_argument("--cache", type=Path, default=Path("/workspace/android-downloads"))
    args = parser.parse_args()
    if not shutil.which("java"):
        raise RuntimeError("Java 21 is required; install a trusted JDK before running this script")
    sdk = args.sdk_root.resolve()
    sdk.mkdir(parents=True, exist_ok=True)
    install_tools(sdk, args.cache.resolve())
    missing = [package for package, relative, key, expected in PACKAGES
               if properties(sdk / relative).get(key) != expected]
    if missing:
        subprocess.run([
            str(sdk / "cmdline-tools/latest/bin/android"),
            "--no-metrics", f"--sdk={sdk}", "sdk", "install", *missing,
        ], env=java_environment(), check=True)
    for package, relative, key, expected in PACKAGES:
        actual = properties(sdk / relative).get(key)
        if actual != expected:
            raise RuntimeError(f"SDK package {package}: expected {expected}, got {actual}")
        print(f"Verified installed SDK package: {package}", flush=True)
    subprocess.run([str(sdk / "platform-tools/adb"), "version"], check=True)
    print(f"Android SDK prepared at {sdk}", flush=True)


if __name__ == "__main__":
    main()
