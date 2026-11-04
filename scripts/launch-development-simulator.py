#!/usr/bin/env python3
"""Opt-in local debug key import. Never supplies a key to a physical device or a file."""
import argparse
import json
import os
import re
import subprocess
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--simulator', required=True, help='Booted iPhone simulator UUID')
args = parser.parse_args()
if not re.fullmatch(r'[0-9A-Fa-f-]{36}', args.simulator):
    parser.error('Use a simulator UUID.')
listed = subprocess.run(['xcrun', 'simctl', 'list', 'devices', 'booted', '--json'], capture_output=True, text=True, check=True)
devices = [d for group in json.loads(listed.stdout)['devices'].values() for d in group]
if not any(d['udid'].lower() == args.simulator.lower() and 'iPhone' in d.get('deviceTypeIdentifier', '') for d in devices):
    sys.exit('Select a booted iPhone simulator. No key was read.')
result = subprocess.run(['/usr/bin/security', 'find-generic-password', '-s', 'app.avatodo.development.meta', '-a', 'avatodo', '-w'], capture_output=True)
if result.returncode:
    sys.exit('Development key unavailable in macOS Keychain. No key was sent.')
key = result.stdout.decode().strip()
if not key or any(ord(c) < 33 or ord(c) > 126 for c in key):
    sys.exit('Development key is invalid. No key was sent.')
environment = os.environ.copy()
environment['SIMCTL_CHILD_AVATODO_DEVELOPMENT_META_KEY'] = key
subprocess.run(['xcrun', 'simctl', 'terminate', args.simulator, 'app.avatodo'], capture_output=True)
launch = subprocess.run(['xcrun', 'simctl', 'launch', args.simulator, 'app.avatodo'], env=environment, capture_output=True)
environment.pop('SIMCTL_CHILD_AVATODO_DEVELOPMENT_META_KEY', None)
key = None
if launch.returncode:
    sys.exit('Launch failed. Key was not printed or written to a project file.')
print('Debug app launched. The key can now be imported into its local simulator Keychain; verify Settings in the app.')
