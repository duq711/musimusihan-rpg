"""Move an MP4's movie index before media without re-encoding samples.

Only self-contained, non-fragmented MP4 files with stco/co64 indexes are
supported. Unsupported layouts fail before writing a destination file.
"""
import argparse
import hashlib
import json
import struct
from pathlib import Path


def boxes(data, start=0, end=None):
    end = len(data) if end is None else end
    while start < end:
        if start + 8 > end:
            raise ValueError('Truncated MP4 box header')
        size, kind = struct.unpack_from('>I4s', data, start)
        header = 8
        if size == 1:
            if start + 16 > end:
                raise ValueError('Truncated extended MP4 box header')
            size = struct.unpack_from('>Q', data, start + 8)[0]
            header = 16
        elif size == 0:
            size = end - start
        if size < header or start + size > end:
            raise ValueError('Invalid MP4 box size')
        yield start, size, kind, header
        start += size


def faststart(source, destination):
    source, destination = Path(source), Path(destination)
    data = source.read_bytes()
    atoms = list(boxes(data))
    movies = [a for a in atoms if a[2] == b'moov']
    media = [a for a in atoms if a[2] == b'mdat']
    if len(movies) != 1 or not media or atoms[0][2] != b'ftyp':
        raise ValueError('Expected one moov, ftyp first, and media data')
    if any(a[2] == b'moof' for a in atoms):
        raise ValueError('Fragmented MP4 is unsupported')
    movie = movies[0]
    if struct.unpack_from('>I', data, movie[0])[0] == 0:
        raise ValueError('A movie index with an implicit end size is unsupported')
    ordered = [atoms[0], movie] + [a for a in atoms[1:] if a != movie]
    new_offsets = {}
    position = 0
    for atom in ordered:
        new_offsets[atom[0]] = position
        position += atom[1]
    index = bytearray(data[movie[0]:movie[0] + movie[1]])
    tables = entries = 0

    def patch(start, end):
        nonlocal tables, entries
        for offset, size, kind, header in boxes(index, start, end):
            body = offset + header
            if kind in (b'moov', b'trak', b'mdia', b'minf', b'stbl'):
                patch(body, offset + size)
            elif kind in (b'cmov', b'mvex'):
                raise ValueError('Compressed or fragmented movie index unsupported')
            elif kind in (b'stco', b'co64'):
                width, fmt = (4, '>I') if kind == b'stco' else (8, '>Q')
                if body + 8 > offset + size:
                    raise ValueError('Truncated chunk-offset table')
                count = struct.unpack_from('>I', index, body + 4)[0]
                if body + 8 + count * width != offset + size:
                    raise ValueError('Invalid chunk-offset table length')
                for i in range(count):
                    entry = body + 8 + i * width
                    old = struct.unpack_from(fmt, index, entry)[0]
                    owner = next((a for a in media if a[0] + a[3] <= old < a[0] + a[1]), None)
                    if owner is None:
                        raise ValueError('Chunk offset points outside local media')
                    new = old + new_offsets[owner[0]] - owner[0]
                    if new >= 1 << (8 * width):
                        raise ValueError('Chunk offset overflow')
                    struct.pack_into(fmt, index, entry, new)
                tables += 1
                entries += count

    patch(movie[3], movie[1])
    if not tables or not entries:
        raise ValueError('No indexed media chunks found')
    result = b''.join(bytes(index) if a == movie else data[a[0]:a[0] + a[1]] for a in ordered)
    if len(result) != len(data):
        raise ValueError('Remux changed file size')
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_name(destination.name + '.faststart.tmp')
    temporary.write_bytes(result)
    temporary.replace(destination)
    return {
        'file': destination.name, 'bytes': len(result),
        'sha256': hashlib.sha256(result).hexdigest(),
        'moov_before_mdat': new_offsets[movie[0]] < min(new_offsets[a[0]] for a in media),
        'chunk_tables': tables, 'chunk_entries': entries,
        'media_payload_sha256': [hashlib.sha256(data[a[0] + a[3]:a[0] + a[1]]).hexdigest() for a in media],
        'media_payload_unchanged': True,
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    print(json.dumps(faststart(args.source, args.destination), indent=2))
