import json,os,pathlib,subprocess,time,urllib.request
out=pathlib.Path('/tmp/loupe-touch-gui-route-ab');out.mkdir()
host=os.environ['LOUPE_PROBE_HOST'];device=os.environ['LOUPE_DEVICE'];results=[]
def snapshot(name):
    with urllib.request.urlopen(host+'/snapshot',timeout=5) as response:data=json.load(response)
    (out/(name+'.json')).write_text(json.dumps(data));return data
flag=subprocess.run(['xcrun','simctl','spawn',device,'notifyutil','-g','com.apple.coredevice.dtuhidd.active'],capture_output=True,text=True,timeout=15)
(out/'dtuhidd-state.log').write_text(flag.stdout+flag.stderr)
for mode in ['normal','legacy','normal','reset','external','normal','legacy']:
    name=f'{len(results):02d}-{mode}';start=time.monotonic();record={'name':name}
    try:
        before=snapshot(name+'-before');button=next(n for n in before['nodes'].values() if n.get('testID')=='touch.uikit.button');f=button['frame'];size=before['screen']['size']
        args=['/tmp/loupe-route-'+mode,'act','tap','--x',str(f['x']+f['width']/2),'--y',str(f['y']+f['height']/2),'--width',str(size['width']),'--height',str(size['height']),'--udid',device]
        result=subprocess.run(args,capture_output=True,text=True,timeout=15)
        (out/(name+'.log')).write_text(result.stdout+result.stderr);record['code']=result.returncode
        status=lambda d:next(n.get('text') for n in d['nodes'].values() if n.get('testID')=='touch.uikit.status')
        record['before']=status(before);deadline=time.monotonic()+4
        while True:
            after=snapshot(name+'-after');record['after']=status(after)
            if record['after']!=record['before'] or time.monotonic()>deadline:break
            time.sleep(0.05)
    except Exception as error:record['error']=repr(error)
    record['elapsed']=time.monotonic()-start;results.append(record);print(record,flush=True);(out/'results.json').write_text(json.dumps(results,indent=2))
with (out/'guest-hid.log').open('w') as stream:
    try:subprocess.run(['xcrun','simctl','spawn',device,'log','show','--last','3m','--style','compact','--predicate','process == "backboardd" OR eventMessage CONTAINS "DTUHIDD" OR eventMessage CONTAINS "SimHIDVirtual"'],stdout=stream,stderr=stream,timeout=20)
    except Exception as error:stream.write(repr(error))
