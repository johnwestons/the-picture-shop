"""Read-only observation of a manual physical-device town journey."""
import json
import math
from pathlib import Path
import re
import subprocess
import time


def apk_identity(phone, report):
    from android_town_journey import PACKAGE
    pkg=phone.command("shell","dumpsys","package",PACKAGE)
    path_lines=phone.command("shell","pm","path",PACKAGE).splitlines()
    path=next(s.removeprefix("package:") for s in path_lines if s.rstrip().endswith("/base.apk"))
    # Trim only validated hex, never treat an unparsed diagnostic as a hash.
    digest=phone.command("shell","sha256sum",path).split()[0].lower()
    if not re.fullmatch(r"[0-9a-f]{64}",digest):
        raise RuntimeError("Cannot read hash of the installed base.apk")
    identity={"package":PACKAGE,"serial":phone.command("get-serialno").strip(),
              "model":phone.command("shell","getprop","ro.product.model").strip(),
              "versionCode":int(re.search(r"\bversionCode=(\d+)",pkg).group(1)),
              "versionName":re.search(r"\bversionName=(\S+)",pkg).group(1),
              "apkSha256":digest,"apkPath":path}
    if report:
        expected=json.loads(Path(report).read_text(encoding="utf-8-sig"))
        if (digest!=expected["sha256"].lower() or identity["versionCode"]!=expected["versionCode"]
                or identity["versionName"]!=expected["versionName"]):
            raise RuntimeError("Installed APK does not match the supplied build report")
    return identity


def monitor(phone, until, timeout, interval, report):
    from android_town_journey import PACKAGE, blue_fraction, summary
    directory=phone.output/("manual-"+time.strftime("%Y%m%d-%H%M%S")+"-"+str(time.time_ns()%1000000))
    directory.mkdir(parents=True,exist_ok=False)
    result={"status":"observing","readOnly":True,"initialPid":phone.pid,"slot":phone.slot,
            "target":until,"startedAt":time.time(),"directory":str(directory),
            "samples":0,"mountedDistanceObserved":0,"screenshots":[]}
    end=time.monotonic()+timeout
    def write():
        (directory/"report.json").write_text(json.dumps(result,indent=2),encoding="utf-8")
    def picture(raw, label, now):
        name=f'{result["samples"]:04d}-{label}.png'
        (directory/name).write_bytes(raw)
        result["screenshots"].append({"file":name,"time":now})
    print("Read-only device monitor: "+str(directory),flush=True)
    previous=None;last_image=0;previous_leg=None;previous_point=None
    try:
        result["apk"]=apk_identity(phone,report)
        write()
        with (directory/"observations.jsonl").open("w",encoding="utf-8") as log:
            while time.monotonic()<end:
                now=time.time()
                current=subprocess.run(phone.adb+["shell","pidof",PACKAGE],capture_output=True,text=True,timeout=10)
                if current.stdout.strip()!=phone.pid:
                    result["observedPid"]=current.stdout.strip()
                    raise RuntimeError("Game process exited or restarted during manual play")
                phone.focus()
                raw=phone.screenshot()
                fraction=blue_fraction(raw)
                errors=phone.command("logcat","-d","--pid",phone.pid,"-t","250")
                if fraction>=.7 or any(re.search(r"FATAL EXCEPTION|Fatal signal \d|Error: .*\.lua:\d|stack traceback:",line,re.I)
                                       for line in errors.splitlines()):
                    picture(raw,"error",now)
                    raise RuntimeError("Android or LÖVE error detected; inspect the captured screen and log")
                try:
                    state=summary(phone.state())
                except FileNotFoundError:
                    state={"scene":"awaiting-slot"}
                result["samples"]+=1
                leg=(state.get("tripToken"),state.get("origin"),state.get("destination"))
                pose=(state["scene"],leg,bool(state.get("gear",{}).get("mounted")),bool(state.get("bike",{}).get("reverse")))
                point=state.get("bike") if pose[2] else None
                if point and previous_point and leg==previous_leg:
                    result["mountedDistanceObserved"]+=math.hypot(point["x"]-previous_point["x"],point["z"]-previous_point["z"])
                previous_leg,previous_point=leg,point
                if pose!=previous or now-last_image>=12 or state["scene"]==until:
                    picture(raw,state["scene"]+("-mounted" if pose[2] else ""),now)
                    last_image=now
                previous=pose
                entry={"time":now,"state":state,"blueFraction":fraction}
                if point:
                    entry["distanceToParking"]=round(math.hypot(point["x"]-state["parking"]["x"],point["z"]-state["parking"]["z"]),2)
                log.write(json.dumps(entry)+"\n");log.flush()
                result["last"]=entry
                print(f'{state["scene"]}: {state.get("origin","")} -> {state.get("destination","")}  '
                      f'mounted={pose[2]} reverse={pose[3]} parking={entry.get("distanceToParking","-")}  '
                      f'observed movement={result["mountedDistanceObserved"]:.1f} m',flush=True)
                if state["scene"]==until:
                    result["status"]="target_scene_observed";write()
                    return
                write()
                time.sleep(interval)
        result["status"]="timeout"
        raise TimeoutError("Manual play has not reached the requested scene within the observation window")
    except BaseException as error:
        if result["status"]=="observing": result["status"]="interrupted" if isinstance(error,KeyboardInterrupt) else "failed"
        result["detail"]=str(error) or type(error).__name__
        # Best-effort evidence for a lost Activity, PID change, or screenshot error.
        try:
            phone.focus()
            picture(phone.screenshot(),"last-screen",time.time())
        except (RuntimeError,OSError,subprocess.SubprocessError): pass
        raise
    finally:
        try:
            (directory/"process-logcat.txt").write_text(phone.command("logcat","-d","--pid",phone.pid),encoding="utf-8")
        except (OSError,subprocess.SubprocessError): pass
        result["finishedAt"]=time.time();write()
