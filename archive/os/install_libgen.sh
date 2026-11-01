#!/bin/bash

# Ensure jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: 'jq' is not installed. Install it with: sudo apt install jq"
    exit 1
fi

REPO="obsfx/libgen-downloader"
ARCH="linux-x64"

echo "Fetching latest version info for $REPO..."

# Use jq to extract the tag_name specifically
LATEST_TAG=$(curl -s https://api.github.com/repos/$REPO/releases/latest | jq -r '.tag_name')

# Check if we actually got a version string
if [[ -z "$LATEST_TAG" || "$LATEST_TAG" == "null" ]]; then
    echo "Error: Could not extract tag_name."
    exit 1
fi

echo "Success! Version tag: $LATEST_TAG"

# Binary naming: libgen-downloader-linux-x64
DOWNLOAD_URL="https://github.com/$REPO/releases/download/$LATEST_TAG/libgen-downloader-$ARCH"

echo "Downloading from: $DOWNLOAD_URL"
curl -L -f -o libgen-downloader "$DOWNLOAD_URL"

if [ $? -eq 0 ]; then
    chmod +x libgen-downloader
    echo "Download successful."
    read -p "Install to /usr/local/bin? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo mv libgen-downloader /usr/local/bin/libgen-downloader
        echo "Installed! Run with: libgen-downloader"
    fi
else
    echo "Download failed. Check the URL above."
fi
