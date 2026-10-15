import json,os,pathlib,re,shutil,signal,subprocess,sys,time
out=pathlib.Path('/tmp/loupe-touch-startup-ab');out.mkdir()
host=os.environ['HOST'];device=os.environ['DEVICE'];results=[]
def decoded(value):return value.decode(errors='replace') if isinstance(value,bytes) else(value or '')
for index in range(240):
    modes=['normal','no-appkit'] if index%2==0 else ['no-appkit','normal']
    for mode in modes:
        name=f'{index:03d}-{mode}';binary='/tmp/loupe-phase-sdk26-artifact/loupe'+('' if mode=='normal' else '-no-appkit')
        started=time.time();clock=time.monotonic();record={'name':name,'mode':mode,'started':started}
        args=[binary,'ui','snapshot','--host',host,'--output',str(out/(mode+'-latest.json'))]
        process=subprocess.Popen(args,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
        try:
            stdout,stderr=process.communicate(timeout=15);record.update(code=process.returncode,elapsed=time.monotonic()-clock)
            (out/(name+'.log')).write_text(f'started={started} pid={process.pid}\n'+stdout+stderr)
        except subprocess.TimeoutExpired as error:
            code=process.poll();record.update(timeout=True,poll=code,elapsed=time.monotonic()-clock)
            (out/(name+'.log')).write_text(f'started={started} pid={process.pid} poll={code} timeout_at={time.time()}\n'+decoded(error.stdout)+decoded(error.stderr))
            try:
                if code is None:
                    process.send_signal(signal.SIGSTOP)
                    with (out/(name+'-sample.log')).open('w') as stream:
                        try:subprocess.run(['/usr/bin/sudo','/usr/bin/sample',str(process.pid),'1','10','-file',str(out/(name+'-host-stack.txt'))],stdout=stream,stderr=stream,timeout=55)
                        except Exception as sample_error:stream.write(repr(sample_error))
            finally:
                if process.poll() is None:
                    process.send_signal(signal.SIGCONT);process.kill()
                try:process.wait(timeout=5)
                except subprocess.TimeoutExpired:pass
                process.stdout.close();process.stderr.close()
        results.append(record);(out/'results.json').write_text(json.dumps(results,indent=2))
        if record.get('timeout') or record.get('code')!=0 or index%20==0:print(record,flush=True)
    if sum(r.get('timeout') or r.get('code')!=0 for r in results)>=2:break
base=pathlib.Path.home()/'Library/Developer/CoreSimulator/Devices'/device/'data/Containers/Data/Application'
for path in base.glob('*/tmp/loupe-touch-server-probe.log'):shutil.copyfile(path,out/('server-'+path.parent.parent.name+'.log'))
for path in (pathlib.Path.home()/'Library/Logs/DiagnosticReports').glob('*'):
    if path.is_file() and time.time()-path.stat().st_mtime<600 and path.name.lower().startswith(('loupe','backboardd','springboard','coresimulator')):shutil.copyfile(path,out/path.name)
with (out/'status.log').open('w') as stream:
    try:subprocess.run(['/usr/bin/curl','--max-time','3','--silent','--show-error','-w',' status=%{http_code} total=%{time_total}',host+'/status'],stdout=stream,stderr=stream,timeout=8)
    except Exception as error:stream.write(repr(error))
failed=any(r.get('timeout') or r.get('code')!=0 for r in results)
print('A/B requests',len(results),'any failed',failed,flush=True)
sys.exit(1 if failed else 0)
