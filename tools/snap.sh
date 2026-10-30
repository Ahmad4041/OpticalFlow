#!/bin/zsh
# Snapshots of every page in light and dark, with seed data, on a fresh test store.
# Usage: tools/snap.sh            all pages
#        APP_SNAPSHOT_PAGES=all,settings tools/snap.sh
# Launches through LaunchServices (open), so it works from sandboxed shells that cannot reach WindowServer.
set -u
store=/tmp/OpticalFlow-test.store
shots=/tmp/OpticalFlow-shots
log=/tmp/OpticalFlow-snap.log
# A crashed run leaves saved window state, and the next launch would wait on a "reopen windows?" alert.
rm -rf ~/Library/Saved\ Application\ State/com.ahmadnaeem.opticalflow.savedState
# Seed data only fills an empty store, so start from nothing.
rm -f $store $store-shm $store-wal $log
rm -rf $shots
pages=${APP_SNAPSHOT_PAGES:-}
open -W -n --stdout $log --stderr $log --env APP_STORE=$store --env APP_SEED=1 --env APP_SNAPSHOT=$shots \
  ${pages:+--env APP_SNAPSHOT_PAGES=$pages} ${APP_ACCENT:+--env APP_ACCENT=$APP_ACCENT} ~/Applications/OpticalFlow.app
cat $log
