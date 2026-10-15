import json,os,pathlib,subprocess,time,concurrent.futures
out=pathlib.Path('/tmp/loupe-context-ab');out.mkdir()
device=os.environ['LOUPE_DEVICE']
try:
    inventory=subprocess.check_output(['/bin/ps','-axo','pid,command'],text=True,timeout=30)
    services=[r.split()[0] for r in inventory.splitlines() if 'CoreSimulatorService.xpc/Contents/MacOS' in r]
except Exception as error:services=[]
results=[]
def sample(pid,name):
    with (out/(name+'-sample.log')).open('w') as stream:
        try:subprocess.run(['/usr/bin/sudo','/usr/bin/sample',str(pid),'2','10','-file',str(out/(name+'-stack.txt'))],stdout=stream,stderr=stream,timeout=55)
        except Exception as error:stream.write(str(error))
for index in range(12):
    if sum(r.get('timeout',False) for r in results) >= 2: break
    for mode in (['baseline','async'] if index%2==0 else ['async','baseline']):
        name=f'{index:02d}-{mode}';begin=time.monotonic()
        with (out/(name+'.log')).open('w') as stream:
            args=['/tmp/loupe-context-'+mode,'act','tap','--x','20','--y','20','--width','402','--height','874','--udid',device]
            process=subprocess.Popen(args,stdout=stream,stderr=stream)
            try:
                code=process.wait(timeout=15);results.append({'name':name,'elapsed':time.monotonic()-begin,'code':code})
            except subprocess.TimeoutExpired:
                results.append({'name':name,'elapsed':time.monotonic()-begin,'pid':process.pid,'timeout':True})
                with concurrent.futures.ThreadPoolExecutor() as pool:
                    futures=[pool.submit(sample,process.pid,name+'-host')]+[pool.submit(sample,pid,name+'-service') for pid in services[:1]]
                    for future in futures:future.result()
                process.kill();process.wait(timeout=5)
        (out/'results.json').write_text(json.dumps(results,indent=2))
        print(results[-1],flush=True)
