"""App-private, temporary live-game instrumentation transport (not UI simulation)."""
import argparse, json, os, subprocess, time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = 'com.thepictureshop.game'
REMOTE = 'files/save/the-picture-shop'
DEFAULT_SERIAL = os.environ.get('TPS_ANDROID_SERIAL', '')

def adb(serial, *args, binary=False):
    if not serial:
        raise RuntimeError('Set TPS_ANDROID_SERIAL to the selected adb device serial.')
    data = subprocess.check_output(['adb', '-s', serial, *map(str,args)], timeout=45, stderr=subprocess.PIPE)
    return data if binary else data.decode('utf-8', 'replace')

def put(serial, local, name):
    assert '/' not in name and '\\' not in name
    adb(serial,'push',str(local),'/data/local/tmp/tps-live-transfer')
    adb(serial,'shell','run-as',PACKAGE,'cp','/data/local/tmp/tps-live-transfer',REMOTE+'/'+name)

def command(target, source, output, serial=DEFAULT_SERIAL, timeout=25):
    output=Path(output);output.mkdir(parents=True,exist_ok=True)
    identifier=str(time.time_ns())
    path=output/(identifier+'.lua')
    path.write_text('-- id:'+identifier+'\n'+source,encoding='utf-8')
    if target=='phone':
        put(serial,path,'live-command.pending')
        adb(serial,'shell','run-as',PACKAGE,'mv',REMOTE+'/live-command.pending',REMOTE+'/live-command.lua')
    else:
        destination=Path(os.environ['APPDATA'])/'LOVE/the-picture-shop/live-command.lua'
        temporary=destination.with_suffix('.pending');temporary.write_bytes(path.read_bytes());temporary.replace(destination)
    deadline=time.monotonic()+timeout
    while time.monotonic()<deadline:
        try:
            if target=='phone': raw=adb(serial,'exec-out','run-as',PACKAGE,'cat',REMOTE+'/live-result.json')
            else: raw=(Path(os.environ['APPDATA'])/'LOVE/the-picture-shop/live-result.json').read_text()
            result=json.loads(raw)
            if result.get('id')==identifier:
                (output/(identifier+'.json')).write_text(json.dumps(result,indent=2),encoding='utf-8')
                if not result['okay']: raise RuntimeError(result['result'])
                return result.get('result')
        except (FileNotFoundError,json.JSONDecodeError,subprocess.CalledProcessError): pass
        time.sleep(.3)
    raise TimeoutError('No live game response from '+target)

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('target',choices=('pc','phone'));p.add_argument('--file',type=Path)
    p.add_argument('--code');p.add_argument('--serial',default=DEFAULT_SERIAL)
    p.add_argument('--output',type=Path,default=ROOT/'output/live-gameplay-20261109/commands')
    p.add_argument('--timeout',type=float,default=25)
    args=p.parse_args()
    source=args.file.read_text(encoding='utf-8') if args.file else args.code or 'return R.liveInspect()'
    print(json.dumps(command(args.target,source,args.output,args.serial,args.timeout),indent=2))
