"""Run the gameplay plan's mobile stages on one explicitly selected physical phone."""
import argparse, json, re, subprocess, time
from datetime import datetime, timezone
from pathlib import Path
from live_device import ROOT, PACKAGE, REMOTE, adb, put

def run(serial, output, selected, overrides=()):
    output.mkdir(parents=True,exist_ok=False)
    plan=json.loads((ROOT/'tools/gameplay_smoke_plan.json').read_text(encoding='utf-8-sig'))
    stages=[s for s in plan['stages'] if (s['mobile'] or s['id']=='delivery-routes')
            and (not selected or s['id'] in selected)]
    if selected and set(selected)-{s['id'] for s in stages}: raise ValueError('Unknown Android stage')
    summary={'status':'RUNNING','platform':'physical Android','serial':serial,'stages':[],
             'diagnostic':bool(overrides),'testOverrides':[str(p) for p in overrides]}
    def save(): (output/'summary.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
    save()
    put(serial,ROOT/'tools/live_device_main.lua','main.lua')
    overlay_entries=[]
    for index,path in enumerate(overrides):
        relative=path.resolve().relative_to(ROOT)
        assert relative.parts[0]=='src' and 'tests' in relative.parts and relative.suffix=='.lua'
        module='.'.join(relative.with_suffix('').parts)
        name='live-overlay-'+str(index)+'.lua'
        put(serial,path,name)
        overlay_entries.append("{module='%s',file='%s'}"%(module,name))
    for index,stage in enumerate(stages):
        start=time.monotonic();identifier='a'+str(time.time_ns())
        config=output/(stage['id']+'.config.lua')
        config.write_text("return {version=1,mode='smoke',id='%s',focus='%s',seed=%s,diagnostic=%s,overrides={%s}}"%
                          (identifier,stage['focus'],stage.get('seed','nil'),
                           'true' if overrides else 'false',','.join(overlay_entries)),encoding='utf-8')
        adb(serial,'shell','am','force-stop',PACKAGE)
        put(serial,config,'live-device-config.lua')
        adb(serial,'shell','am','start','-W','-n',PACKAGE+'/org.love2d.android.GameActivity')
        print('START '+stage['id'],flush=True)
        report='';timed_out=False;process_exited=False;device_unavailable=False
        render_resume_requested=False
        while time.monotonic()-start<stage['timeoutSeconds']*2:
            result=subprocess.run(['adb','-s',serial,'exec-out','run-as',PACKAGE,'cat',
                                   REMOTE+'/live-'+identifier+'.rpt'],capture_output=True,timeout=30)
            if result.returncode==0:
                device_unavailable=False
                report=result.stdout.decode('utf-8','replace')
            if '\nSMOKE_OK' in report or '\nFAIL ' in report: break
            if '\nCHECKS_COMPLETE\n' in report and not render_resume_requested:
                # A USB reconnect can leave Android's USB settings screen in
                # front. Once the checks are complete, foreground the game so
                # Love can draw the required final frames and flush SMOKE_OK.
                resumed=subprocess.run(['adb','-s',serial,'shell','am','start','-W','-n',
                                        PACKAGE+'/org.love2d.android.GameActivity'],
                                       capture_output=True,timeout=30)
                render_resume_requested=True
                if resumed.returncode==0: device_unavailable=False
                else: device_unavailable=True
            process=subprocess.run(['adb','-s',serial,'shell','pidof',PACKAGE],
                                   capture_output=True,timeout=30)
            if not process.stdout.strip():
                if process.returncode!=0:
                    # A brief USB/ADB transport drop can make pidof appear empty
                    # while the game keeps running. Keep polling so the report
                    # can arrive after the device reconnects.
                    device_unavailable=True
                    time.sleep(2)
                    continue
                # Completion may have been flushed between the report read and
                # the process query. Re-read before classifying an early exit.
                final=subprocess.run(['adb','-s',serial,'exec-out','run-as',PACKAGE,'cat',
                                      REMOTE+'/live-'+identifier+'.rpt'],capture_output=True,timeout=30)
                if final.returncode!=0:
                    device_unavailable=True
                    time.sleep(2)
                    continue
                device_unavailable=False
                report=final.stdout.decode('utf-8','replace')
                if '\nSMOKE_OK' in report or '\nFAIL ' in report: break
                process_exited=True
                try:
                    exit_info=adb(serial,'shell','dumpsys','activity','exit-info',PACKAGE)
                except (subprocess.CalledProcessError,subprocess.TimeoutExpired) as exc:
                    detail=getattr(exc,'stderr',None)
                    if isinstance(detail,bytes): detail=detail.decode('utf-8','replace')
                    exit_info='Could not collect Android exit info; device may be disconnected.\n'+str(detail or exc)
                (output/(stage['id']+'.exit-info.txt')).write_text(exit_info,encoding='utf-8')
                break
            time.sleep(2)
        else: timed_out=True
        (output/(stage['id']+'.rpt')).write_text(report,encoding='utf-8')
        lines=report.splitlines();checks=[v[5:] for v in lines if v.startswith('PASS ')]
        required={c for f in plan['features'] if stage['id'] in f['stages'] for c in f['checks']}
        problems=[v for v in lines if v.startswith(('FAIL ','SMOKE_REPORT_ERROR'))]
        if timed_out: problems.append('Device stage timed out')
        if process_exited: problems.append('Android process exited before completion; see exit-info report')
        if device_unavailable: problems.append('Android device disconnected or became unreachable; reconnect and rerun this stage')
        if len(checks)!=len(set(checks)): problems.append('Duplicate checks')
        if len(checks)<stage['minChecks']: problems.append('Insufficient checks')
        for marker in ('CHECKS_COMPLETE','PASS render_three_frames','SMOKE_OK'):
            if lines.count(marker)!=1: problems.append('Missing/repeated '+marker)
        expected='SMOKE_CONFIG focus=%s mobile=1 seed=%s identity=the-picture-shop-test-device-%s'%(
            stage['focus'],stage.get('seed','none'),identifier)
        if lines.count(expected)!=1: problems.append('Wrong device test configuration')
        problems.extend('Missing feature: '+c for c in sorted(required-set(checks)))
        status='FAIL' if problems else 'PASS'
        summary['stages'].append({'id':stage['id'],'status':status,'checks':len(checks),
                                 'seconds':round(time.monotonic()-start,2),'problems':problems})
        save();print(status+' '+stage['id']+': '+str(len(checks))+' checks',flush=True)
        if problems:
            print('\n'.join(problems),flush=True)
            summary['status']='FAIL';save();return 1
    summary['status']='DIAGNOSTIC_PASS' if overrides else 'PARTIAL' if selected else 'PASS'
    summary['completedAt']=datetime.now(timezone.utc).isoformat();save();return 0

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial',required=True);parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--stage',action='append',default=[])
    parser.add_argument('--override-test',type=Path,action='append',default=[],
                        help='Diagnostic only: load an updated test without rebuilding the APK; cannot produce an acceptance PASS')
    args=parser.parse_args()
    raise SystemExit(run(args.serial,args.output,args.stage,args.override_test))
