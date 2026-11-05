#!/bin/bash
# Builds build/ProgRadioMenuBar-<version>.dmg and .zip for a GitHub release: a universal (arm64 + x86_64) app, signed ad hoc.
# Not notarized: the Homebrew cask clears the quarantine flag; DMG users do it once (see README).
set -euo pipefail
cd "$(dirname "$0")/.."

version=$(sed -nE 's/^ *MARKETING_VERSION: "(.*)"/\1/p' project.yml)
xcodegen generate --quiet
rm -rf build/release
xcodebuild -project ProgRadio.xcodeproj -scheme ProgRadio -configuration Release \
    -derivedDataPath build/release/DerivedData -destination 'generic/platform=macOS' \
    ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO -quiet build

name="Prog Radio Menu Bar"
app="build/release/$name.app"
cp -R "build/release/DerivedData/Build/Products/Release/$name.app" "$app"
codesign --verify --deep --strict "$app"

zip=build/ProgRadioMenuBar-$version.zip
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"

# The disk image: the app next to a link to /Applications, to drag it onto.
dmg=build/ProgRadioMenuBar-$version.dmg
stage=build/release/dmg
mkdir -p "$stage"
cp -R "$app" "$stage/"
ln -s /Applications "$stage/Applications"
rm -f "$dmg"
hdiutil create -quiet -volname "$name $version" -srcfolder "$stage" -fs HFS+ -format UDZO -ov "$dmg"

lipo -archs "$app/Contents/MacOS/$name"
lipo -archs "$app/Contents/PlugIns/ProgRadioWidgets.appex/Contents/MacOS/ProgRadioWidgets"
shasum -a 256 "$dmg" "$zip"
