#!/bin/zsh
set -eu

if [[ ! -t 0 ]]; then
  print -u2 'Open this file in Terminal to enter your key privately.'
  exit 1
fi

print 'Save your development Meta Model API key in macOS Keychain.'
print 'The password prompt hides your input. No API request will be sent.'
/usr/bin/security add-generic-password -U -a avatodo \
  -s app.avatodo.development.meta -l 'Avatodo Development Meta API' -w
print 'Saved in Keychain. The key was not written to a project file.'
