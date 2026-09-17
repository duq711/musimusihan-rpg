"""Repair the truncated record count hiding existing supplied texture UIDs.

The exact Godot revision reads only the count declared in uid_cache.bin:
https://github.com/godotengine/godot/blob/5b4e0cb0f/core/io/resource_uid.cpp#L283
Only the four-byte count changes. All existing records are validated/preserved;
no new UID is generated and no registry reset or editor process control occurs.
"""
from pathlib import Path
import hashlib,json,os,re,struct,tempfile

STAGE=Path(__file__).resolve().parents[1]
PROJECT=STAGE.parents[1]/'godot-game'
CACHE=PROJECT/'.godot/uid_cache.bin'
AUDIT=STAGE/'audit'
SOURCE='https://github.com/godotengine/godot/blob/5b4e0cb0f/core/io/resource_uid.cpp#L283'

def sha(data):return hashlib.sha256(data).hexdigest()
def decode(data):
    declared=struct.unpack_from('<I',data)[0];offset=4;records=[]
    while offset<len(data):
        assert offset+12<=len(data),'Truncated UID-cache record header'
        uid,size=struct.unpack_from('<QI',data,offset);offset+=12
        assert 0<size<16384 and offset+size<=len(data),'Invalid existing UID-cache record'
        path=data[offset:offset+size].decode('utf-8');offset+=size
        assert path.startswith('res://') and uid<0x8000000000000000
        records.append((uid,path))
    assert declared<=len(records),'Header claims nonexistent records'
    return declared,records

def uid_number(text):
    assert text.startswith('uid://')
    value=0
    for ch in text[6:]:value=value*34+(ord(ch)-ord('a')if ch.islower()else ord(ch)-ord('0')+25)
    return value&0x7fffffffffffffff

def current_uid(path):
    file=PROJECT/path.removeprefix('res://');assert file.is_file(),f'Missing mapped resource: {path}'
    if Path(str(file)+'.import').exists():text=Path(str(file)+'.import').read_text()
    elif Path(str(file)+'.uid').exists():return uid_number(Path(str(file)+'.uid').read_text().strip())
    else:text=file.read_text()
    matches=re.findall(r'\buid="(uid://[a-y0-8]+)"',text)
    assert matches,f'Resource has no existing UID: {path}'
    return uid_number(matches[0])

line=next(v for v in (AUDIT/'import_uid_registration_plan.log').read_text().splitlines() if v.startswith('SUPPLIED TEXTURE UID REGISTRATION: '))
plan=json.loads(line.split(': ',1)[1]);assert not plan['problems']
before=CACHE.read_bytes();count,records=decode(before);registered=dict(records[:count]);physical=dict(records)
for uid_text,path in plan['missing'].items():
    uid=int(uid_text)
    assert path.startswith('res://assets/3d/player/') and path.endswith('.png')
    assert current_uid(path)==uid and physical.get(uid)==path,f'Required UID missing or mismatched: {path}'
for uid,path in records[count:]:
    assert current_uid(path)==uid,f'Trailing record does not match current resource: {path}'
    assert uid not in registered or registered[uid]==path,f'Conflicting existing UID: {uid}/{path}'
    registered[uid]=path
report={'engine_source':SOURCE,'old_declared_record_count':count,'actual_record_count':len(records),'old_cache_sha256':sha(before),'restored_required_texture_mappings':plan['missing'],'trailing_records':[{'uid':uid,'path':path}for uid,path in records[count:]],'all_existing_record_bytes_preserved':True,'new_uids_generated':0}
after=struct.pack('<I',len(records))+before[4:]
if after!=before:
    backup=AUDIT/'uid_cache_before_registration.bin'
    if backup.exists() and backup.read_bytes()!=before:backup=AUDIT/('uid_cache_before_registration_'+sha(before)[:12]+'.bin')
    if backup.exists():assert backup.read_bytes()==before,'Refusing to overwrite a distinct backup'
    else:backup.write_bytes(before)
    fd,tmp=tempfile.mkstemp(prefix='supplied-uid-count-',suffix='.tmp',dir=CACHE.parent)
    try:
        with os.fdopen(fd,'wb')as stream:stream.write(after);stream.flush();os.fsync(stream.fileno())
        assert CACHE.read_bytes()==before,'UID cache changed concurrently; retry from a fresh audit'
        os.chmod(tmp,CACHE.stat().st_mode);os.replace(tmp,CACHE)
    finally:
        if os.path.exists(tmp):os.unlink(tmp)
    report['backup']=str(backup)
saved=CACHE.read_bytes();new_count,new_records=decode(saved)
assert saved==after and saved[4:]==before[4:] and new_records==records and new_count==len(records)
report.update(new_cache_sha256=sha(saved),changed_byte_offsets=[i for i,(a,b)in enumerate(zip(before,saved))if a!=b],passed=True)
(AUDIT/'import_uid_repair.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
