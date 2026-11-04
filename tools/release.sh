#!/bin/zsh
# Packages the staged build for a GitHub release: OpticalFlow-<version>.zip, .zip.sha256, and a
# drag-and-drop .dmg whose window shows the app, an arrow, and the Applications folder.
# Usage: ./build.sh && tools/release.sh            writes ~/Library/Developer/OpticalFlow/release/<version>/
# The copy is signed ad hoc, so no personal certificate name ends up in a public download.
# The updater needs the .zip and its .zip.sha256 on the release; the .dmg is for first installs.
set -euo pipefail
here=${0:A:h:h}
staged=~/Library/Developer/OpticalFlow/build/staged/OpticalFlow.app
version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$staged/Contents/Info.plist")
out=~/Library/Developer/OpticalFlow/release/$version
work=$out/work
[[ -d $out ]] && { echo "release: $out exists; move it away first"; exit 1; }
mkdir -p $work/root

ditto "$staged" "$work/root/OpticalFlow.app"
codesign --force --deep --sign - "$work/root/OpticalFlow.app"
codesign --verify --deep --strict "$work/root/OpticalFlow.app"

zip=$out/OpticalFlow-$version.zip
ditto -c -k --keepParent "$work/root/OpticalFlow.app" "$zip"
(cd $out && shasum -a 256 "${zip:t}" > "${zip:t}.sha256")

# The DMG: app, Applications link, and a hidden background, laid out by Finder on a writable image.
ln -s /Applications "$work/root/Applications"
mkdir "$work/root/.background"
cp "$here/Icon/dmg/background.tiff" "$work/root/.background/background.tiff"
volume="OpticalFlow $version"
hdiutil create -quiet -volname "$volume" -srcfolder "$work/root" -fs HFS+ -format UDRW -ov "$work/rw.dmg"
device=$(hdiutil attach -readwrite -noverify -noautoopen "$work/rw.dmg" | awk '/Apple_HFS/ {print $1}')
osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$volume"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 840, 548}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set text size of viewOptions to 13
    set background picture of viewOptions to file ".background:background.tiff"
    set position of item "OpticalFlow.app" of container window to {160, 190}
    set position of item "Applications" of container window to {480, 190}
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT
sync
hdiutil detach -quiet "$device"
dmg=$out/OpticalFlow-$version.dmg
hdiutil convert -quiet "$work/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$dmg"
(cd $out && shasum -a 256 "${dmg:t}" > "${dmg:t}.sha256")
mv "$work" "$out/.work-done"   # kept for a look; the release only uses the four files
echo "release: $out"
ls -l "$out"
