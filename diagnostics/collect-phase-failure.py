import concurrent.futures,json,os,pathlib,re,subprocess,time
out=pathlib.Path('/tmp/loupe-xcode27-crashes');out.mkdir(exist_ok=True)
device=os.environ['DEVICE'];host=os.environ['HOST']
def command(name,args,timeout=20):
    start=time.time()
    with (out/(name+'.log')).open('w') as stream:
        stream.write(f'started={start}\n');stream.flush()
        try:
            result=subprocess.run(args,stdout=stream,stderr=stream,timeout=timeout)
            stream.write(f'\ncode={result.returncode} finished={time.time()}\n')
        except Exception as error:stream.write(f'\nerror={error!r} finished={time.time()}\n')
base=pathlib.Path.home()/'Library/Developer/CoreSimulator/Devices'/device/'data/Containers/Data/Application'
pids=set()
for path in base.glob('*/tmp/loupe-touch-server-probe.log'):
    match=re.search(r'pid=(\d+)',path.read_text())
    if match:pids.add(match[1])
with concurrent.futures.ThreadPoolExecutor() as pool:
    work=[pool.submit(command,'app-'+pid,['/usr/bin/sudo','/usr/bin/sample',pid,'2','10','-file',str(out/('app-'+pid+'-stack.txt'))],55) for pid in pids]
    work+=[pool.submit(command,'processes',['/bin/ps','-axo','pid,ppid,pcpu,rss,comm']),pool.submit(command,'memory',['/usr/bin/vm_stat']),pool.submit(command,'status',['/usr/bin/curl','--max-time','3','--silent','--show-error','-w',' status=%{http_code} connect=%{time_connect} first=%{time_starttransfer} total=%{time_total}',host+'/status'],8),pool.submit(command,'app-unified',['/usr/bin/log','show','--last','2m','--style','compact','--predicate','process == "LoupeExample"'],25)]
    for future in work:future.result()
