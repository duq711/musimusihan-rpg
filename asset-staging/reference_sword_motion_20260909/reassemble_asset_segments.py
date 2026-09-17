#!/usr/bin/env python3
"""Reconstitute an unchanged Windows asset from verified local and sent bytes."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import tempfile


def digest(data):
    return hashlib.sha256(data).hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def unique(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, 'Duplicate JSON key: ' + key)
        result[key] = value
    return result


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8-sig'), object_pairs_hook=unique)


def assemble(args):
    recipe = read_json(args.recipe)
    known = read_json(args.known)
    require(recipe['format'] == 'codex_byte_segments_v1', 'Unexpected recipe format')
    require(recipe['sha256'] == args.expected_sha256, 'Recipe is not the expected Windows artifact')
    require(type(recipe['size_bytes']) is int and 0 < recipe['size_bytes'] <= 512 * 1024 * 1024, 'Invalid asset size')
    require(isinstance(recipe['segments'], list) and 0 < len(recipe['segments']) <= 100000, 'Invalid segment list')
    require(not args.output.exists() and not args.output.is_symlink(), 'Output exists; preserve it and choose a new path')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    cursor = 0
    hasher = hashlib.sha256()
    reused = 0
    entries = []
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=args.output.parent, prefix='.asset-', delete=False) as target:
            temporary = Path(target.name)
            for item in recipe['segments']:
                require(type(item['offset']) is int and item['offset'] == cursor, 'Segment gap or overlap')
                length = item['length']
                require(type(length) is int and 0 < length <= recipe['size_bytes'] - cursor, 'Invalid segment length')
                sha = item['sha256']
                require(isinstance(sha, str) and re.fullmatch('[0-9a-f]{64}', sha), 'Invalid segment digest')
                if item['source'] == 'known':
                    require(sha in known, 'Mac does not have declared known bytes: ' + sha)
                    location = known[sha]
                    require(location['length'] == length, 'Known blob size differs')
                    source = Path(location['path'])
                    require(source.is_file() and not source.is_symlink(), 'Known source is not a regular file')
                    with source.open('rb') as stream:
                        stream.seek(location['offset'])
                        data = stream.read(length)
                    reused += length
                    provenance = {'path': str(source), 'offset': location['offset']}
                else:
                    require(item['source'] == 'payload', 'Unexpected segment source')
                    require(item['path'] == 'blobs/' + sha + '.bin', 'Invalid payload path')
                    source = args.recipe.parent / item['path']
                    require(source.resolve().is_relative_to(args.recipe.parent.resolve()), 'Payload escapes delivery')
                    require(source.is_file() and not source.is_symlink(), 'Payload is not a regular file')
                    require(source.stat().st_size == length, 'Payload length differs')
                    data = source.read_bytes()
                    provenance = {'path': str(source), 'offset': 0}
                require(len(data) == length and digest(data) == sha, 'Segment bytes failed SHA-256 verification')
                target.write(data)
                hasher.update(data)
                entries.append({'offset': cursor, 'length': length, 'sha256': sha, 'source': item['source'], 'provenance': provenance})
                cursor += length
            require(cursor == recipe['size_bytes'], 'Segments do not reach the exact end of the asset')
            require(hasher.hexdigest() == args.expected_sha256, 'Reassembled asset is not byte-identical to Windows final')
            target.flush()
            os.fsync(target.fileno())
        os.link(temporary, args.output)
        receipt = {'status': 'pass', 'asset': str(args.output.resolve()), 'size_bytes': cursor, 'sha256': hasher.hexdigest(),
                   'reused_known_bytes': reused, 'received_payload_bytes': cursor - reused, 'recipe_sha256': digest(args.recipe.read_bytes()),
                   'source_files_modified': False, 'segments': entries,
                   'scope': 'Byte identity only; geometry and production playback are checked separately.'}
        receipt_path = args.output.with_suffix(args.output.suffix + '.receipt.json')
        with receipt_path.open('x', encoding='utf-8') as stream:
            json.dump(receipt, stream, indent=2)
            stream.write('\n')
        print(json.dumps({k: v for k, v in receipt.items() if k != 'segments'}))
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--recipe', type=Path, required=True)
    parser.add_argument('--known', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--expected-sha256', required=True)
    assemble(parser.parse_args())
