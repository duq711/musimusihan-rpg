#!/usr/bin/env python3
"""Register the internal native game and add one Dock shortcut without copying assets."""
import datetime
import json
import os
from pathlib import Path
import plistlib
import shutil
import secrets
import subprocess
import sys
import time
from urllib.parse import unquote, urlparse
try:
    from .mac_dock_preferences import DockCoreFoundation
except ImportError:
    from mac_dock_preferences import DockCoreFoundation


ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "unity-game/Builds/MusimusihanRPG.app"
LABEL = "무시무시한 RPG"


def run(*args, **kwargs):
    return subprocess.run(args, check=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, **kwargs)


def dock():
    data = run("/usr/bin/defaults", "export", "com.apple.dock", "-").stdout
    return data, plistlib.loads(data)


def tile_path(tile):
    url = tile.get("tile-data", {}).get("file-data", {}).get("_CFURLString", "")
    return Path(unquote(urlparse(url).path)).resolve() if url else None


def main():
    if sys.platform != "darwin":
        raise SystemExit("This installer runs on the project's Mac.")
    app = APP.resolve(strict=True)
    info_path = app / "Contents/Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    executable = app / "Contents/MacOS" / info["CFBundleExecutable"]
    if not executable.is_file() or not os.access(executable, os.X_OK):
        raise RuntimeError("The native player executable is missing or not executable.")
    backup = Path.home() / "Documents/RPG-Dock-Setup" / datetime.datetime.now(
        datetime.timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
    backup.mkdir(parents=True, mode=0o700)
    # Non-ASCII executable names produced an invalid outer resource seal on
    # this Mac. Keep the Korean display name and bundle ID/settings identity.
    renamed = not info["CFBundleExecutable"].isascii()
    display_changed = info.get("CFBundleDisplayName") != LABEL
    icon_name = info.get("CFBundleIconFile", "PlayerIcon.icns")
    if not icon_name.endswith(".icns"):
        icon_name += ".icns"
    icon = app / "Contents/Resources" / icon_name
    icon_bytes = 0
    if not icon.is_file():
        candidates = sorted((Path.home() / "Applications").glob(
            "RPG-Unity-*/Unity/Unity.app/Contents/Resources/UnityAppIcon.icns"))
        source = candidates[-1] if candidates else Path(
            "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericApplicationIcon.icns")
        shutil.copy2(source, icon)
        icon_bytes = icon.stat().st_size
    if renamed or display_changed:
        shutil.copy2(info_path, backup / "Info.plist.before")
        shutil.copy2(executable, backup / "game-executable.before")
        seal = app / "Contents/_CodeSignature/CodeResources"
        if seal.exists():
            shutil.copy2(seal, backup / "CodeResources.before")
        if renamed:
            replacement = app / "Contents/MacOS/MusimusihanRPG"
            if replacement.exists():
                # An incremental Unity rebuild can leave the previous
                # installer's executable alongside the new generated one.
                shutil.copy2(replacement, backup / "previous-installed-executable.before")
            executable.replace(replacement)
            info["CFBundleExecutable"] = replacement.name
        info["CFBundleDisplayName"] = LABEL
        info_path.write_bytes(plistlib.dumps(info, sort_keys=False))
    verify_args = ("/usr/bin/codesign", "--verify", "--deep", "--strict", str(app))
    verified = subprocess.run(verify_args, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if verified.returncode:
        run("/usr/bin/codesign", "--force", "--sign", "-", "--timestamp=none", str(app))
    run(*verify_args)
    shortcut = Path.home() / "Applications" / (LABEL + ".app")
    shortcut.parent.mkdir(exist_ok=True)
    if shortcut.exists() or shortcut.is_symlink():
        if not shortcut.is_symlink() or shortcut.resolve() != app:
            raise RuntimeError("Refusing to replace an unrelated application shortcut.")
    else:
        shortcut.symlink_to(app, target_is_directory=True)
    register = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    run(register, "-f", str(app))
    run(register, "-f", str(shortcut))
    before_bytes, before = dock()
    recovery = backup / "Dock.before.plist"
    recovery.write_bytes(before_bytes)
    recovery.chmod(0o600)
    original = before.get("persistent-apps", [])
    existing = [i for i, tile in enumerate(original) if tile_path(tile) == app]
    if len(existing) > 1:
        raise RuntimeError("Duplicate game Dock tiles already exist; preserving the current Dock.")
    added = not existing
    index = len(original) if added else existing[0]
    cf = DockCoreFoundation()
    repair = added
    if not added:
        current_tile = original[index]
        data = current_tile.get("tile-data", {})
        repair = (type(data.get("file-type")) is not int or data.get("file-type") != 41 or
                  type(data.get("file-data", {}).get("_CFURLStringType")) is not int or
                  data.get("file-data", {}).get("_CFURLStringType") != 15 or
                  data.get("file-data", {}).get("_CFURLString") != app.as_uri() + "/" or
                  type(current_tile.get("GUID")) is not int or not isinstance(data.get("book"), bytes))
        if not repair:
            try:
                resolved, stale = cf.resolve_bookmark(data["book"])
                repair = stale or resolved != app
            except (RuntimeError, TypeError, FileNotFoundError):
                repair = True
    if repair:
        guids = {tile.get("GUID") for tile in original}
        guid = secrets.randbelow(2**32 - 1) + 1
        while guid in guids:
            guid = secrets.randbelow(2**32 - 1) + 1
        tile = {"GUID": guid, "tile-type": "file-tile", "tile-data": {
            "file-data": {"_CFURLString": app.as_uri() + "/", "_CFURLStringType": 15},
            "file-label": LABEL, "bundle-identifier": info["CFBundleIdentifier"],
            "file-type": 41, "book": cf.bookmark(app)}}
        updated = list(original)
        if added:
            updated.append(tile)
        else:
            updated[index] = tile
        cf.write_persistent_apps(updated, original, index)
        run("/usr/bin/killall", "-u", str(os.getuid()), "Dock")
    after = None
    for _ in range(40):
        _, after = dock()
        current = after.get("persistent-apps", [])
        if len([tile for tile in current if tile_path(tile) == app]) == 1:
            break
        time.sleep(.2)
    current = after.get("persistent-apps", [])
    expected_count = len(original) + int(added)
    untouched_after = current[:index] + current[index + 1:]
    untouched_before = original if added else original[:index] + original[index + 1:]
    if len(current) != expected_count or untouched_after != untouched_before or len([
            t for t in current if tile_path(t) == app]) != 1:
        raise RuntimeError("Dock verification failed; the original domain backup is preserved.")
    installed = current[index]
    data = installed["tile-data"]
    if type(data["file-data"]["_CFURLStringType"]) is not int or type(data["file-type"]) is not int:
        raise RuntimeError("Dock URL/type values were not saved as native integers.")
    resolved, stale = cf.resolve_bookmark(data["book"])
    if stale or resolved != app:
        raise RuntimeError("Dock's native application bookmark does not resolve correctly.")
    print(json.dumps({"result": "Passed", "native_app": str(app), "shortcut": str(shortcut),
                      "dock_added": added, "dock_repaired": repair and not added,
                      "dock_apps_before": len(original),
                      "dock_apps_after": len(current), "existing_app_order_preserved": True,
                      "signature_verified": True, "executable_name": info["CFBundleExecutable"],
                      "bundle_identifier_preserved": info["CFBundleIdentifier"],
                      "asset_copy_bytes": 0, "icon_copy_bytes": icon_bytes,
                      "typed_dock_values_verified": True, "bookmark_target_verified": True,
                      "private_recovery": str(backup)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
