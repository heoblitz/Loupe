import json,subprocess,time
for iteration in range(160):
    result={'time':time.time()}
    for key,args in [('memory',['/usr/sbin/sysctl','hw.memsize','hw.ncpu','vm.swapusage']),('vm',['/usr/bin/vm_stat']),('processes',['/bin/ps','-axo','pid,ppid,pcpu,rss,command'])]:
        try:
            text=subprocess.check_output(args,text=True,timeout=5)
            if key=='processes':
                rows=[line.split(None,4) for line in text.splitlines()[1:]]
                rows=[row for row in rows if len(row)==5]
                result['top_rss']=sorted(rows,key=lambda row:float(row[3]),reverse=True)[:12]
                result['top_cpu']=sorted(rows,key=lambda row:float(row[2]),reverse=True)[:8]
            else:result[key]=text
        except Exception as error:result[key]=repr(error)
    print(json.dumps(result),flush=True)
    time.sleep(15)
