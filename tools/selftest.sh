#!/bin/zsh
# Runs the in-app self-test against a fresh store in /tmp. Exit code 0 when every check passed.
# Launches through LaunchServices (open), so it works from sandboxed shells that cannot reach WindowServer.
set -u
rm -rf ~/Library/Saved\ Application\ State/com.ahmadnaeem.opticalflow.savedState
store=/tmp/OpticalFlow-self.store
log=/tmp/OpticalFlow-self.log
rm -f $store $store-shm $store-wal $log
open -W -n --stdout $log --stderr $log --env APP_STORE=$store ~/Applications/OpticalFlow.app --args --selftest
cat $log
grep -q "^SELFTEST PASS" $log
