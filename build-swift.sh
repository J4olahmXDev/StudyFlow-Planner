#!/bin/zsh
set -eu
cd "${0:A:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.cache/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.cache/modules"
swift build --disable-sandbox --cache-path "$PWD/.cache/swiftpm" --scratch-path "$PWD/.build"
bundle="StudyFlow Planner.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp Resources/StudyFlowIcon.icns "$bundle/Contents/Resources/StudyFlowIcon.icns"
cp Resources/CloudDeployment.plist "$bundle/Contents/Resources/CloudDeployment.plist"
cp .build/debug/Daylight "$bundle/Contents/MacOS/Daylight"
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleExecutable</key><string>Daylight</string><key>CFBundleIdentifier</key><string>studio.daylight.planner</string><key>CFBundleName</key><string>StudyFlow Planner</string><key>CFBundleDisplayName</key><string>StudyFlow Planner</string><key>CFBundleIconFile</key><string>StudyFlowIcon.icns</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleVersion</key><string>2</string><key>CFBundleShortVersionString</key><string>1.1.0</string><key>LSMinimumSystemVersion</key><string>14.0</string><key>NSHighResolutionCapable</key><true/></dict></plist>
PLIST
codesign --force --sign - "$bundle"
