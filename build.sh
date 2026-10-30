#!/bin/zsh
# Builds OpticalFlow and installs it to ~/Applications/OpticalFlow.app.
# Build products live in ~/Library/Developer/OpticalFlow, outside the repo
# (and outside Dropbox or iCloud, which would try to sync them).
#
# Usage: ./build.sh            release build; install unless the app is running (then it stays staged)
#        ./build.sh --debug    debug build
#        ./build.sh --open     quit the running copy, install, open the new one
#
# The bundle is assembled in a staging folder first. Tests (tools/selftest.sh, tools/snap.sh)
# run that staged copy, so a build never replaces an app someone is using: macOS kills a
# running app whose signed binary changes on disk, with no crash report.
set -euo pipefail
here=${0:A:h}
name="OpticalFlow"
scratch="$HOME/Library/Developer/$name/build"
config=release
[[ " $* " == *" --debug "* ]] && config=debug

# Sign with your Apple Development certificate when you have one (Xcode >
# Settings > Accounts). Otherwise sign ad hoc, which is fine for your own Mac.
identity="${SIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  identity=$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 -o '"Apple Development: [^"]*"' | tr -d '"' || true)
fi
[[ -n "$identity" ]] || identity=-

swift build -c $config --package-path "$here" --scratch-path "$scratch" 2>&1 | grep -E "error|warning|Build complete" | grep -v "^\[" || true
bin="$scratch/$config/$name"
[[ -x "$bin" ]] || { echo "build failed"; exit 1; }
# swift build can report success while an edited file failed to compile. Catch that.
stale=$(find "$here/Sources" -name '*.swift' -newer "$bin" | head -1)
if [[ -n "$stale" ]]; then
  echo "build failed: binary is older than $stale"
  swift build -c $config --package-path "$here" --scratch-path "$scratch" 2>&1 | grep -E "error" | head -20
  exit 1
fi

installed="$HOME/Applications/$name.app"
app="$scratch/staged/$name.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/$name"
sed -e "s/__BUILD__/$(date +%Y%m%d%H%M)/" "$here/Info.plist.in" > "$app/Contents/Info.plist"
# The icon: Icon/AppIcon.icon -> Resources/Assets.car + AppIcon.icns, rebuilt when it changed.
if [[ -d "$here/Icon/AppIcon.icon" ]]; then
  car="$here/Resources/Assets.car"
  if [[ ! -f "$car" || -n "$(find "$here/Icon/AppIcon.icon" -newer "$car" | head -1)" ]]; then
    "$here/tools/make_icon.sh"
  fi
  cp -X "$car" "$here/Resources/AppIcon.icns" "$app/Contents/Resources/"
fi
xattr -cr "$app"
codesign --force --sign "$identity" "$app" 2>&1 | grep -v "replacing existing signature" || true
echo "staged $app (signed: ${identity})"

# Install only when nothing is using the installed copy.
running=$(pgrep -f "$installed/Contents/MacOS/$name\$" || true)
if [[ -n "$running" && " $* " != *" --open "* ]]; then
  echo "not installed: $name is running (pid $running). Quit it, or run ./build.sh --open."
  exit 0
fi
if [[ -n "$running" ]]; then
  osascript -e "quit app \"$name\"" 2>/dev/null || true
  for _ in {1..20}; do pgrep -f "$installed/Contents/MacOS/$name\$" >/dev/null || break; sleep 0.25; done
fi
mkdir -p "$HOME/Applications"
rm -rf "$installed"
ditto "$app" "$installed"
echo "installed $installed"
# The CLI: the app binary under a short name on PATH (bama agent-cli skill).
mkdir -p "$HOME/.local/bin"
ln -sf "$installed/Contents/MacOS/$name" "$HOME/.local/bin/opticalflow"

if [[ " $* " == *" --open "* ]]; then
  open "$installed"
fi
