import json,os,pathlib,plistlib,re,subprocess,sys
assert os.environ.get('GITHUB_ACTIONS')=='true' and os.environ.get('RUNNER_ENVIRONMENT')=='github-hosted'
device,phase=sys.argv[1:];assert re.fullmatch(r'[0-9A-Fa-f-]{36}',device)
mode=os.environ['LOUPE_CI_WIDGET_PROFILE'];assert mode in ('stock','widgets')
labels=['com.apple.PosterBoard','com.apple.chronod','com.apple.liveactivitiesd','com.apple.navd']
# Widget-only labels and per-device store format reviewed from SimSlim commit
# 6518ba7eab1123d7e1d7797b0e05f51043b42a5b. No host-global services change.
if phase=='prepare':
 inventory=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','--json'],timeout=30))
 selected=[d for ds in inventory['devices'].values() for d in ds if d['udid']==device]
 assert len(selected)==1 and selected[0]['state']=='Shutdown',selected
 path=pathlib.Path('/private/var/tmp')/('com.apple.CoreSimulator.SimDevice.'+device)/'disabled.plist'
 entries=plistlib.loads(path.read_bytes()) if path.exists() else {}
 assert isinstance(entries,dict)
 before=dict(entries)
 if mode=='widgets':
  entries.update(dict.fromkeys(labels,True))
  path.parent.mkdir(mode=0o700,parents=True,exist_ok=True)
  temporary=path.with_suffix('.loupe-profile.tmp')
  temporary.write_bytes(plistlib.dumps(entries))
  temporary.chmod(0o644);temporary.replace(path)
 pathlib.Path('/tmp/loupe-touch-widget-profile.json').write_text(json.dumps({'mode':mode,'device':device,'before':before,'after':entries},indent=2))
else:
 result=subprocess.check_output(['xcrun','simctl','spawn',device,'launchctl','print-disabled','system'],text=True,timeout=10)
 pathlib.Path('/tmp/loupe-touch-widget-disabled.log').write_text(result)
 for label in labels:
  off=bool(re.search(r'"'+re.escape(label)+r'"\s*=>\s*true',result))
  assert off==(mode=='widgets'),(mode,label,result)
 print('Verified widget-only profile:',mode,flush=True)
