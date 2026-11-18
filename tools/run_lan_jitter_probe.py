"""Compare real ENet state delivery through jitter with zero injected loss.

Requires LÖVE with ENet. Runs isolated loopback sessions and disposable save
identities; never connects to a player's game. The unsequenced case must deliver
all movement/physics updates and all reliable messages. The sequenced case is a
diagnostic comparison, not a pass requirement. Reports retain proxy counters.
"""
import argparse
import datetime
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--love', default=shutil.which('lovec') or shutil.which('love')
                        or r'C:\Program Files\LOVE\lovec.exe')
    parser.add_argument('--port', type=int, default=24940)
    parser.add_argument('--ticks', type=int, default=180)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if not 1024 <= args.port <= 65532 or not 12 <= args.ticks <= 720:
        parser.error('Choose a port from 1024 to 65532 and 12 to 720 ticks.')
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    out = (args.output or ROOT / 'output/lan-jitter-probe' / stamp).resolve()
    out.mkdir(parents=True, exist_ok=False)
    flags = subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0
    duration = args.ticks / 12 + 15
    for index, flag in enumerate(('unreliable', 'unsequenced')):
        port = args.port + index * 2
        profile = {'name': 'jitter-' + flag, 'seed': 120,
                   'upstream': {'latency_ms': 75, 'jitter_ms': 30, 'loss': 0},
                   'downstream': {'latency_ms': 75, 'jitter_ms': 30, 'loss': 0},
                   'queue': {'max_packets': 512, 'max_bytes': 262144, 'max_delay_ms': 2000}}
        control = out / (flag + '-profile.json')
        control.write_text(json.dumps(profile), encoding='utf-8')
        with (out / (flag + '-proxy.log')).open('wb') as proxy_log:
            proxy = subprocess.Popen([sys.executable, str(ROOT / 'tools/lan_impairment_proxy.py'),
                '--listen', f'127.0.0.1:{port+1}', '--target', f'127.0.0.1:{port}',
                '--control', str(control), '--stats', str(out / (flag + '-proxy.json')),
                '--duration', str(duration)], cwd=ROOT, stdout=proxy_log,
                stderr=subprocess.STDOUT, creationflags=flags)
            try:
                time.sleep(.3)
                if proxy.poll() is not None:
                    raise RuntimeError('Proxy did not start; inspect ' + str(proxy_log.name))
                report = out / (flag + '.txt')
                env = os.environ.copy()
                env.update(ENET_PROBE_FLAG=flag, ENET_PROBE_PORT=str(port),
                           ENET_PROBE_TICKS=str(args.ticks), ENET_PROBE_ROOT=str(ROOT),
                           ENET_PROBE_REPORT=str(report.resolve()), APPDATA=str(out / ('appdata-' + flag)))
                result = subprocess.run([args.love, str(ROOT / 'tools/probes/lan_jitter')],
                    cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                    timeout=duration, creationflags=flags)
                (out / (flag + '-stdout.txt')).write_bytes(result.stdout)
                print(report.read_text(encoding='utf-8') if report.exists() else result.stdout.decode('utf-8', 'replace'), flush=True)
                if result.returncode != 0:
                    raise RuntimeError(flag + ' probe failed; inspect ' + str(out))
            finally:
                if proxy.poll() is None:
                    proxy.terminate()
                proxy.wait(timeout=10)
    print('PASS: real ENet jitter regression; evidence=' + str(out), flush=True)


if __name__ == '__main__':
    main()
