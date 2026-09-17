#!/bin/zsh
editor_dir="${0:A:h}"
open -n -a Blender --args --enable-autoexec "$editor_dir/검_방패_양손_직접편집.blend" --python "$editor_dir/editor_ui.py"
