"""Compatibility entry point for the accepted lower-interface repair.

Earlier v16zf-v16zj under-cowl seal experiments created visible bibs, plates,
or a rear bridge. The accepted isolated candidate instead sculpts the lower
rim of the existing one-piece cowl; its implementation lives in
``build_v16zl_sculpted_lower_drape.py``. Keeping this dispatcher makes the
historical command safe to run without resurrecting the rejected mesh.
"""

from pathlib import Path
import runpy


SCRIPT = Path(__file__).with_name("build_v16zl_sculpted_lower_drape.py")
runpy.run_path(str(SCRIPT), run_name="__main__")
