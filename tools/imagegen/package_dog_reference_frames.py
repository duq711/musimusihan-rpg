#!/usr/bin/env python3
"""Package built-in imagegen frames and corresponding actual references without editing pixels."""
import argparse
import hashlib
import json
import shutil
import zipfile
from pathlib import Path
from PIL import Image


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    args = parser.parse_args()
    root = args.root.resolve()
    catalog = json.loads((root / 'prompts.json').read_text())
    review = json.loads((root / 'visual-review.json').read_text())
    export = root / 'export'
    sources = export / 'sources'
    sources.mkdir(parents=True, exist_ok=True)
    frames = []
    expected = list(range(1, catalog['frame_count'] + 1))
    assert [f['frame'] for f in catalog['frames']] == expected
    for planned in catalog['frames']:
        n = planned['frame']
        receipt = json.loads((root / 'generation' / f'frame{n:03d}.json').read_text())
        filename = planned['filename']
        path = export / 'frames' / filename
        assert receipt['frame'] == n
        assert 'built-in' in receipt['mode']
        assert receipt['selected_image'] == 'export/frames/' + filename
        assert receipt['source_frame'] == planned['source_frame']
        assert receipt['prompt'] and receipt['referenced_image_paths'][0] == planned['referenced_image_paths'][0]
        assert path.read_bytes() == Path(receipt['default_image_path']).read_bytes()
        assert digest(path) == receipt['sha256']
        assert path.stat().st_size == receipt['bytes']
        with Image.open(path) as im:
            assert im.format == 'PNG'
            resolution = list(im.size)
            assert resolution == receipt['resolution']
            im.verify()
        source = root / planned['source_reference']
        original = Path(planned['referenced_image_paths'][0])
        assert source.read_bytes() == original.read_bytes()
        target = sources / source.name
        if target.exists():
            assert target.read_bytes() == source.read_bytes()
        else:
            shutil.copyfile(source, target)
        frames.append({**{k: planned[k] for k in ('frame','filename','source_frame','source_time_seconds','time_seconds','duration_seconds','cycle_phase','pose_cue')},
            'file': 'frames/' + filename, 'reference_file': 'sources/' + target.name,
            'sha256': digest(path), 'reference_sha256': digest(target), 'bytes': path.stat().st_size,
            'resolution': resolution, 'exact_default_source_copy': True,
            'prompt': receipt['prompt'], 'reference_roles': receipt['reference_roles']})
    assert len(set(f['sha256'] for f in frames)) == len(frames), 'Duplicate image bytes'
    archive = f'dog-run-actual-reference-{len(frames)}-frames-20261007.zip'
    manifest = {'schema': catalog['schema'], 'frame_count': len(frames), 'source_url': catalog['source_url'],
        'tool': catalog['tool'], 'archive': archive, 'default_preview_fps': 16,
        'original_capture_fps': None, 'source_timing_cycle_seconds': 56 / 24,
        'frames': frames, 'visual_review': review,
        'file_validation': {'png_count':len(frames),'reference_count':len(frames),
            'exact_default_copies':len(frames),'exact_reference_copies':len(frames),
            'distinct_image_hashes':len(frames),'pixels_resized_or_edited':False}}
    write_json(export / 'manifest.json', manifest)
    shutil.copyfile(Path(__file__).with_name('dog_reference_frames_gallery.html'), export / 'index.html')
    readme = ('# 개 달리기 실제 자세 참고 시퀀스 / Dog-run reference sequence\n\n'
        '내장 imagegen으로 만든 개별 PNG 16장과 대응하는 실제 영상 프레임입니다. 원본 바이트를 보존했고 리사이즈나 픽셀 편집을 하지 않았습니다.\n'
        'Sixteen individual built-in imagegen PNGs with corresponding actual video references. Original output bytes are preserved, with no resizing or pixel edits.\n\n'
        'frames/는 생성 이미지, sources/는 실제 자세 참고입니다. manifest.json에 시간·해시·프롬프트·검사 한계가 있습니다.\n'
        'frames/ contains generated images; sources/ contains pose references. See manifest.json for timing, hashes, prompts and review limits.\n\n'
        'HTTP 서버에서 index.html을 열면 프레임을 비교·재생할 수 있습니다. 기본 16fps는 미리보기 설정입니다. 원본 시간 옵션은 이미 느린 영상의 24fps 샘플 시간을 따릅니다. 실제 촬영 FPS는 확인되지 않았습니다.\n'
        'Serve this folder over HTTP to compare and play frames. The default 16fps is a preview setting. Source timing follows the already slowed 24fps video; its original capture FPS is unknown.\n\n'
        + review['summary_ko'] + '\n' + review['summary_en'] + '\n\nSource: ' + catalog['source_url'] + '\n')
    (export / 'README.md').write_text(readme, encoding='utf-8')
    members = [export / 'manifest.json', export / 'README.md', export / 'index.html']
    members += [export / f['file'] for f in frames]
    members += [export / f['reference_file'] for f in frames]
    with zipfile.ZipFile(export / archive, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for path in members:
            z.write(path, path.relative_to(export).as_posix())
    with zipfile.ZipFile(export / archive) as z:
        assert z.testzip() is None
        assert len(z.namelist()) == len(members)
        for path in members:
            assert z.read(path.relative_to(export).as_posix()) == path.read_bytes()
    validation = {'png_count':len(frames),'source_reference_count':len(frames),
        'receipt_checks':len(frames),'zip_member_byte_checks':len(members),
        'zip_bytes':(export / archive).stat().st_size,'zip_sha256':digest(export / archive),
        'resolutions':sorted({tuple(f['resolution']) for f in frames}),
        'output_png_bytes':sum(f['bytes'] for f in frames), 'file_integrity_verified':True,
        'visual_review_file':'visual-review.json','archive':'export/'+archive}
    write_json(root / 'validation-summary.json', validation)
    print(json.dumps(validation, ensure_ascii=False))


if __name__ == '__main__':
    main()
