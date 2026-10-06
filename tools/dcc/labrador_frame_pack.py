"""Arrange actual Blender Run PNGs into readable sheets and a frame-only ZIP.

This packages the rendered poses without changing or synthesizing their content.
Run with the workspace Python runtime that includes Pillow.
"""
import argparse
import hashlib
import json
import math
import zipfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def font(size):
    path = Path('/System/Library/Fonts/AppleSDGothicNeo.ttc')
    return ImageFont.truetype(str(path), size) if path.exists() else ImageFont.load_default(size=size)


def sheet(base, rows, target, columns, width, title):
    image_height = round(width * 854 / 1280)
    cell_height = image_height + 40
    header = 64
    canvas = Image.new('RGB', (columns * width, header + math.ceil(len(rows) / columns) * cell_height), '#f4f1eb')
    draw = ImageDraw.Draw(canvas)
    draw.text((20, 14), title, font=font(25), fill='#39342c')
    for i, row in enumerate(rows):
        x = i % columns * width
        y = header + i // columns * cell_height
        draw.text((x + 12, y + 7), f"{row['index']:02d}  ·  {row['time_seconds']:.3f}s", font=font(21), fill='#494339')
        with Image.open(base / row['file']) as source:
            thumbnail = ImageOps.contain(source.convert('RGB'), (width, image_height), Image.Resampling.LANCZOS)
        canvas.paste(thumbnail, (x + (width - thumbnail.width) // 2, y + 40))
    canvas.save(target)


def package(base):
    render_receipt = base / 'run-frames-render.json'
    receipt = json.loads(render_receipt.read_text())
    rows = receipt['frames']
    assert len(rows) == 42 and receipt['fps'] == 60
    assert [r['index'] for r in rows] == list(range(1, 43))
    for i, row in enumerate(rows):
        path = (base / row['file']).resolve()
        assert path.is_relative_to(base.resolve()) and path.suffix == '.png'
        assert digest(path) == row['sha256']
        assert abs(row['time_seconds'] - i / 60) < 1e-8
        with Image.open(path) as image:
            assert image.size == (1280, 854)
    output = base / 'export'
    output.mkdir(exist_ok=True)
    overview = output / 'Labrador_Run_42Frames_Overview.png'
    sheet(base, rows, overview, 6, 320, '달리기 42프레임 / Run · 60fps · 0.70s')
    details = output / 'sheets'
    details.mkdir(exist_ok=True)
    pages = []
    for i in range(7):
        target = details / f'Run_Frames_{i * 6 + 1:02d}-{i * 6 + 6:02d}.png'
        sheet(base, rows[i * 6:(i + 1) * 6], target, 2, 640,
              f'달리기 / Run · {i * 6 + 1:02d}–{i * 6 + 6:02d} · 60fps')
        pages.append(target)
    readme = output / 'README_Frames.md'
    readme.write_text(
        '# 래브라도 달리기 프레임 / Labrador Run frames\n\n'
        '수정된 실제 3D 모션 한 주기를 60fps로 렌더한 PNG42장입니다. '
        'Run_001.png부터 Run_042.png까지 순서대로 보세요. 각 이미지1280×854이며 '
        '시간은0초부터0.683333초입니다. 0.70초의 frame43은 첫 자세와 같아 제외했습니다.\n\n'
        'The42 PNGs render one actual corrected3D Run cycle at60fps. '
        'Read Run_001.png through Run_042.png in order; each is1280×854. '
        'Times cover0–0.683333s; repeated closure frame43 at0.70s is omitted.\n\n'
        '모델 / Model: Labrador Dog by kenchoo / all of life, CC BY4.0.\n'
        'https://sketchfab.com/3d-models/labrador-dog-1f56cfbab07e4fe49b5d9e521c82073a\n\n'
        '원본 움직임 참고 / Motion source: Lei Han et al., Figshare dog motion capture.\n'
        'https://doi.org/10.6084/m9.figshare.24968946.v1\n\n'
        '프레임은 고정된 옆 시점·조명으로 렌더했습니다. 애니메이션 수정·Unity 적용은 없습니다.\n'
        'Fixed side camera and lighting; the animation and Unity installation are unchanged.\n',
        encoding='utf-8')
    archive = output / 'Labrador_Run_42Frames.zip'
    with zipfile.ZipFile(archive, 'w', compression=zipfile.ZIP_STORED) as bundle:
        for row in rows:
            bundle.write(base / row['file'], 'frames/' + Path(row['file']).name)
        bundle.write(readme, readme.name)
        bundle.write(render_receipt, render_receipt.name)
    with zipfile.ZipFile(archive) as bundle:
        assert bundle.testzip() is None
        assert len([n for n in bundle.namelist() if n.endswith('.png')]) == 42
        for row in rows:
            assert hashlib.sha256(bundle.read('frames/' + Path(row['file']).name)).hexdigest() == row['sha256']
    result = {'result': 'Passed', 'frame_count': 42, 'PNG_resolution': [1280, 854],
              'source_sha256': receipt['source_sha256'], 'render_receipt_sha256': digest(render_receipt),
              'overview': str(overview.relative_to(base)), 'detail_pages': [str(p.relative_to(base)) for p in pages],
              'zip': str(archive.relative_to(base)), 'ZIP_frame_count': 42, 'ZIP_all_frame_hashes_match': True,
              'artifacts': {str(p.relative_to(base)): {'sha256': digest(p), 'bytes': p.stat().st_size}
                            for p in [overview, *pages, readme, archive]},
              'scope_ko': '실제 프레임을 순서대로 모아보기와 ZIP으로 묶었습니다. 이미지42장은 최종 요청 산출물로 보존합니다.',
              'scope_en': 'Actual frames arranged in order and packaged; all42 frame images are retained as requested deliverables.'}
    (base / 'run-frames-package.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'frames': 42, 'overview': str(overview), 'ZIP': str(archive), 'sheets': 7}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--base', type=Path, required=True)
    package(parser.parse_args().base.resolve())
