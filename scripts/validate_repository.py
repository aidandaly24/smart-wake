#!/usr/bin/env python3
"""Structural checks only; these do NOT replace Swift compilation or device tests."""
import json
import plistlib
import re
import subprocess
import struct
from pathlib import Path
from xml.etree import ElementTree
root = Path(__file__).resolve().parents[1]
checks = 0
def check(condition, message):
    global checks
    assert condition, message
    checks += 1
for path in [*root.rglob('*.plist'), *root.rglob('*.entitlements'), *root.rglob('*.xcprivacy')]:
    with path.open('rb') as handle: plistlib.load(handle)
    check(True, f'Invalid XML plist {path}')
for path in root.rglob('*.xcscheme'):
    ElementTree.parse(path)
    check(True, f'Invalid scheme {path}')
for path in (root/'Fixtures').glob('*.json'):
    json.loads(path.read_text())
    check(True, f'Invalid fixture {path}')
iphone = plistlib.loads((root/'iPhoneApp/Info.plist').read_bytes())
watch = plistlib.loads((root/'WatchApp/Info.plist').read_bytes())
check(bool(iphone.get('NSAlarmKitUsageDescription')), 'Missing alarm purpose')
check(bool(watch.get('NSHealthShareUsageDescription')), 'Missing HealthKit read purpose')
check(bool(watch.get('NSMotionUsageDescription')), 'Missing motion purpose')
check('NSHealthUpdateUsageDescription' not in watch, 'HealthKit writes are not requested')
check(not watch.get('UIBackgroundModes'), 'No fake background runtime')
project = root/'SmartWake.xcodeproj/project.pbxproj'
check(project.exists(), 'Missing Xcode project')
text = project.read_text()
for path in [*root.joinpath('iPhoneApp').glob('*.swift'), *root.joinpath('WatchApp').glob('*.swift')]:
    check(path.name in text, f'Missing project source {path.name}')
all_swift='\n'.join(p.read_text() for p in root.rglob('*.swift'))
check('HKWorkoutSession(' not in all_swift, 'No fake workout')
check('WKExtendedRuntimeSession(' not in all_swift, 'No unsupported all-night runtime')
check('URLSession' not in all_swift, 'No server health transmission')
check('stopButton:' in all_swift and 'Emergency stop' in all_swift, 'Visible exits required')
check('CODE_SIGN_ENTITLEMENTS' in text, 'Watch entitlement must be wired')
check('Embed Watch Content' in text, 'Watch must be embedded')
check('COMPANION_APP_BUNDLE_IDENTIFIER' in text, 'Companion identifier missing')
for folder, platform in [('iPhoneApp', 'ios'), ('WatchApp', 'watchos')]:
    catalog = root/folder/'SmartWakeArtwork.xcassets'
    metadata = json.loads((catalog/'SmartWakeIcon.appiconset/Contents.json').read_text())
    icon = metadata['images'][0]
    check(icon['platform'] == platform and icon['size'] == '1024x1024', 'Invalid icon platform/size')
    png = (catalog/'SmartWakeIcon.appiconset'/icon['filename']).read_bytes()
    check(png[:8] == b'\x89PNG\r\n\x1a\n', 'Icon must be PNG')
    check(struct.unpack('>II', png[16:24]) == (1024, 1024), 'Icon dimensions must be 1024 square')
    check(png[25] == 2, 'Icon must be opaque RGB')
    check('SmartWakeArtwork.xcassets' in text and 'SmartWakeIcon' in text, 'Icon must be wired into project')
for path in root.rglob('*'):
    if not path.is_file() or any(part in {'.git', '__pycache__', '.build', 'DerivedData'} for part in path.parts): continue
    check(path.suffix not in {'.p12', '.mobileprovision', '.pem', '.healthkit'}, f'Sensitive file {path}')
print(f'PASS: {checks} structural/privacy smoke checks. Swift compilation and XCTest execution NOT covered.')
