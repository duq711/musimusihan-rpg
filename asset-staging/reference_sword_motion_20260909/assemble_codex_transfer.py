#!/usr/bin/env python3
"""Assemble real ordered base64 chunks, verify a ZIP, and extract to a new folder.

Inputs are beside this script in transfer_incoming/<name>_0000.b64, etc.
Chunks split ONE base64 stream; separately padded binary chunks are rejected.
The verified ZIP remains in transfer_incoming/<name>.zip. Complete file hashes
are written to <output>/__codex_transfer_receipt.json; stdout is a JSON summary.
"""

import argparse
import base64
import hashlib
import json
import os
import re
import stat
import sys
import tempfile
import zipfile
from pathlib import Path, PureWindowsPath


MAX_CHUNKS = 100000
MAX_CHUNK_CHARS = 12000
MAX_ZIP_BYTES = 512 * 1024 * 1024
MAX_MEMBERS = 10000
MAX_FILE_BYTES = 1024 * 1024 * 1024
MAX_UNCOMPRESSED_BYTES = 2 * 1024 * 1024 * 1024
RECEIPT_NAME = "__codex_transfer_receipt.json"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def assemble_zip(incoming, name, count, expected):
    archive_path = incoming / (name + ".zip")
    chunks = []
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(prefix=name + "-", suffix=".partial", dir=incoming, delete=False) as stream:
            temporary = Path(stream.name)
            pending, written, hasher = b"", 0, hashlib.sha256()
            for index in range(count):
                path = incoming / ("%s_%04d.b64" % (name, index))
                require(path.is_file() and not path.is_symlink(), "Missing regular transfer chunk: " + str(path))
                require(path.stat().st_size <= MAX_CHUNK_CHARS + 4, "Chunk exceeds 12000 base64 characters: " + path.name)
                raw = path.read_bytes()
                text = raw.strip(b"\r\n")
                require(0 < len(text) <= MAX_CHUNK_CHARS, "Empty or oversized chunk: " + path.name)
                require(re.fullmatch(rb"[A-Za-z0-9+/=]+", text) is not None, "Invalid characters in base64 chunk: " + path.name)
                chunks.append({"name": path.name, "base64_characters": len(text), "file_sha256": hashlib.sha256(raw).hexdigest()})
                pending += text
                # Keep the final quantum until all chunks have arrived. This
                # supports arbitrary text split points without accepting padding
                # in the middle of the transfer.
                ready = max(0, (len(pending) - 4) // 4 * 4)
                if ready:
                    prefix, pending = pending[:ready], pending[ready:]
                    require(b"=" not in prefix, "Padding before the end: chunks must split one base64 stream")
                    decoded = base64.b64decode(prefix, validate=True)
                    written += len(decoded)
                    require(written <= MAX_ZIP_BYTES, "Decoded ZIP exceeds 512 MiB")
                    hasher.update(decoded)
                    stream.write(decoded)
            decoded = base64.b64decode(pending, validate=True)
            written += len(decoded)
            require(0 < written <= MAX_ZIP_BYTES, "Decoded ZIP is empty or exceeds 512 MiB")
            hasher.update(decoded)
            stream.write(decoded)
            stream.flush()
            os.fsync(stream.fileno())
        actual = hasher.hexdigest()
        require(actual == expected, "ZIP SHA-256 mismatch: expected %s; received %s" % (expected, actual))
        if archive_path.exists() or archive_path.is_symlink():
            require(archive_path.is_file() and not archive_path.is_symlink() and digest(archive_path) == expected,
                    "Existing transfer ZIP differs; it will not be overwritten: " + str(archive_path))
        else:
            # Same-directory exclusive publication preserves existing files.
            os.link(temporary, archive_path)
        return archive_path, chunks, written
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def archive_members(archive):
    infos = archive.infolist()
    require(0 < len(infos) <= MAX_MEMBERS, "ZIP must contain between 1 and 10000 members")
    seen, files, prepared, total = set(), set(), [], 0
    for info in infos:
        raw = info.orig_filename
        require("\0" not in raw and raw == info.filename, "NUL or truncated ZIP member path")
        require(not (info.flag_bits & 1), "Encrypted ZIP entries are not accepted")
        relative = raw.replace("\\", "/")
        directory = info.is_dir() or relative.endswith("/")
        require(relative and not relative.startswith("/") and not PureWindowsPath(relative).drive,
                "Absolute or drive-prefixed ZIP path: " + repr(raw))
        parts = relative.rstrip("/").split("/")
        require(all(part and part not in {".", ".."} and ":" not in part and not part.endswith((" ", "."))
                    and not PureWindowsPath(part).is_reserved() for part in parts),
                "Unsafe ZIP path component: " + repr(raw))
        key = "/".join(parts).casefold()
        require(key not in seen, "Duplicate or case-colliding ZIP path: " + repr(raw))
        require(key != RECEIPT_NAME.casefold(), "Archive conflicts with the receiver's receipt filename")
        seen.add(key)
        mode = info.external_attr >> 16
        file_type = stat.S_IFMT(mode)
        require(not stat.S_ISLNK(mode), "ZIP symlink is forbidden: " + repr(raw))
        require(file_type in {0, stat.S_IFREG, stat.S_IFDIR}, "ZIP special file is forbidden: " + repr(raw))
        require(not (file_type == stat.S_IFDIR and not directory), "Directory mode without directory path: " + repr(raw))
        require(0 <= info.file_size <= MAX_FILE_BYTES, "ZIP member exceeds 1 GiB: " + repr(raw))
        require(not directory or info.file_size == 0, "ZIP directory contains unexpected file data: " + repr(raw))
        total += info.file_size
        require(total <= MAX_UNCOMPRESSED_BYTES, "ZIP uncompressed total exceeds 2 GiB")
        if not directory:
            files.add(key)
        prepared.append((info, parts, directory))
    require(files, "ZIP contains no regular files")
    for _info, parts, _directory in prepared:
        for end in range(1, len(parts)):
            require("/".join(parts[:end]).casefold() not in files, "ZIP file/directory hierarchy conflict")
    return prepared, total


def receive(args):
    require(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]{0,79}", args.name) is not None,
            "--name must be a plain ASCII slug, at most 80 characters")
    require(1 <= args.count <= MAX_CHUNKS, "--count must be between 1 and 100000")
    require(re.fullmatch(r"[0-9a-fA-F]{64}", args.sha256) is not None, "--sha256 must contain 64 hexadecimal characters")
    require(not args.output.exists() and not args.output.is_symlink(), "--output already exists; choose a new unique directory")
    output = args.output.resolve()
    incoming = Path(__file__).resolve().parent / "transfer_incoming"
    require(incoming.is_dir(), "transfer_incoming directory does not exist")
    expected = args.sha256.lower()
    archive_path, chunks, zip_bytes = assemble_zip(incoming, args.name, args.count, expected)
    with zipfile.ZipFile(archive_path) as archive:
        members, expected_total = archive_members(archive)
        # Do not create the destination until the complete archive has passed
        # path/type/size preflight. No archive-controlled permissions are applied.
        output.mkdir(parents=True, exist_ok=False)
        received, actual_total = [], 0
        for info, parts, directory in members:
            destination = output.joinpath(*parts)
            destination.resolve().relative_to(output)
            if directory:
                destination.mkdir(parents=True, exist_ok=True)
                continue
            destination.parent.mkdir(parents=True, exist_ok=True)
            written, hasher = 0, hashlib.sha256()
            with archive.open(info, "r") as source, destination.open("xb") as target:
                for block in iter(lambda: source.read(1024 * 1024), b""):
                    written += len(block)
                    actual_total += len(block)
                    require(written <= info.file_size and actual_total <= MAX_UNCOMPRESSED_BYTES,
                            "ZIP expanded beyond declared or allowed size")
                    hasher.update(block)
                    target.write(block)
            require(written == info.file_size, "Extracted member size differs: " + info.filename)
            # ZipExtFile checks each member CRC while being read to completion.
            received.append({"relative_path": "/".join(parts), "size_bytes": written, "sha256": hasher.hexdigest()})
        require(actual_total == expected_total, "Extracted byte total differs from ZIP metadata")
    require(digest(archive_path) == expected, "Verified ZIP changed during extraction")
    receipt_path = output / RECEIPT_NAME
    receipt = {"status": "pass", "transfer_name": args.name, "chunk_count": args.count,
               "archive": str(archive_path), "archive_sha256": expected, "archive_size_bytes": zip_bytes,
               "output": str(output), "file_count": len(received), "uncompressed_size_bytes": actual_total,
               "archive_crc_checked": True, "source_chunks_preserved": True, "chunks": chunks, "received_files": received,
               "scope": "Byte transport, ZIP integrity, and safe extraction only; file hashes do not establish Windows execution or motion quality."}
    with receipt_path.open("x", encoding="utf-8") as target:
        json.dump(receipt, target, ensure_ascii=False, indent=2)
        target.write("\n")
    return {"status": "pass", "archive": str(archive_path), "archive_sha256": expected,
            "output": str(output), "file_count": len(received), "receipt": str(receipt_path)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", required=True)
    parser.add_argument("--count", required=True, type=int)
    parser.add_argument("--sha256", required=True)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    try:
        result = receive(args)
    except Exception as error:
        print(json.dumps({"status": "fail", "error": "%s: %s" % (type(error).__name__, error),
                          "output": str(args.output), "note": "If extraction had begun, its new partial directory is retained; use a new output name."},
                         ensure_ascii=False))
        return 1
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
