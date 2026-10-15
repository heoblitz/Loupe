import json,os,pathlib,subprocess,time,urllib.request
out=pathlib.Path('/tmp/loupe-touch-gui-ab');out.mkdir()
host=os.environ['LOUPE_PROBE_HOST'];device=os.environ['LOUPE_DEVICE'];results=[]
def snapshot(name):
    with urllib.request.urlopen(host+'/snapshot',timeout=5) as response:data=json.load(response)
    (out/(name+'.json')).write_text(json.dumps(data))
    return data
def run_phase(phase):
    for mode in ['normal','skip-register','legacy','normal']:
        name=f'{len(results):02d}-{phase}-{mode}';before=snapshot(name+'-before')
        button=next(n for n in before['nodes'].values() if n.get('testID')=='touch.uikit.button')
        frame=button['frame'];size=before['screen']['size'];start=time.monotonic()
        args=['/tmp/loupe-gui-'+mode,'act','tap','--x',str(frame['x']+frame['width']/2),'--y',str(frame['y']+frame['height']/2),'--width',str(size['width']),'--height',str(size['height']),'--udid',device]
        try:
            result=subprocess.run(args,capture_output=True,text=True,timeout=15)
            (out/(name+'.log')).write_text(result.stdout+result.stderr)
            after=snapshot(name+'-after')
            status=lambda d:next(n.get('text') for n in d['nodes'].values() if n.get('testID')=='touch.uikit.status')
            record={'name':name,'elapsed':time.monotonic()-start,'code':result.returncode,'before':status(before),'after':status(after)}
        except Exception as error:record={'name':name,'error':str(error),'elapsed':time.monotonic()-start}
        results.append(record);print(record,flush=True);(out/'results.json').write_text(json.dumps(results,indent=2))
run_phase('headless')
frontend=os.environ['DEVELOPER_DIR'].removesuffix('/Developer')+'/Applications/DeviceHub.app'
subprocess.run(['/usr/bin/open','-a',frontend,'devices://device/open?id='+device],check=True,timeout=15)
# Observe the newly attached frontend without changing an input deadline.
subprocess.run(['/bin/ps','-axo','pid,command'],stdout=(out/'frontend-processes.txt').open('w'),timeout=15)
run_phase('attached')
