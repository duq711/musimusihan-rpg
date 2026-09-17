"""Run only this task's Blender helper hidden and record actual execution."""
from pathlib import Path
from datetime import datetime,timezone
import subprocess,sys,json,time,platform,hashlib
ROOT=Path(__file__).resolve().parent
EXE=Path('C:/Users/duq71/Documents/Codex/2026-09-08/new-chat/work/tools/blender-5.2.1-windows-x64/blender.exe')
script=Path(sys.argv[1]).resolve();out=Path(sys.argv[2]).resolve();out.mkdir(parents=True,exist_ok=True)
argv=[str(EXE),'--background','--factory-startup','--disable-autoexec','--python-exit-code','1','--python',str(script),'--',*sys.argv[3:]]
report={'execution_os':platform.system(),'hostname':platform.node(),'blender_executable':str(EXE),'command_argv':argv,'working_directory':str(ROOT),'started_at_utc':datetime.now(timezone.utc).isoformat()}
tick=time.monotonic()
with (out/'execution.log').open('w',encoding='utf-8') as log:
    result=subprocess.run(argv,cwd=ROOT,stdin=subprocess.DEVNULL,stdout=log,stderr=subprocess.STDOUT,creationflags=subprocess.CREATE_NO_WINDOW)
report.update(completed_at_utc=datetime.now(timezone.utc).isoformat(),exit_code=result.returncode,elapsed_seconds=time.monotonic()-tick)
(out/'execution.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps(report));print((out/'execution.log').read_text(encoding='utf-8')[-4500:])
raise SystemExit(result.returncode)
