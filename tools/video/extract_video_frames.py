#!/usr/bin/env python3
"""Decode each selected source video frame once, preserving its native size and PTS.

Requires FFmpeg (pass --ffmpeg, or install the imageio-ffmpeg Python package).
The frame range is zero-based and end-exclusive; no frame-rate filter is used.
"""
import argparse
import hashlib
import json
import re
import shutil
import subprocess
from pathlib import Path


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--ffmpeg')
    parser.add_argument('--start-frame', type=int, default=0)
    parser.add_argument('--end-frame', type=int)
    parser.add_argument('--source-url', default='')
    parser.add_argument('--source-title', default='')
    parser.add_argument('--archive-filename', default='video-frames.zip')
    parser.add_argument('--initial-frame', type=int, default=1)
    args = parser.parse_args()
    if args.start_frame < 0 or (args.end_frame is not None and args.end_frame <= args.start_frame):
        parser.error('Invalid zero-based, end-exclusive frame range')
    ffmpeg = args.ffmpeg or shutil.which('ffmpeg')
    if not ffmpeg:
        import imageio_ffmpeg
        ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    frames_dir = args.output / 'frames'
    if frames_dir.exists():
        raise FileExistsError('Refusing to overwrite a frame sequence: ' + str(frames_dir))
    frames_dir.mkdir(parents=True)
    selection = 'gte(n\\,%d)' % args.start_frame
    if args.end_frame is not None:
        selection += '*lt(n\\,%d)' % args.end_frame
    command = [ffmpeg, '-nostdin', '-hide_banner', '-i', str(args.source), '-map', '0:v:0', '-an',
               '-vf', 'showinfo,select=' + selection, '-fps_mode', 'passthrough',
               '-pix_fmt', 'rgb24', '-compression_level', '6', str(frames_dir / 'Frame_%06d.png')]
    result = subprocess.run(command, capture_output=True, check=True)
    log = result.stderr.decode(errors='replace')
    config = re.search(r'config in time_base: (\d+)/(\d+), frame_rate: (\d+)/(\d+)', log)
    if not config:
        raise RuntimeError('Could not read original frame time base')
    tb_n, tb_d, fps_n, fps_d = map(int, config.groups())
    source_frames = [(int(n), int(pts)) for n, pts in re.findall(r'\bn:\s*(\d+)\s+pts:\s*(-?\d+)\s+pts_time:', log)]
    assert source_frames and [n for n, _ in source_frames] == list(range(len(source_frames)))
    selected = [(n, pts) for n, pts in source_frames
                if n >= args.start_frame and (args.end_frame is None or n < args.end_frame)]
    paths = sorted(frames_dir.glob('Frame_*.png'))
    assert len(paths) == len(selected), (len(paths), len(selected))
    from PIL import Image
    records = []
    dimensions = set()
    for index, (path, (source_n, pts)) in enumerate(zip(paths, selected), start=1):
        with Image.open(path) as picture:
            picture.verify()
        with Image.open(path) as picture:
            dimensions.add(picture.size)
            assert picture.format == 'PNG' and picture.mode == 'RGB'
        records.append({'frame': index, 'filename': path.name, 'source_frame': source_n,
                        'source_pts': pts, 'timestamp_seconds': pts * tb_n / tb_d,
                        'bytes': path.stat().st_size, 'sha256': digest(path)})
    assert len(dimensions) == 1
    width, height = dimensions.pop()
    manifest = {'schema_version': 1, 'title_ko': '실제 영상 · 개 달리기 프레임',
                'source_url': args.source_url, 'source_title': args.source_title,
                'source_filename': args.source.name, 'source_sha256': digest(args.source),
                'source_fps': fps_n / fps_d, 'source_frame_rate_rational': [fps_n, fps_d],
                'source_time_base_rational': [tb_n, tb_d], 'source_decoded_frame_count': len(source_frames),
                'selected_source_range_zero_based_end_exclusive': [args.start_frame, args.end_frame],
                'width': width, 'height': height, 'default_preview_rate_fps': 8,
                'initial_frame': min(max(1, args.initial_frame), len(records)),
                'archive_filename': args.archive_filename, 'archive_available': True,
                'method_ko': '각 원본 프레임을 순서대로 한 번씩 디코드. 보간·프레임 복제·크기 변경·AI 생성 없음.',
                'method_en': 'Decode each selected source frame once in order. No interpolation, duplication, resizing or AI generation.',
                'frames': records}
    (args.output / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    report = {'source_decoded_frames': len(source_frames), 'selected_frames': len(records),
              'pngs_checked': len(paths), 'width': width, 'height': height,
              'source_fps': manifest['source_fps'], 'source_pts_strictly_increasing': all(
                  a['source_pts'] < b['source_pts'] for a, b in zip(records, records[1:])),
              'source_indices_contiguous': [r['source_frame'] for r in records] == list(range(
                  records[0]['source_frame'], records[-1]['source_frame'] + 1)),
              'exact_duplicate_png_count': len(records) - len({r['sha256'] for r in records}),
              'source_sha256': manifest['source_sha256'], 'selected_png_bytes': sum(r['bytes'] for r in records),
              'ffmpeg_version': subprocess.run([ffmpeg, '-version'], capture_output=True, check=True).stdout.decode().splitlines()[0],
              'command': ['ffmpeg' if part == ffmpeg else part for part in command]}
    assert report['source_pts_strictly_increasing'] and report['source_indices_contiguous']
    (args.output.parent / 'extraction-summary.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(report, ensure_ascii=False))


if __name__ == '__main__':
    main()
