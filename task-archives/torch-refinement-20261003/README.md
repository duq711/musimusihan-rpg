# 횃불 소등·점화음 수정 / Torch refinement — 2026-10-03

빌드 26을 기존 Dock 게임에 설치했습니다. 끄면 횃불과 횃불 손이 즉시 사라지고 주머니에 넣는 모션을 재생하지 않습니다. 대장간 금속 타격음은 직접 제작한 짧은 부싯돌 마찰음으로 교체했습니다. 3초 점화, 취소, 일시정지, F2 복원과 다른 무기의 손 자세를 유지했습니다. 자동 검사 3,582개와 실제 Metal 소등 화면 검토, 로컬 서명 및 설치된 DLL 해시 검증을 통과했습니다.

로컬 작업 커밋은 `d54c8c3fa683d54c9ad1fff9f6e7fe06c1bce545`이며 필요한 기준 커밋은 `bb3411f16636deb8b5301dec1dbc0bc041b57e42`입니다. [task-bundle.json](task-bundle.json)에 해당 작업 20개 파일의 완전한 패치, 직접 제작한 WAV 원본의 base64 자료, 파일 해시와 비식별 검증 근거를 저장했습니다. 기준 파일에 패치를 적용한 결과를 모두 재검증했고 GitHub에서 다시 읽은 자료가 로컬과 일치함을 확인했습니다.

**로컬 GitHub 인증 문제로 전체 Unity 이전 브랜치의 push는 완료하지 못했습니다.** 이 게시물은 이번 변경의 복원 가능한 자료이며 독립 실행 가능한 전체 Unity 프로젝트 또는 전체 브랜치 동기화 완료를 뜻하지 않습니다. 필요한 기존 Unity 파일·에셋과 원본 제작 자료는 로컬에 보존합니다. 자동 검증은 음소거했으며 스피커 청취나 새 성능 측정을 인증하지 않습니다.

Build 26 is installed at the existing Dock target. Extinguish immediately hides the torch and its hand without pocket stowing. A dedicated authored dry flint scrape replaces the smithing clang. Three-second ignition, cancellation, pause, F2 restoration and other equipment hands remain. All 3,582 checks, direct Metal extinguish review, signing and installed assembly verification passed.

The bundle contains the complete 20-file task patch, the authored WAV payload, file hashes and sanitized validation. Patch roundtrip and exact GitHub read-back were verified. **Local Git authentication blocked the full migration-branch push.** This archive is a restorable task delta requiring the existing Unity baseline/assets; it is neither a standalone project nor proof of full-branch synchronization. Speaker output stayed muted; no new performance benchmark is claimed.

복원 / Restore from the required baseline checkout after downloading `task-bundle.json`:

```python
import base64, gzip, hashlib, json, pathlib, subprocess
data = json.loads(pathlib.Path("task-bundle.json").read_text())
patch = gzip.decompress(base64.b64decode(data["patch_gzip_base64"]))
assert hashlib.sha256(patch).hexdigest() == data["patch_sha256"]
subprocess.run(["git", "apply", "--check", "-"], input=patch, check=True)
subprocess.run(["git", "apply", "-"], input=patch, check=True)
# Replace the patch's Git LFS pointer with the included authored PCM.
for path, media in data["lfs_payloads"].items():
    payload = base64.b64decode(media["content"])
    assert hashlib.sha256(payload).hexdigest() == media["sha256"]
    pathlib.Path(path).write_bytes(payload)
```

Bundle SHA-256: `08af8c1257c45b83feb199f9b440bea537539b82d82b10a07b924ef86c6a033b`.
