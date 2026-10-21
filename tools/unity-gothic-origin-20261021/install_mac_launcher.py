#!/usr/bin/env python3
"""새 고딕 Unity 앱만 Dock에 등록합니다. / Register only the new native gothic app."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent / "launcher_support"))
import shared_installer as installer

installer.APP = ROOT / "unity-game/Builds/MusimusihanRPG-GothicOrigin.app"
installer.LABEL = "무시무시한 RPG - 고딕의 기원"

if __name__ == "__main__":
    installer.main()
