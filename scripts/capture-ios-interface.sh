#!/bin/bash
# Capture the Debug app shell and explicit activity fixtures without loading a model.
set -euo pipefail

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_root"
app_path="${1:-build/DerivedData/Build/Products/Debug-iphonesimulator/fullmoon.app}"
output_path="${2:-build/interface-captures}"

exec python3 - "$app_path" "$output_path" <<'PY'
import json
import os
from pathlib import Path
import plistlib
import re
import signal
import struct
import subprocess
import sys
import time
import uuid


def command(*args, timeout=30, check=True, env=None):
    return subprocess.run(args, check=check, capture_output=True, text=True,
                          timeout=timeout, env=env)


def simctl(*args, **kwargs):
    return command('xcrun', 'simctl', *args, **kwargs)


def version(value):
    parts = [int(part) for part in re.findall(r'\d+', str(value))[:3]]
    return tuple((parts + [0, 0, 0])[:3])


def stop_for_timeout(_signal, _frame):
    raise TimeoutError('Simulator interface capture exceeded eight minutes.')


def stop_for_signal(received_signal, _frame):
    raise SystemExit(128 + received_signal)


def assert_running(pid, executable):
    os.kill(pid, 0)
    process = command('/bin/ps', '-p', str(pid), '-o', 'comm=').stdout.strip()
    if Path(process).name != executable:
        raise RuntimeError(f'The launched app is no longer running as PID {pid}.')


def supports_activity_fixtures(app, executable):
    marker = b'NOCTIS_ACTIVITY_PREVIEW'
    # ENABLE_DEBUG_DYLIB can move Swift code out of the executable into a sibling dylib.
    candidates = [app / executable, *app.glob('*.debug.dylib')]
    for candidate in candidates:
        if not candidate.is_file() or candidate.resolve().parent != app:
            continue
        # Bound memory use and retain an overlap for markers crossing a chunk boundary.
        with candidate.open('rb') as binary:
            overlap = b''
            for chunk in iter(lambda: binary.read(1024 * 1024), b''):
                data = overlap + chunk
                if marker in data:
                    return True
                overlap = data[-(len(marker) - 1):]
    return False


app = Path(sys.argv[1]).resolve()
output = Path(sys.argv[2]).resolve()
if output.exists() and any(output.iterdir()):
    raise SystemExit('The capture directory is not empty; refusing to reuse old screenshots.')
output.mkdir(parents=True, exist_ok=True)
metadata = {
    'scope': 'Compiled app shell and explicit activity presentation fixtures only; '
             'no inference or live-tool validation.',
    'captures': [],
}
created_devices = []
signal.signal(signal.SIGALRM, stop_for_timeout)
signal.signal(signal.SIGTERM, stop_for_signal)
signal.alarm(480)

