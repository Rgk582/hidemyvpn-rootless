#!/bin/bash
# Builds HideMyVPN as a rootless .deb on macOS (new arm64e ABI, which Linux can't produce).
set -e
cd "$(dirname "$0")"

if ! xcode-select -p >/dev/null 2>&1; then
    echo "Installing Xcode Command Line Tools. Run this script again when that finishes."
    xcode-select --install
    exit 1
fi

export THEOS="${THEOS:-$HOME/theos}"
if [ ! -d "$THEOS" ]; then
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/theos/theos/master/bin/install-theos)"
fi

rm -rf .theos packages
make package FINALPACKAGE=1
echo
echo "Done. The .deb is in: $(pwd)/packages"
open packages
