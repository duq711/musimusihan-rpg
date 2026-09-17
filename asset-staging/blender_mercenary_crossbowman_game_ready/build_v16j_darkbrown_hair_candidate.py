"""Build the validated v16j dark-brown short-hair candidate from v15."""
from pathlib import Path
import runpy

runpy.run_path(
    str(Path(__file__).with_name("test_v16e_mpfb_short_hair.py")),
    run_name="__main__",
)
