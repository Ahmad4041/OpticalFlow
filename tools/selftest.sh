#!/bin/zsh
# Runs the in-app self-test against a fresh store in /tmp. Exit code 0 when every check passed.
set -u
rm -rf ~/Library/Saved\ Application\ State/com.ahmadnaeem.opticalflow.savedState
store=/tmp/OpticalFlow-self.store
rm -f $store $store-shm $store-wal
APP_STORE=$store ~/Applications/OpticalFlow.app/Contents/MacOS/OpticalFlow --selftest
