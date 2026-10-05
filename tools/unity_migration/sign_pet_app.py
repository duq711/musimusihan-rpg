#!/usr/bin/env python3
"""Ad-hoc sign the local Labrador Mac build; preserve the Korean display name."""
import argparse
import pathlib
import plistlib
import subprocess


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("app", type=pathlib.Path)
    args = parser.parse_args()
    app = args.app.resolve()
    info_path = app / "Contents/Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    # ASCII bundle filenames avoid macOS NFC/NFD resource-seal disagreement.
    executable = app / "Contents/MacOS" / info["CFBundleExecutable"]
    ascii_executable = executable.with_name("MusimusihanRPG")
    if executable != ascii_executable:
        if ascii_executable.exists():
            raise RuntimeError("Refusing to overwrite an existing executable")
        executable.rename(ascii_executable)
        info["CFBundleExecutable"] = ascii_executable.name
        info_path.write_bytes(plistlib.dumps(info, sort_keys=False))
    plugins = app / "Contents/PlugIns"
    for plugin in sorted(plugins.iterdir()):
        if plugin.is_file() and plugin.suffix in (".dylib", ".bundle"):
            subprocess.run(["codesign", "--force", "--sign", "-", str(plugin)], check=True)
    subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app)], check=True)


if __name__ == "__main__":
    main()
