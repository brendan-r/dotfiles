#!/bin/bash
set -e

# 1. Ensure dependencies (including jq for JSON parsing)
for pkg in curl wget zstd jq; do
    if ! command -v $pkg &> /dev/null; then
        echo "Installing missing dependency: $pkg"
        sudo apt update && sudo apt install -y $pkg
    fi
done

# 2. Setup temp directory
install_dir=$(mktemp -d)
echo "Working in $install_dir..."
pushd "$install_dir" > /dev/null

# 3. Get the latest download URL for the launcher
echo "Fetching latest launcher version from GitHub..."
# This query specifically looks for the asset containing "launcher" and "linux"
download_url=$(curl -s https://api.github.com/repos/ankitects/anki/releases/latest \
    | jq -r '.assets[] | select(.name | test("launcher.*linux.tar.zst")) | .browser_download_url')

if [ -z "$download_url" ] || [ "$download_url" == "null" ]; then
    echo "Error: Could not find the launcher download URL."
    echo "Check your internet connection or if the GitHub API is rate-limiting you."
    exit 1
fi

filename=$(basename "$download_url")
echo "Found: $filename"
echo "Downloading..."

# 4. Download and Extract
wget -q --show-progress "$download_url"
tar --use-compress-program=unzstd -xf "$filename"

# 5. Install
# The launcher folder naming is predictable: anki-launcher-<version>-linux
cd anki-launcher-*-linux
echo "Running installer..."
sudo ./install.sh

# 6. Cleanup
popd > /dev/null
rm -rf "$install_dir"

echo "------------------------------------------------"
echo "Anki Launcher has been successfully installed!"
echo "You can now launch Anki from your application menu."
