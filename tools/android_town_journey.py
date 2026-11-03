"""Exercise and record the installed Picture Shop APK using Android touch input.

Examples (a debug-signed tester APK permits read-only run-as access):
  python tools/android_town_journey.py status
  python tools/android_town_journey.py new --seed 52 --replace-test-slot
  python tools/android_town_journey.py departure
  python tools/android_town_journey.py mount
  python tools/android_town_journey.py ride
  python tools/android_town_journey.py arrive
  python tools/android_town_journey.py verify
  python tools/android_town_journey.py monitor --until home --timeout 900

Use seed 52 and the default brick walk-up for a short trip. Start in the
warehouse, use the door, choose Explore Town, confirm, equip and mount before
running ride. For two-way coverage, repeat from the apartment. No save is
written by this tool. Navigation and interaction use the installed game's
ordinary controls. A checkpoint requires both a foreground game screenshot and
its actual saved scene. Captures must also be inspected for a completed draw.
"""
import argparse
import ctypes
import io
import json
import math
import os
from pathlib import Path
import re
import subprocess
import time

from PIL import Image
from audit_lua_limits import Compiler, library_path

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = "com.thepictureshop.game"

# Decode only the named durable fields and use the game's own route solver.
# Saving recovery copies of private player data is unnecessary.
INSPECT = b"""
local bytes=...
local read=assert(loadstring('return '..bytes))
setfenv(read,{})
local slot=read()
local home=slot.state.home
local town=home.town
local info={scene=slot.player.sceneId or 'warehouse',player=slot.player,
  apartment=home.apartmentId,seed=town and town.seed,slot=slot.slot,balanceCents=home.balanceCents}
if info.scene=='warehouse' then
  -- Use the same floor mask and fixed equipment obstacles as an actual walker.
  love={timer={getTime=os.clock}}
  local assets={getData=function() end,get=function() end}
  local context=require('src.world').employeeContext(slot.state,assets)
  local door=require('src.warehouse_registration').entrance
  info.shopDoor={x=door.x,y=door.y}
  local goals={{x=door.x,y=door.y+3}}
  -- A visitor can stand directly on the threshold. Use whichever point
  -- inside the door's interaction radius is free, just as a player can.
  for i=0,7 do
    local angle=i*math.pi/4
    goals[#goals+1]={x=door.x+20*math.cos(angle),y=door.y+20*math.sin(angle)}
  end
  info.walkPath=require('src.npc_navigation').findPath(
    {id=1,x=slot.player.x,y=slot.player.y,sceneId='warehouse'},goals,context)
end
local trip=home.commute
if trip then
  local part=assert(trip.participants.owner)
  local w=require('src.commute.town').world(town)
  local route=assert(require('src.commute.routes').new(w.roads):find(trip.origin,trip.destination))
  info.origin,info.destination=trip.origin,trip.destination
  info.tripToken=trip.token
  info.bike,info.ped,info.gear=part.rider.bike,part.rider.ped,part.rider.gear
  info.speed=(part.presentation or {}).speed or 0
  info.roadPoints=route.points
  info.routeLength=route.length
  info.parking=w.roads.destinations[trip.destination]
  info.door=w.sites.byId[trip.destination].door
end
return require('tools.performance_probe.json')(info)
"""

def inspect_save(raw):
    lib = Compiler(library_path(None)).lib
    lib.lua_pushlstring.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t]
    lib.lua_pushlstring.restype = ctypes.c_void_p
    state = lib.luaL_newstate()
    try:
        lib.luaL_openlibs(state)
        status = lib.luaL_loadbuffer(state, INSPECT, len(INSPECT), b"@android_town_journey")
        if not status:
            lib.lua_pushlstring(state, raw, len(raw))
            status = lib.lua_pcall(state, 1, 1, 0)
        size = ctypes.c_size_t()
        pointer = lib.lua_tolstring(state, -1, ctypes.byref(size))
        result = ctypes.string_at(pointer, size.value).decode("utf-8")
        if status:
            raise RuntimeError(result)
        return json.loads(result)
    finally:
        lib.lua_close(state)


def summary(data):
    return {k:v for k,v in data.items() if k != "roadPoints"}


class SlotPending(FileNotFoundError):
    """The app has not committed its first primary for this slot."""


