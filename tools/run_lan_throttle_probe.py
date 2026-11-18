"""Measure native ENet RTT-throttle blackholes and overload recovery on localhost.

Runs four isolated native links for 46 seconds: settled clean RTT, increased latency
without loss or a bandwidth cap, then a ten-second 8KB/s bottleneck and recovery.
Compares default ENet, shorter recalibration, faster recovery, and disabled backoff.
Only shorter recalibration is used by the game; the other cases are diagnostics.
Requires LOVE with ENet/LuaSocket. No player game or device is contacted.
"""
import argparse
import datetime
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--love', default=shutil.which('lovec') or shutil.which('love')
                        or r'C:\Program Files\LOVE\lovec.exe')
    parser.add_argument('--port', type=int, default=23950)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if not 1024 <= args.port <= 65528:
        parser.error('Choose a base port from 1024 to 65528 for eight localhost sockets.')
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    out = (args.output or ROOT / 'output/lan-throttle-probe' / stamp).resolve()
    out.mkdir(parents=True, exist_ok=False)
    report = out / 'throttle.txt'
    env = os.environ.copy()
    env.update(ENET_PROBE_ROOT=str(ROOT), ENET_PROBE_PORT=str(args.port),
               ENET_PROBE_REPORT=str(report), APPDATA=str(out / 'appdata'))
    result = subprocess.run([args.love, str(ROOT / 'tools/probes/lan_throttle')],
                            cwd=ROOT, env=env, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=70,
                            creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
    (out / 'stdout.txt').write_bytes(result.stdout)
    content = report.read_text(encoding='utf-8') if report.exists() else ''
    print('\n'.join(line for line in content.splitlines()
                    if line.startswith(('RESULT', 'COMPLETE', 'FAIL'))), flush=True)
    if result.returncode != 0 or not content.endswith('COMPLETE\n'):
        raise RuntimeError('Native ENet throttle probe failed; inspect ' + str(out))
    print('Evidence=' + str(out), flush=True)


if __name__ == '__main__':
    main()
