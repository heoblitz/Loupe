import json,subprocess,time
for iteration in range(120):
    result={'time':time.time()}
    for key,args in [('memory',['/usr/sbin/sysctl','hw.memsize','hw.ncpu','vm.swapusage','vm.loadavg']),('vm',['/usr/bin/vm_stat'])]:
        try: result[key]=subprocess.check_output(args,text=True,timeout=5)
        except Exception as error: result[key]=repr(error)
    print(json.dumps(result),flush=True)
    time.sleep(15)
