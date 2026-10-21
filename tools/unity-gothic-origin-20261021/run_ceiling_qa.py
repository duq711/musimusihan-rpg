#!/usr/bin/env python3
"""Compare authored sidedness against the old shader in the same isolated Metal player."""
import argparse,json,os,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('app',type=Path);p.add_argument('output',type=Path);p.add_argument('--variant',choices=['before','after','both'],default='both');a=p.parse_args()
app=a.app.resolve();out=a.output.resolve();out.mkdir(parents=True,exist_ok=True)
for name,legacy in [('before',True),('after',False)]:
    if a.variant!='both' and a.variant!=name:continue
    folder=out/name;folder.mkdir(exist_ok=True)
    env=dict(os.environ,ORIGIN_QA_DIR=str(folder),ORIGIN_QA_WIDTH='2940',ORIGIN_QA_HEIGHT='1846',ORIGIN_QA_LEGACY_SIDEDNESS='1' if legacy else '0')
    args=[str(app/'Contents/MacOS/Musimusihan Gothic Origin'),'-batchmode','-force-metal','-screen-width','2940','-screen-height','1846','-originQa','-originCeilingQa','-originVisibilityQa','-logFile',str(folder/'player.log')]
    with (folder/'bootstrap.log').open('w') as stream:
        run=subprocess.run(args,env=env,stdout=stream,stderr=subprocess.STDOUT,timeout=900)
    if not (folder/'summary.json').is_file():
        raise SystemExit(f'{name}: player exited with code {run.returncode} without a complete QA summary; inspect {folder}')
    summary=json.loads((folder/'summary.json').read_text())
    print(json.dumps(dict(variant=name,exitCode=run.returncode,checks=summary['checkCount'],failure=summary['failure'],ceilingViews=(summary.get('ceilings') or {}).get('views'),ceilingVoidViews=(summary.get('ceilings') or {}).get('viewsWithVoid')),ensure_ascii=False),flush=True)
    if run.returncode or summary['failure']:raise SystemExit(1)