def blue_fraction(raw):
    sample=Image.open(io.BytesIO(raw)).convert("RGB").resize((65,37)).tobytes()
    n=len(sample)//3
    return sum(b>100 and b>g*1.35 and b>r*2 for r,g,b in zip(sample[::3],sample[1::3],sample[2::3]))/n


class JourneyLease:
    """Hold one OS lock per serial during observation or input, including across output folders."""
    def __init__(self,phone):
        serial=phone.command("get-serialno").strip()
        key=re.sub(r'[^A-Za-z0-9_.-]','_',serial)
        location=ROOT/"output/mobile/journey-locks"
        location.mkdir(exist_ok=True,parents=True)
        self.file=(location/(key+".lock")).open("a+b")
    def __enter__(self):
        self.file.seek(0,2)
        if not self.file.tell():
            self.file.write(b"1");self.file.flush()
        self.file.seek(0)
        try:
            if os.name=="nt":
                import msvcrt
                msvcrt.locking(self.file.fileno(),msvcrt.LK_NBLCK,1)
            else:
                import fcntl
                fcntl.flock(self.file,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except OSError as exc:
            self.file.close()
            raise RuntimeError("A journey driver or manual monitor already owns this device. No input sent.") from exc
        return self
    def __exit__(self,*unused):
        self.file.close()


class Phone:
    def __init__(self, args):
        self.slot = args.slot
        self.output = args.output
        self.adb = [os.environ.get("ADB", str(ROOT / "output/mobile/tooling/android-sdk/platform-tools/adb.exe"))]
        if args.port:
            self.adb += ["-P", str(args.port)]
        if args.serial:
            self.adb += ["-s", args.serial]
        self.bounds = args.viewport
        self.read_only=args.action in ("monitor","status","record")
        self.pid = self.command("shell", "pidof", PACKAGE).strip()
        if not self.pid:
            raise RuntimeError("Open the installed game first")
        self.focus()

    def command(self, *args, binary=False):
        if self.read_only and args[:2]==("shell","input"):
            raise RuntimeError("Touch input is disabled in read-only observation mode")
        output = subprocess.check_output(self.adb + list(args), timeout=25)
        return output if binary else output.decode("utf-8", "replace")

    def focus(self):
        line = next((line for line in self.command("shell","dumpsys","window").splitlines()
                     if "mCurrentFocus=" in line), "")
        if PACKAGE not in line or self.command("shell","pidof",PACKAGE).strip() != self.pid:
            raise RuntimeError("Game lost foreground or restarted: " + line)
        return line.strip()

    def screenshot(self):
        return self.command("exec-out","screencap","-p",binary=True)

    def point(self, x, y):
        if self.bounds is None:
            width,height = Image.open(io.BytesIO(self.screenshot())).size
            if width < height:
                raise RuntimeError("Landscape game viewport required")
            self.bounds = (0,0,width,height)
        left,top,width,height = self.bounds
        scale = min(width/960,height/678)
        return str(round(left+(width-960*scale)/2+x*scale)), str(round(top+(height-678*scale)/2+y*scale))

    def interior_control(self, control, dx=0, dy=0, ms=0):
        # The interior mobile HUD anchors to the full viewport, including
        # widescreen gutters. Exterior bike buttons anchor to the design frame.
        self.point(0,0)
        left,top,width,height=self.bounds
        scale=min(width/960,height/678)
        if control=="use":
            p=(str(round(left+.906*width)),str(round(top+.846*height)))
            self.command("shell","input","tap",*p)
        else:
            x=left+max(80*scale,.105*width)
            y=top+min(height-80*scale,.846*height)
            length=math.hypot(dx,dy)
            if not length:
                return
            # A press starts inside the actual joystick and sets its axis
            # immediately, even with the Android swipe start/end identical.
            p=(str(round(x+68*scale*dx/length)),str(round(y+68*scale*dy/length)))
            self.command("shell","input","swipe",*p,*p,str(round(ms)))

    def press(self, x, y, ms=0):
        p = self.point(x,y)
        if ms:
            self.command("shell","input","swipe",*p,*p,str(round(ms)))
        else:
            self.command("shell","input","tap",*p)

    def state(self):
        path=f"files/save/the-picture-shop/saves/slot{self.slot}.lua"
        result=subprocess.run(self.adb+["exec-out","run-as",PACKAGE,"cat",path],
                              capture_output=True,timeout=25)
        # Some Android exec-out implementations return zero and put remote
        # cat diagnostics on stdout. Only the missing named primary is normal
        # while a new shop's first write is in flight.
        if result.returncode or not result.stdout.lstrip().startswith(b"{"):
            diagnostic=(result.stdout+result.stderr).decode("utf-8","replace").strip()
            if len(diagnostic)<1024 and path in diagnostic and "No such file or directory" in diagnostic:
                raise SlotPending(path)
            raise RuntimeError("Cannot read the installed game's save: "+diagnostic[:300])
        return inspect_save(result.stdout)

    def record(self, label, expected):
        self.output.mkdir(parents=True,exist_ok=True)
        focus = self.focus()
        raw = self.screenshot()
        (self.output / (label+".png")).write_bytes(raw)
        # The LÖVE error screen can leave the same process and Activity alive.
        # Its background is saturated blue. Check pixels as well as logcat.
        blue = blue_fraction(raw)
        logs = self.command("logcat","-d","--pid",self.pid)
        (self.output / (label+"-logcat.txt")).write_text(logs, encoding="utf-8")
        errors = [line for line in logs.splitlines() if re.search(
            r"FATAL EXCEPTION|Fatal signal [0-9]|Error: src/[^\n]*\.lua:\d+|stack traceback:", line, re.I)]
        try:
            saved=summary(self.state())
        except (SlotPending,subprocess.CalledProcessError,RuntimeError) as problem:
            saved={"scene":None,"readError":str(problem)}
        entry = {"stage":label,"expectedScene":expected,"focus":focus,"pid":self.pid,"capturedAt":time.time(),
                 "blueFraction":blue,"errors":errors,"state":saved,"screenshot":label+".png"}
        entry["passed"] = blue < .7 and not errors and "readError" not in saved and (not expected or saved["scene"] == expected)
        (self.output / (label+".json")).write_text(json.dumps(entry,indent=2),encoding="utf-8")
        if not entry["passed"]:
            raise RuntimeError("Failed checkpoint, inspect " + str(self.output / (label+".json")))
        print(json.dumps(entry,indent=2))

    def fresh_mounted_state(self, expected=None):
        # A headlight toggle takes the same ordinary save path as other riding
        # commands. This gives the controller current position rather than a
        # five-second-old periodic checkpoint. No game state is injected.
        before = self.state()
        validate_drive_state(before,expected)
        previous = before["bike"].get("headlight",False)
        self.press(.84*960,.88*678)
        for _ in range(20):
            time.sleep(.10)
            value = self.state()
            validate_drive_state(value,before)
            if value["bike"].get("headlight",False) != previous:
                return value
        raise RuntimeError("Headlight input did not reach the bike; inspect viewport, screen and controls")


def distance(a,b):
    return math.hypot(a["x"]-b["x"],a["z"]-b["z"])


def validate_drive_state(state,expected=None):
    gear=state.get("gear",{})
    if state.get("scene")!="commute" or not gear.get("mounted") or not gear.get("engine"):
        raise RuntimeError("Driver stopped: the motorcycle is no longer mounted and running")
    if state["bike"].get("reverse"):
        raise RuntimeError("Driver stopped: reverse is selected. Choose forward before starting an automatic ride.")
    if expected and any(state.get(k)!=expected.get(k) for k in ("tripToken","origin","destination","slot","seed")):
        raise RuntimeError("Driver stopped: the active trip changed")
    if expected and state["bike"].get("damage")!=expected["bike"].get("damage"):
        raise RuntimeError("Driver stopped: collision damage changed")


def ride(phone, timeout):
    started = time.monotonic()
    car = phone.fresh_mounted_state()
    if not car["gear"].get("engine"):
        raise RuntimeError("Start the engine before riding")
    index = min(range(len(car["roadPoints"])),key=lambda i:distance(car["bike"],car["roadPoints"][i]))
    best_index=index;best_gap=math.inf;advanced=started
    while time.monotonic()-started < timeout:
        phone.focus()
        bike,points,parking = car["bike"],car["roadPoints"],car["parking"]
        remaining = distance(bike,parking)
        speed = car["speed"]
        while index<len(points)-1 and distance(bike,points[index])<4.5:
            index+=1
        gap=distance(bike,points[index])
        if index>best_index or gap<best_gap-.65:
            best_index,best_gap,advanced=index,gap,time.monotonic()
        if time.monotonic()-advanced>8:
            raise RuntimeError("Driver stopped: no progress toward the next road point for 8 seconds. Inspect the bike before resuming.")
        dx,dz=points[index]["x"]-bike["x"],points[index]["z"]-bike["z"]
        delta=(math.atan2(dz,dx)-bike["heading"]+math.pi)%(2*math.pi)-math.pi
        print(f"point {index}/{len(points)-1}  to parking {remaining:.1f} m  speed {speed:.1f}  turn {math.degrees(delta):.0f}°",flush=True)
        if remaining<3.5:
            phone.press(.94*960,.56*678,1200)
            car=phone.fresh_mounted_state(car)
            if distance(car["bike"],parking)<5 and car["speed"]<.05:
                return car
            continue
        if abs(delta)>.22 and speed>1.3:
            # The bike coasts under its own physics while the steering pad is held.
            phone.press(.10*960+math.copysign(60,delta),.80*678,min(750,max(200,abs(delta)*700)))
        elif speed < (3.1 if abs(delta)>.35 or remaining<7 else 4.8):
            phone.press(.84*960,.56*678,380 if remaining<7 else 650)
        elif speed>5:
            phone.press(.94*960,.56*678,240)
        else:
            time.sleep(.22)
        car=phone.fresh_mounted_state(car)
    raise RuntimeError("Could not reach parking within the time limit. Capture the current screen and investigate.")


def wait_for_state(phone, predicate, timeout):
    end=time.monotonic()+timeout
    last="no checkpoint observed"
    while time.monotonic()<end:
        try:
            value=phone.state()
            if predicate(value):
                return value
            last=json.dumps(summary(value))
        except SlotPending as pending:
            last="waiting for "+str(pending)
        time.sleep(.25)
    raise RuntimeError("Timed out waiting for game progress. Last observation: "+last)


def new_shop(phone, seed, replace):
    # Only run from the title. Honour the selected slot's overwrite confirmation.
    listing=subprocess.run(phone.adb+["shell","run-as",PACKAGE,"ls","files/save/the-picture-shop/saves"],
                           capture_output=True,text=True,timeout=15)
    if listing.returncode and "No such file" not in listing.stdout+listing.stderr:
        raise RuntimeError("Cannot inspect test slot: "+listing.stdout+listing.stderr)
    files=listing.stdout.splitlines()
    occupied=any(f.startswith(f"slot{phone.slot}.lua") for f in files)
    if occupied and not replace:
        raise RuntimeError("The selected slot already has a save. Use --replace-test-slot only for a disposable test slot.")
    phone.press(480,370+(phone.slot-1)*58)
    phone.press(210,544)
    time.sleep(.65)
    if occupied:
        phone.press(395,410)
        time.sleep(.55)
    phone.press(800,613)
    time.sleep(.8)
    phone.press(745,138)
    time.sleep(.5)
    phone.command("shell","input","text",str(seed))
    phone.command("shell","input","keyevent","KEYCODE_ENTER")
    time.sleep(.7)
    phone.press(678,191)
    time.sleep(.45)
    phone.press(800,618)
    wait_for_state(phone,lambda s:s["scene"]=="warehouse" and s.get("seed")==seed and s["slot"]==phone.slot,18)
    phone.record("new-shop","warehouse")


def departure(phone):
    data=phone.state()
    if data["scene"]=="warehouse":
        for _ in range(12):
            p=data["player"];goal=data["shopDoor"]
            dist=math.hypot(goal["x"]-p["x"],goal["y"]-p["y"])
            if dist<29:
                break
            points=data.get("walkPath",[])
            if not points: raise RuntimeError("No walkable path to the shop door")
            waypoint=next((v for v in points if math.hypot(v["x"]-p["x"],v["y"]-p["y"])>8),goal)
            dx,dy=waypoint["x"]-p["x"],waypoint["y"]-p["y"]
            phone.interior_control("stick",dx,dy,min(1900,max(200,math.hypot(dx,dy)*6.7)))
            data=wait_for_state(phone,lambda s: math.hypot(s["player"]["x"]-p["x"],s["player"]["y"]-p["y"])>1,12)
        else: raise RuntimeError("Could not walk to the front door")
    elif data["scene"]!="home":
        raise RuntimeError("Start departure inside the warehouse or beside the apartment exit")
    phone.interior_control("use")
    time.sleep(.5)
    phone.record("travel-menu-"+data["scene"],data["scene"])
    phone.press(480,440)
    time.sleep(.65)
    phone.press(480,440)
    wait_for_state(phone,lambda s:s["scene"]=="commute",18)
    # Regression for touches while the entire exterior is being prepared.
    phone.press(430,322)
    time.sleep(.75)
    phone.press(430,322)


def mount(phone):
    for _ in range(16):
        gear=phone.state().get("gear",{})
        if gear.get("outfit")=="geared":
            break
        phone.press(480,632)
        time.sleep(2)
    else: raise RuntimeError("Ride did not finish loading or gear equip failed")
    if not gear.get("mounted"):
        phone.press(.94*960,.72*678)
        wait_for_state(phone,lambda s:s.get("gear",{}).get("mounted"),12)


def arrive(phone,yaw):
    data=phone.state()
    if not data.get("door") or distance(data["bike"],data["parking"])>=5:
        raise RuntimeError("Park at the destination first")
    destination=data["destination"]
    if data["gear"].get("mounted"):
        phone.press(.94*960,.72*678)
        wait_for_state(phone,lambda s:not s.get("gear",{}).get("mounted"),10)
        time.sleep(1.4)
    angle=math.radians(yaw or 0)
    calibrated=yaw is not None
    for _ in range(12):
        data=phone.state()
        ped=data["ped"];door=data["door"]
        dx,dz=door["x"]-ped["x"],door["z"]-ped["z"]
        length=math.hypot(dx,dz)
        if length<1.55:
            break
        sx=(dx*math.cos(angle)-dz*math.sin(angle))/length
        sy=(dx*math.sin(angle)+dz*math.cos(angle))/length
        duration=min(7000 if calibrated else 650,max(300,(length-.65)/1.62*1000))
        phone.press(.10*960+60*sx,.80*678+60*sy,duration)
        # Allow the ordinary five-second checkpoint to capture the end of
        # this walk before calculating another approach, not a mid-stride save.
        time.sleep(5.5)
        next_ped=phone.state()["ped"]
        mx,mz=next_ped["x"]-ped["x"],next_ped["z"]-ped["z"]
        if math.hypot(mx,mz)>.25:
            # Screen direction minus actual direction gives the current camera
            # yaw, including a follow camera just released by dismounting.
            angle=math.atan2(sy,sx)-math.atan2(mz,mx)
            calibrated=True
    else: raise RuntimeError("Door approach blocked; check the outside camera angle and foot position")
    phone.press(.94*960,.72*678)
    scene="warehouse" if destination=="warehouse" else "home"
    wait_for_state(phone,lambda s:s["scene"]==scene,16)
    time.sleep(1)
    phone.record("arrival-"+scene,scene)


def verify(output, require_return):
    def check(label):
        entry=json.loads((output/(label+".json")).read_text(encoding="utf-8"))
        if not entry.get("passed") or not (output/entry["screenshot"]).is_file():
            raise RuntimeError("Missing passing capture: "+label)
        return entry
    created=check("new-shop")
    apartment=created["state"]["apartment"]
    legs=[("warehouse",apartment,"home")]
    if require_return: legs.append((apartment,"warehouse","warehouse"))
    last=created["capturedAt"]
    for origin,destination,scene in legs:
        suffix=origin+"-to-"+destination
        start=check("mounted-"+suffix);park=check("parked-"+suffix);inside=check("arrival-"+scene)
        for e in [start,park,inside]:
            s=e["state"]
            if (e["capturedAt"]<=last or s["seed"]!=created["state"]["seed"] or
                s["slot"]!=created["state"]["slot"] or e["pid"]!=created["pid"]):
                raise RuntimeError("Checkpoints are not one continuous playthrough")
            last=e["capturedAt"]
        a,b=start["state"],park["state"]
        if (a.get("origin")!=origin or b.get("destination")!=destination or not a["gear"]["mounted"]
                or not b["gear"]["mounted"] or distance(a["bike"],b["bike"])<4 or b["speed"]>.05
                or distance(b["bike"],b["parking"])>=5 or inside["state"]["scene"]!=scene):
            raise RuntimeError("Ride or door checkpoint failed: "+suffix)
    print("Verified new-shop creation, mounted movement, parking and entry on "+str(len(legs))+" leg(s). Inspect the screenshots for rendering.")


def main():
    parser=argparse.ArgumentParser(description=__doc__,formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--serial",default=os.environ.get("ANDROID_SERIAL"))
    parser.add_argument("--port",type=int,default=os.environ.get("ANDROID_ADB_SERVER_PORT") or os.environ.get("ADB_PORT"),
                        help="ADB server TCP port")
    parser.add_argument("--slot",type=int,choices=(1,2,3),default=1)
    parser.add_argument("--output",type=Path,default=ROOT/"output/mobile/town-journey")
    parser.add_argument("--viewport",nargs=4,type=int,metavar=("X","Y","W","H"),
                        help="physical inset viewport; default is the full landscape screenshot")
    commands=parser.add_subparsers(dest="action",required=True)
    status=commands.add_parser("status")
    status.add_argument("--file",type=Path,help="inspect an existing local test save without a device")
    tap=commands.add_parser("tap")
    tap.add_argument("x",type=float);tap.add_argument("y",type=float)
    tap.add_argument("--hold",type=int,default=0,help="milliseconds")
    capture=commands.add_parser("record")
    capture.add_argument("label",type=lambda s:s if re.fullmatch("[a-z0-9-]+",s) else parser.error("Invalid label"))
    capture.add_argument("--expect",choices=("warehouse","commute","home"))
    new=commands.add_parser("new",help="from title, create a production new game using the normal setup screens")
    new.add_argument("--seed",type=int,default=52)
    new.add_argument("--replace-test-slot",action="store_true")
    travel=commands.add_parser("ride")
    travel.add_argument("--timeout",type=int,default=240)
    commands.add_parser("departure",help="walk to the shop entrance and confirm a weekday outing")
    commands.add_parser("mount",help="wait for loading, equip using the visible gear button, and mount")
    door=commands.add_parser("arrive",help="dismount in destination parking, walk to its door and enter")
    door.add_argument("--yaw",type=float,help="optional initial outside camera yaw in degrees; otherwise measure on foot")
    validate=commands.add_parser("verify",help="verify ordered saved checkpoints and screenshot presence without a device")
    validate.add_argument("--require-return",action="store_true")
    watch=commands.add_parser("monitor",help="watch a manual ride without injecting any input; stop on apartment/warehouse arrival")
    watch.add_argument("--until",choices=("home","warehouse"),default="home")
    watch.add_argument("--timeout",type=int,default=900)
    watch.add_argument("--interval",type=float,default=2)
    watch.add_argument("--apk-report",type=Path,help="compare the installed APK SHA256 and version to this build report")
    args=parser.parse_args()
    os.chdir(ROOT)
    if args.action=="verify":
        return verify(args.output,args.require_return)
    if args.action=="status" and args.file:
        print(json.dumps(summary(inspect_save(args.file.read_bytes())),indent=2))
        return
    phone=Phone(args)
    if args.action=="status":
        print(json.dumps(summary(phone.state()),indent=2))
    elif args.action=="record":
        phone.record(args.label,args.expect)
    else:
        with JourneyLease(phone):
            if args.action=="monitor":
                if not 1<=args.interval<=60 or args.timeout<=0: parser.error("Use an interval of 1-60 s and a positive timeout")
                from android_town_monitor import monitor
                monitor(phone,args.until,args.timeout,args.interval,args.apk_report)
            elif args.action=="tap":
                phone.press(args.x,args.y,args.hold)
            elif args.action=="new":
                if not 1<=args.seed<=2147483646: parser.error("Seed out of range")
                new_shop(phone,args.seed,args.replace_test_slot)
            elif args.action=="departure":
                departure(phone)
            elif args.action=="mount":
                mount(phone)
            elif args.action=="arrive":
                arrive(phone,args.yaw)
            elif args.action=="ride":
                state=phone.state();validate_drive_state(state)
                suffix=state["origin"]+"-to-"+state["destination"]
                phone.record("mounted-"+suffix,"commute")
                ride(phone,args.timeout)
                phone.record("parked-"+suffix,"commute")

if __name__=="__main__":
    main()