try:
    with (app / 'Info.plist').open('rb') as source:
        info = plistlib.load(source)
    if 'iPhoneSimulator' not in info.get('CFBundleSupportedPlatforms', []):
        raise RuntimeError('The supplied app must be built for the iOS Simulator.')
    bundle_id = info['CFBundleIdentifier']
    executable = info['CFBundleExecutable']
    if not supports_activity_fixtures(app, executable):
        raise RuntimeError('Activity fixture captures require a Debug build with preview support.')
    metadata.update(bundle_id=bundle_id, minimum_os=info['MinimumOSVersion'],
                    commit=command('git', 'rev-parse', 'HEAD').stdout.strip())
    inventory = json.loads(simctl('list', '--json').stdout)
    metadata['available_ios_runtimes'] = [runtime['version'] for runtime in inventory['runtimes']
                                         if runtime.get('isAvailable') and '.iOS-' in runtime['identifier']]
    runtimes = [runtime for runtime in inventory['runtimes']
                if runtime.get('isAvailable') and '.iOS-' in runtime['identifier']
                and version(runtime['version']) >= version(info['MinimumOSVersion'])]
    if not runtimes:
        raise RuntimeError('No installed iOS Simulator runtime satisfies the app minimum OS.')
    runtime = max(runtimes, key=lambda item: version(item['version']))
    metadata['runtime'] = runtime['identifier']
    runtime_parts = version(runtime['version'])
    runtime_number = (runtime_parts[0] << 16) | (runtime_parts[1] << 8) | runtime_parts[2]
    available_types = {
        device.get('deviceTypeIdentifier')
        for device in inventory.get('devices', {}).get(runtime['identifier'], [])
        if device.get('isAvailable')
    }
    launch_environment = dict(os.environ, SIMCTL_CHILD_XCODE_RUNNING_FOR_PREVIEWS='1')
    launch_environment.pop('SIMCTL_CHILD_NOCTIS_ACTIVITY_PREVIEW', None)

    for family in ('iPhone', 'iPad'):
        candidates = [item for item in inventory['devicetypes']
                      if item.get('productFamily', item['name'].split(' ')[0]) == family
                      and item.get('minRuntimeVersion', 0) <= runtime_number
                      and item.get('maxRuntimeVersion', 0xFFFFFFFF) >= runtime_number]
        if not candidates:
            if family == 'iPhone':
                raise RuntimeError('No iPhone device type supports the selected runtime.')
            metadata['ipad_skipped'] = 'No compatible iPad device type is installed.'
            continue
        existing = [item for item in candidates if item['identifier'] in available_types]
        device_type = (existing or candidates)[-1]
        device_name = f'Noctis UI QA {family} {uuid.uuid4().hex[:8]}'
        device_id = simctl('create', device_name, device_type['identifier'], runtime['identifier']).stdout.strip()
        if not re.fullmatch(r'[0-9A-Fa-f-]{36}', device_id):
            raise RuntimeError('simctl create did not return a simulator identifier.')
        created_devices.append(device_id)
        simctl('boot', device_id)
        simctl('bootstatus', device_id, '-b', timeout=180)
        simctl('install', device_id, str(app), timeout=90)
        for appearance in ('light', 'dark'):
            simctl('ui', device_id, 'appearance', appearance)
            scenarios = (None, 'searching', 'completed') if family == 'iPhone' else (None,)
            for scenario in scenarios:
                environment = dict(launch_environment)
                if scenario:
                    environment['SIMCTL_CHILD_NOCTIS_ACTIVITY_PREVIEW'] = scenario
                launched = simctl('launch', '--terminate-running-process', device_id, bundle_id,
                                 '-hasCompletedNoctisOnboarding', 'YES',
                                 '-AppleLanguages', '(fr)', '-AppleLocale', 'fr_FR',
                                 env=environment)
                match = re.search(r':\s*(\d+)\s*$', launched.stdout)
                if not match:
                    raise RuntimeError(f'simctl launch did not report the app PID: {launched.stdout}')
                pid = int(match.group(1))
                # Fixtures bypass the store and model; three seconds suffice for their initial layout.
                for _ in range(3 if scenario else 8):
                    assert_running(pid, executable)
                    time.sleep(1)
                suffix = f'-activity-{scenario}' if scenario else ''
                image = output / f'{family.lower()}{suffix}-{appearance}-fr.png'
                simctl('io', device_id, 'screenshot', '--type=png', str(image))
                assert_running(pid, executable)
                header = image.read_bytes()[:24]
                if len(header) < 24 or header[:8] != b'\x89PNG\r\n\x1a\n':
                    raise RuntimeError('Simulator did not produce a valid PNG screenshot.')
                width, height = struct.unpack('>II', header[16:24])
                if min(width, height) < 100:
                    raise RuntimeError('Simulator screenshot dimensions are invalid.')
                capture = {'file': image.name, 'device': device_type['name'],
                           'appearance': appearance, 'width': width, 'height': height,
                           'launch_pid': pid, 'inference_validated': False}
                if scenario:
                    capture.update(scope='Activity presentation fixture from explicit reducer events; '
                                         'no model, tools or persistent conversation store.',
                                   fixture=scenario, details_expanded=True, animation_frozen=True)
                else:
                    capture.update(scope='Default application shell with model loading disabled.')
                metadata['captures'].append(capture)
                print(f'Captured {image.name}: {device_type["name"]}, {width}x{height}', flush=True)
        simctl('shutdown', device_id)
        simctl('delete', device_id)
        created_devices.remove(device_id)
    metadata['status'] = 'captured'
except BaseException as error:
    metadata['status'] = 'failed'
    metadata['error'] = str(error)
    if isinstance(error, subprocess.CalledProcessError):
        metadata['command_error'] = error.stderr
    raise
finally:
    signal.alarm(0)
    for device_id in created_devices:
        for operation in ('shutdown', 'delete'):
            try:
                simctl(operation, device_id, check=False)
            except (OSError, subprocess.SubprocessError) as error:
                print(f'Could not {operation} QA simulator {device_id}: {error}', file=sys.stderr)
    (output / 'capture-manifest.json').write_text(json.dumps(metadata, indent=2))
PY
