import json,os,pathlib,re,subprocess,time,urllib.request
out=pathlib.Path('/tmp/loupe-touch-gui-trace-ab');out.mkdir()
cli=str(pathlib.Path('.build/debug/loupe').resolve());device=os.environ['LOUPE_DEVICE'];results=[]
cases=[('input','selector',True),('button','selector',True),('input','selector',False),('button','selector',False),('input','coordinates',True),('button','coordinates',True),('input','coordinates',False)]
for index,(target,selection,trace) in enumerate(cases):
    name=f'{index:02d}-{target}-{selection}-trace{int(trace)}';start=time.monotonic();record={'name':name}
    try:
        launch=subprocess.run([cli,'app','launch','--device',device,'--bundle-id','dev.loupe.example','--inject','--env','LOUPE_EXAMPLE_ROUTE=touch','--timeout','30'],capture_output=True,text=True,timeout=70)
        (out/(name+'-launch.log')).write_text(launch.stdout+launch.stderr)
        assert launch.returncode==0,launch.stderr
        host=re.search(r'^loupe host: (.+)$',launch.stdout,re.M)[1]
        def snapshot(label):
            with urllib.request.urlopen(host+'/snapshot',timeout=5) as response:data=json.load(response)
            (out/(name+'-'+label+'.json')).write_text(json.dumps(data))
            return data
        before=snapshot('before');testid='touch.input' if target=='input' else 'touch.uikit.button'
        node=next(n for n in before['nodes'].values() if n.get('testID')==testid);f=node['frame']
        args=[cli,'act','tap','--host',host,'--udid',device]
        if selection=='selector':args+=['--test-id',testid]
        else:args+=['--x',str(f['x']+f['width']/2),'--y',str(f['y']+f['height']/2)]
        if trace:args+=['--trace-dir',str(out/(name+'-trace'))]
        action=subprocess.run(args,capture_output=True,text=True,timeout=35 if trace else 15)
        (out/(name+'.log')).write_text(action.stdout+action.stderr)
        record['code']=action.returncode
        deadline=time.monotonic()+4
        while True:
            after=snapshot('after');field=next(n for n in after['nodes'].values() if n.get('testID')=='touch.input')
            statusid='touch.input.status' if target=='input' else 'touch.uikit.status'
            status=next(n.get('text') for n in after['nodes'].values() if n.get('testID')==statusid)
            record.update(status=status,first_responder=field.get('uikit',{}).get('isFirstResponder'))
            if (target=='input' and status.startswith('Input mode:')) or (target=='button' and status=='UIKit taps 1') or time.monotonic()>deadline:break
            time.sleep(0.05)
    except Exception as error:record['error']=repr(error)
    record['elapsed']=time.monotonic()-start;results.append(record);print(record,flush=True)
    (out/'results.json').write_text(json.dumps(results,indent=2))
