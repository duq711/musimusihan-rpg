#!/usr/bin/python3
"""Launch only this isolated test project with its local execution base."""
from pathlib import Path
import datetime
import subprocess
import sys
import tempfile

project = Path(__file__).resolve().parent.parent
engine = Path('/Volumes/T7/UE 58/UE_5.8/Engine/Binaries/Mac')
mode = sys.argv[1] if len(sys.argv) > 1 else 'editor'
if mode not in ('editor', 'headless', 'pie-capture', 'build-map'):
    raise SystemExit('Unknown test mode')
binary = engine / ('UnrealEditor.app/Contents/MacOS/UnrealEditor' if mode in ('editor', 'pie-capture') else 'UnrealEditor-Cmd')
if not binary.is_file():
    raise SystemExit('T7 디스크의 언리얼 엔진을 찾지 못했습니다. 디스크 연결을 확인해주세요.')
base = project / 'RuntimeHost/Engine/Binaries/Mac'
if not base.is_dir():
    raise SystemExit('프로젝트의 분리 실행 폴더가 없습니다.')
# A temporary ASCII alias avoids inconsistent quoting between Mac BaseDir()
# and the engine's map URL parser. All resources stay in the project/engine.
alias = Path(tempfile.mkdtemp(prefix='ue_agent_test_'))
(alias / 'RuntimeHost').symlink_to(project / 'RuntimeHost', target_is_directory=True)
base_alias = alias / 'RuntimeHost/Engine/Binaries/Mac'
args = [str(binary), str(project / 'UE_Agent_Test.uproject'), '/Game/Maps/TestRoom', '-basedir=' + str(base_alias), '-nosplash']
if mode == 'headless':
    args += ['-game', '-AgentAutoTest', '-nullrhi']
elif mode == 'pie-capture':
    args += ['-AgentPIE', '-AgentAutoTest', '-AgentCapture', '-RenderOffscreen', '-MetalOffscreenOnly', '-windowed', '-ResX=1280', '-ResY=800']
elif mode == 'build-map':
    args += ['-run=AgentBuildMap', '-nullrhi']
if mode != 'editor':
    args += ['-unattended', '-skipminspeccheck', '-nosound', '-NoCrashDialog', '-stdout', '-FullStdOutLogOutput', '-ExecCmds=t.MaxFPS 60,Slate.bAllowThrottling 0,t.IdleWhenNotForeground 0']
stamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
evidence = project / 'Evidence'
evidence.mkdir(exist_ok=True)
log = evidence / f'{mode}_{stamp}_console.log'
args.append('-abslog=' + str(evidence / f'{mode}_{stamp}_engine.log'))
with log.open('w') as output:
    if mode == 'editor':
        subprocess.Popen(args, cwd=project, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
        print('언리얼 편집기를 시작했습니다. 테스트 맵이 열릴 때까지 기다려주세요.')
    else:
        result = subprocess.run(args, cwd=project, stdout=output, stderr=subprocess.STDOUT)
        print(str(log))
        raise SystemExit(result.returncode)
