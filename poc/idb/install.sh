#!/usr/bin/env bash
set -euo pipefail
# Isolated official release; no Homebrew/Python package changes outside PREFIX.
prefix="${1:?install prefix is required}"
mkdir -p "$prefix/downloads" "$prefix/bin"
release=https://github.com/facebook/idb/releases/download/v1.7.3
archive=idb-companion.macos-arm64.tar.gz
curl -fsSL "$release/$archive" -o "$prefix/downloads/$archive"
echo "1a4e9dc2a90b93af83ac885b2b45b0e7357153f5e5736dbaa7bd9db6c164c783  $prefix/downloads/$archive" | shasum -a 256 -c -
tar -xzf "$prefix/downloads/$archive" -C "$prefix/bin"
curl -fsSL "$release/fb_idb-1.7.3-py3-none-any.whl" -o "$prefix/downloads/fb_idb-1.7.3-py3-none-any.whl"
echo "b3933fa86c2499e446dc2e06f2fd475737c41a4a99fc1782bf32cd7133b2a29e  $prefix/downloads/fb_idb-1.7.3-py3-none-any.whl" | shasum -a 256 -c -
"${IDB_PYTHON:-python3}" -m venv "$prefix/venv"
"$prefix/venv/bin/python" -m pip install --disable-pip-version-check "$prefix/downloads/fb_idb-1.7.3-py3-none-any.whl"
"$prefix/bin/idb_companion" --version
