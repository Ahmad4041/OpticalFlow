#!/bin/zsh
# Snapshots of every page in light and dark, with seed data, on a fresh test store.
# Usage: tools/snap.sh            all pages
#        APP_SNAPSHOT_PAGES=all,settings tools/snap.sh
# Launches through LaunchServices (open), so it works from sandboxed shells that cannot reach WindowServer.
set -u
# The staged bundle from the last build, so tests never run (or replace) the copy someone is using.
app="$HOME/Library/Developer/OpticalFlow/build/staged/OpticalFlow.app"
[[ -d "$app" ]] || app="$HOME/Applications/OpticalFlow.app"
store=/tmp/OpticalFlow-test.store
shots=/tmp/OpticalFlow-shots
log=/tmp/OpticalFlow-snap.log
# A crashed run leaves saved window state, and the next launch would wait on a "reopen windows?" alert.
rm -rf ~/Library/Saved\ Application\ State/com.ahmadnaeem.opticalflow.savedState
# Seed data only fills an empty store, so start from nothing.
rm -f $store $store-shm $store-wal /tmp/OpticalFlow-test.sock $log
rm -rf $shots
extra=()
[[ -n "${APP_SNAPSHOT_PAGES:-}" ]] && extra+=(--env "APP_SNAPSHOT_PAGES=$APP_SNAPSHOT_PAGES")
[[ -n "${APP_ACCENT:-}" ]] && extra+=(--env "APP_ACCENT=$APP_ACCENT")
open -W -n --stdout $log --stderr $log --env APP_STORE=$store --env APP_AGENT_SOCKET=/tmp/OpticalFlow-test.sock --env APP_SEED=1 --env APP_SNAPSHOT=$shots "${extra[@]}" "$app"
cat $log
