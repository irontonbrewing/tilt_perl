#!/bin/bash
set -e

SOURCE_DIR="$HOME/tilt-perl"
cd $SOURCE_DIR

# Assume the control file is at "DEBIAN/control" relative to the repository root
# Extract the version number (e.g., from a line like "Version: 1.0")
VERSION=$(grep '^Version:' DEBIAN/control | head -n1 | awk '{print $2}')

if [ -z "$VERSION" ]; then
    echo "Error: Could not determine version from DEBIAN/control."
    exit 1
fi

echo "Building package version: $VERSION"

# Set up a clean build directory
BUILD_DIR="/tmp/tilt-perl-${VERSION}"

# Remove any existing directory with the same name
rm -rf "$BUILD_DIR"

# Create the directory structure
mkdir -p "$BUILD_DIR/usr/bin"
mkdir -p "$BUILD_DIR/usr/share/doc/tilt"
mkdir -p "$BUILD_DIR/usr/share/tilt"

# Copy files
cp tilt.pl "$BUILD_DIR/usr/bin/tilt"
chmod +x "$BUILD_DIR/usr/bin/tilt"

cp tilt_logo.png "$BUILD_DIR/usr/share/tilt"
cp tilt_icon.jpg "$BUILD_DIR/usr/share/tilt"
cp config.sample.json "$BUILD_DIR/usr/share/tilt"
cp data_test.pl "$BUILD_DIR/usr/share/tilt"

cp README.md "$BUILD_DIR/usr/share/doc/tilt"
cp LICENSE.txt "$BUILD_DIR/usr/share/doc/tilt"

# Copy the control file (and any maintainer scripts if needed)
cp -R DEBIAN "$BUILD_DIR"

# Build the Debian package
PPA_DIR="$HOME/ppa"
rm -f "$PPA_DIR/dist/tilt-perl"*.deb

PACKAGE_NAME="$PPA_DIR/dist/tilt-perl-${VERSION}.deb"
dpkg-deb --build "$BUILD_DIR" "$PACKAGE_NAME"
echo "Package built: $PACKAGE_NAME"

dpkg-deb --contents $PACKAGE_NAME

# Remove the build area
rm -rf "$BUILD_DIR"
