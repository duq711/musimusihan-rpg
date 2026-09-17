#!/bin/zsh
TASK_DIR="${0:A:h}"
open -n -a Blender --args --enable-autoexec "$TASK_DIR/왼손_횃불_직접편집.blend" --python "$TASK_DIR/hand_editor_ui.py"
