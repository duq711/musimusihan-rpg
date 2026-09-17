#!/usr/bin/env python3
"""Build and verify the Windows animation handoff without modifying game files."""
from pathlib import Path, PurePosixPath
import hashlib
import json
import re
import zipfile

ROOT = Path(__file__).resolve().parents[2]
FOLDER = ROOT / "exports/Sword_Shield_FirstPerson_Windows_2026-09-08"
ARCHIVE = FOLDER.with_suffix(".zip")


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def main():
    assert (FOLDER / "START_HERE_KO.txt").is_file()
    assert list((FOLDER / "Animations").glob("*.blend"))
    assert len(list((FOLDER / "Animations").glob("*.glb"))) == 6
    source_record = json.loads((FOLDER / "Verification/copied_sources.json").read_text())
    for record in source_record["source_files"]:
        assert digest(ROOT / record["source_file"]) == record["sha256"], record
        assert digest(FOLDER / record["package_file"]) == record["sha256"], record
    records = []
    seen = set()
    for path in sorted(FOLDER.rglob("*")):
        assert not path.is_symlink(), path
        if not path.is_file() or path.name == "files_sha256.json":
            continue
        relative = path.relative_to(FOLDER).as_posix()
        assert relative.lower() not in seen, relative
        seen.add(relative.lower())
        for part in PurePosixPath(relative).parts:
            assert not re.search(r'[<>:"\\|?*\x00-\x1f]', part), relative
            assert not part.endswith((".", " ")), relative
            assert not re.fullmatch(r"(?i)(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\..*)?", part), relative
        assert len(relative) < 180, relative
        assert not any(x in relative for x in [".DS_Store", "__MACOSX", ".sb-", ".import", ".godot", "__pycache__"]), relative
        records.append({"file": relative, "size_bytes": path.stat().st_size, "sha256": digest(path)})
    manifest = FOLDER / "Verification/files_sha256.json"
    manifest.write_text(json.dumps({"files": records, "count": len(records)}, indent=2) + "\n")
    with zipfile.ZipFile(ARCHIVE, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as z:
        for path in sorted(FOLDER.rglob("*")):
            if path.is_file():
                z.write(path, FOLDER.name + "/" + path.relative_to(FOLDER).as_posix())
    with zipfile.ZipFile(ARCHIVE) as z:
        assert z.testzip() is None
        names = z.namelist()
        assert len(names) == len(set(names)) == len(records) + 1
        for record in records:
            data = z.read(FOLDER.name + "/" + record["file"])
            assert len(data) == record["size_bytes"]
            assert hashlib.sha256(data).hexdigest() == record["sha256"]
    report = {"archive": ARCHIVE.name, "size_bytes": ARCHIVE.stat().st_size,
              "sha256": digest(ARCHIVE), "entries": len(records) + 1,
              "zip_crc_pass": True, "all_archived_file_hashes_match": True,
              "original_sources_unchanged": True, "windows_filename_checks_pass": True}
    ARCHIVE.with_suffix(".verification.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report))


if __name__ == "__main__":
    main()
