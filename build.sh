#!/bin/zsh
# Builds MultiSoundChanger.app (Apple silicon) into build/. --install also copies it to ~/Applications and
# launches it, --zip also creates build/MultiSoundChanger-<version>.zip for a GitHub release.
set -euo pipefail
cd "${0:A:h}"

# Link against the real SDK version, otherwise macOS shows the app in the legacy look.
SDK="$(xcrun --show-sdk-version)"
FLAGS=(-c release --disable-sandbox --arch arm64 -Xlinker -platform_version -Xlinker macos -Xlinker 27.0 -Xlinker "$SDK")
swift build "${FLAGS[@]}"
BIN="$(swift build "${FLAGS[@]}" --show-bin-path)/MultiSoundChanger"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)

APP=build/MultiSoundChanger.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
# Sign with a Developer ID if available, so the Accessibility permission survives rebuilds.
IDENTITY=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)
codesign --force --sign "${IDENTITY:--}" --options runtime "$APP"
echo "Built: $APP ($VERSION)"

if [[ "${1:-}" == "--zip" ]]; then
    ZIP="build/MultiSoundChanger-$VERSION.zip"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "Archive: $ZIP"
fi

if [[ "${1:-}" == "--install" ]]; then
    pkill -x MultiSoundChanger || true
    mkdir -p ~/Applications
    rm -rf ~/Applications/MultiSoundChanger.app
    ditto "$APP" ~/Applications/MultiSoundChanger.app
    open ~/Applications/MultiSoundChanger.app
    echo "Installed: ~/Applications/MultiSoundChanger.app"
fi
