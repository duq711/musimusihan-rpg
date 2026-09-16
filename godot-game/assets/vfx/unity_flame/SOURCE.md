Unity Labs, Flame02

Source: https://unity.com/blog/engine-platform/free-vfx-image-sequences-flipbooks
Download: https://unity3d.com/files/labs/downloads/vfx/assets01/Flame02/Flame02-flipbooks.zip
License: CC0 1.0, as declared on the source article. https://creativecommons.org/publicdomain/zero/1.0/

Flame02_16x4.tga converted losslessly to PNG for Godot. Original 2048x1024 RGBA atlas, 64 frames (16 columns x 4 rows). GPU interpolates consecutive frames at 24 fps. Multiple independent cards surround the oil-soaked wrapping. Previous raymarch assets retained as an unused backup.

2026-09-12: enlarged cloth and upper flame cards. Player lateral velocity drives a smoothed world-space lean in the movement direction; the shared cloth-base pivot stays fixed. Crossed cards receive the same deformation transformed into their own local coordinates.
