#!/usr/bin/env python3
"""Prepare a full JDK21 for Android compilation, retaining TLS/SHA256 checks."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request

TARGET = Path('/workspace/jdk-21')
ARCHIVE = Path('/workspace/temurin-jdk21.tar.gz')
URL = ('https://github.com/adoptium/temurin21-binaries/releases/download/'
       'jdk-21.0.13%2B9/OpenJDK21U-jdk_x64_linux_hotspot_21.0.13_9.tar.gz')
# Independently retrieved from the official release's .sha256.txt artifact.
SHA256 = 'd7f5d5cf865a2902b70ff549b97586a7d3f234e016f041ab447ea740c7d66d1c'


def checked(path):
    if not path.is_file():
        return False
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest() == SHA256


def configure_trust():
    # Use the managed machine's public CA store, including its HTTPS proxy CA.
    # TLS verification stays enabled; preserve the vendor trust store for review.
    system = Path('/etc/ssl/certs/java/cacerts')
    store = TARGET / 'lib/security/cacerts'
    if not system.is_file():
        return
    if store.is_symlink():
        if store.resolve() != system.resolve():
            raise RuntimeError('Existing custom Java trust store preserved; inspect configuration')
        return
    backup = store.with_name('cacerts.vendor')
    if backup.exists():
        raise RuntimeError('Existing Java CA backup preserved; inspect before changing trust')
    store.rename(backup)
    os.symlink(system,store)


def main():
    compiler = TARGET / 'bin/javac'
    if TARGET.exists():
        if not compiler.is_file():
            raise RuntimeError('Existing JDK directory preserved: no Java compiler found')
        result = subprocess.run([str(compiler), '-version'], capture_output=True, text=True, check=True)
        if not (result.stdout + result.stderr).strip().startswith('javac 21.'):
            raise RuntimeError('Existing JDK preserved: project requires JDK21')
        configure_trust()
        print((result.stdout + result.stderr).strip())
        return
    if not checked(ARCHIVE):
        partial = ARCHIVE.with_suffix('.download')
        with urllib.request.urlopen(URL, timeout=60) as response, partial.open('wb') as output:
            shutil.copyfileobj(response, output)
        if not checked(partial):
            partial.unlink(missing_ok=True)
            raise RuntimeError('JDK checksum verification failed')
        partial.replace(ARCHIVE)
    with tempfile.TemporaryDirectory(prefix='finora-jdk-', dir='/workspace') as temp:
        with tarfile.open(ARCHIVE) as bundle:
            bundle.extractall(temp, filter='data')
        roots = list(Path(temp).iterdir())
        if len(roots) != 1:
            raise RuntimeError('Unexpected JDK archive structure')
        shutil.move(str(roots[0]), TARGET)
    configure_trust()
    subprocess.run([str(compiler), '-version'], check=True)


if __name__ == '__main__':
    main()
