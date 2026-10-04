# 간단 제작 복원 자료 / Simple crafting restoration archive

구현 커밋 `3483e44dfcaa88b71fc1b0e9ecb30a588c556208`의 **26개 작업 파일만** `source.patch`에 저장했습니다. 정확한 Git LFS 화면 포인터와 실제 PNG의 base64 사본을 함께 보존합니다. 부모 커밋 `17cb4ed7e56e9546a002ad9c13b68cbc64452818`에 패치가 적용되는지 별도 임시 인덱스로 확인했습니다. 파일 해시는 `manifest.json`에 기록합니다.

This archive contains only the implementation commit's **26 task files**, its exact binary-capable Git format-patch, and actual PNG bytes as base64 alongside the Git LFS pointer. The patch was checked against its exact parent with an isolated temporary index. File hashes are recorded in the manifest.

기존 Unity 이전 파일·에셋과 부모 커밋이 필요합니다. 원격 main에는 기준이 없으므로 이전 작업 자료를 먼저 복원합니다. 전체 Unity 브랜치 또는 LFS 저장소의 동기화 완료를 뜻하지 않습니다. 원본 PNG는 기존 프로젝트 Migration 경로에 보존합니다.

The recorded Unity migration baseline and assets are required; remote main alone lacks this parent. Restore earlier task archives first. This package does not confirm full-branch or LFS synchronization. The original PNG remains at its project Migration path.

복원 / Restore from the repository root after obtaining the required baseline:

```sh
sh tools/git-project.sh apply --check task-archives/simple-crafting-20261004/source.patch
sh tools/git-project.sh apply task-archives/simple-crafting-20261004/source.patch
python3 - <<'PYRESTORE'
import pathlib, base64, hashlib, json
archive = pathlib.Path('task-archives/simple-crafting-20261004')
manifest = json.loads((archive / 'manifest.json').read_text())
for entry in manifest['binary_payloads']:
    data = base64.b64decode((archive / entry['archive_file']).read_bytes())
    assert hashlib.sha256(data).hexdigest() == entry['sha256']
    assert len(data) == entry['bytes']
    target = pathlib.Path(entry['path'])
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)
PYRESTORE
```

읽기용 보고서는 구현 이후의 공유 안내를 포함합니다. 정확한 구현 시점 문서는 패치 안에 있고, 별도 검증 JSON은 구현 커밋과 같은 바이트입니다.

The readable report includes the later publication note. The patch retains the exact implementation-time document; the readable validation JSON exactly matches the implementation commit.
