#!/usr/bin/env python3
"""Prepare the minimal native build project; preserve production sources and metadata."""
from pathlib import Path
import argparse, hashlib, json, shutil, subprocess, tarfile
ROOT=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('project',type=Path);a=p.parse_args();project=a.project.resolve()
assert (project/'ProjectSettings/ProjectVersion.txt').is_file(), 'Create the isolated 6000.6.3f1 project with Unity CLI first.'
def copy(source,destination):
    destination.parent.mkdir(parents=True,exist_ok=True)
    if destination.exists() and source.read_bytes()==destination.read_bytes():return
    subprocess.run(['cp','-c',str(source),str(destination)],check=True)
def tree(source,destination):
    for f in source.rglob('*'):
        if f.is_file():copy(f,destination/f.relative_to(source))
tree(ROOT/'unity-game/Assets/GothicOrigin',project/'Assets/GothicOrigin')
tree(ROOT/'unity-game/Assets/StreamingAssets/GothicDungeon',project/'Assets/StreamingAssets/GothicDungeon')
records=[]
for monster in ['folded_penitent','hollow_bell_keeper','knot_pilgrim']:
    source=ROOT/f'assets/3d/gothic_monster_trio_20261019/reference_match_v2/{monster}/{monster}.glb'
    destination=project/f'Assets/StreamingAssets/GothicActors/{monster}.glb';copy(source,destination)
    digest=hashlib.sha256(source.read_bytes()).hexdigest();assert digest==hashlib.sha256(destination.read_bytes()).hexdigest()
    records.append(dict(source=str(source.relative_to(ROOT)),sha256=digest,bytes=source.stat().st_size))
fonts=ROOT/'unity-game/Assets/RPG/Generated/Fonts'
for name in ['ExpeditionSansKR.ttf','SanctuarySerifKR400.ttf','SanctuaryCinzel400.ttf']:
    copy(fonts/name,project/'Assets/GothicOrigin/SourceFonts'/name)
for f in fonts.glob('OFL-*.txt'):copy(f,project/'Assets/StreamingAssets/Licenses'/f.name)
package=next((project/'Library/PackageCache').glob('com.unity.ugui*/Package Resources/TMP Essential Resources.unitypackage'))
# Noninteractive essential-resource extraction, preserving package paths and GUID metadata.
with tarfile.open(package,'r:gz') as tar:
    members={m.name:m for m in tar.getmembers()}
    for pathname in [n for n in members if n.endswith('/pathname')]:
        base=pathname.rsplit('/',1)[0];relative=tar.extractfile(pathname).read().decode().strip();target=project/relative
        assert target.resolve().is_relative_to(project/'Assets'),relative
        for entry,suffix in [('asset',''),('asset.meta','.meta')]:
            member=members.get(base+'/'+entry)
            if member and member.isfile():
                file=Path(str(target)+suffix);file.parent.mkdir(parents=True,exist_ok=True)
                if not file.exists():file.write_bytes(tar.extractfile(member).read())
(project/'origin-source-receipt.json').write_text(json.dumps(dict(actors=records,mapManifestSha256=hashlib.sha256((ROOT/'unity-game/Assets/StreamingAssets/GothicDungeon/manifest.json').read_bytes()).hexdigest()),indent=2)+'\n')
print('Prepared real Unity sources, original35-room package, actors and licensed fonts at',project)
