"""Read original Labrador BVH captures without changing their motion data.

This module contains no downloaded model or capture data. The source captures
must be obtained under their own license and attributed separately. Parsing is
independent of Blender so hierarchy/channel failures can be reported before DCC
import. Blender callers may use ``world_pose`` for evaluated joint transforms.
"""
from __future__ import annotations

from dataclasses import dataclass, field
import math
from pathlib import Path
import re


@dataclass
class Joint:
    name: str
    parent: int | None
    offset: tuple = (0.0, 0.0, 0.0)
    channels: list = field(default_factory=list)
    channel_start: int = 0
    children: list = field(default_factory=list)
    end_site: bool = False


@dataclass
class Capture:
    path: Path
    joints: list
    frames: list
    frame_time: float
    channel_count: int

    @property
    def fps(self):
        return 1.0 / self.frame_time

    @property
    def duration(self):
        return max(0, len(self.frames) - 1) * self.frame_time

    def description(self):
        return {
            "file": self.path.name, "frame_count": len(self.frames),
            "fps": self.fps, "duration_seconds": self.duration,
            "channel_count": self.channel_count,
            "joints": [
                {"name": j.name, "parent": None if j.parent is None else self.joints[j.parent].name,
                 "offset": list(j.offset), "channels": j.channels, "end_site": j.end_site}
                for j in self.joints
            ],
        }

    def world_pose(self, frame, coordinate=None, scale=1.0, position_mode="absolute"):
        """Evaluate recorded rotations; available inside Blender only.

        A fractional frame interpolates channels, including Euler wraps by the
        shorter arc. ``coordinate`` maps BVH coordinate space into the target
        armature space. It never rescales segment lengths independently.
        This dataset records all joints' local offsets again in XYZ position
        channels. ``absolute`` therefore replaces OFFSET on those axes, matching
        Blender's bundled BVH importer. ``additive`` is available for captures
        whose position channels are offsets from OFFSET instead.
        """
        from mathutils import Matrix, Vector
        coordinate = coordinate or Matrix.Identity(4)
        inverse = coordinate.inverted()
        frame = max(0.0, min(float(frame), len(self.frames) - 1))
        first = int(frame); last = min(first + 1, len(self.frames) - 1)
        fraction = frame - first
        result = []
        for joint in self.joints:
            translation = Vector(joint.offset)
            local_rotation = Matrix.Identity(4)
            for ci, channel in enumerate(joint.channels):
                channel_index = joint.channel_start + ci
                a = self.frames[first][channel_index]; b = self.frames[last][channel_index]
                if channel.endswith("rotation"):
                    difference = (b - a + 180) % 360 - 180
                    value = a + fraction * difference
                    local_rotation = local_rotation @ Matrix.Rotation(math.radians(value), 4, channel[0].upper())
                elif channel.endswith("position"):
                    value = a + fraction * (b - a)
                    axis = "XYZ".index(channel[0].upper())
                    if position_mode == "absolute":
                        translation[axis] = value
                    elif position_mode == "additive":
                        translation[axis] += value
                    else:
                        raise ValueError("Invalid BVH position mode: " + position_mode)
                else:
                    raise ValueError("Unsupported BVH channel: " + channel)
            local = Matrix.Translation(translation) @ local_rotation
            world = local if joint.parent is None else result[joint.parent] @ local
            result.append(world)
        transformed = []
        for world in result:
            mapped = coordinate @ world @ inverse
            mapped.translation *= scale
            transformed.append(mapped)
        return {joint.name: matrix for joint, matrix in zip(self.joints, transformed)}


def read_bvh(path):
    path = Path(path)
    text = path.read_text(encoding="utf-8-sig")
    return parse_bvh(text, path)


def parse_bvh(text, path="capture.bvh"):
    """Parse an already read archive entry without making an extracted copy."""
    path = Path(path)
    sections = re.split(r"\bMOTION\b", text, maxsplit=1)
    if len(sections) != 2:
        raise ValueError(f"Missing MOTION section: {path.name}")
    tokens = re.findall(r"[{}]|[^\s{}]+", sections[0])
    cursor = 0; joints = []; channel_count = 0

    def take(expected=None):
        nonlocal cursor
        if cursor >= len(tokens):
            raise ValueError(f"Truncated hierarchy: {path.name}")
        value = tokens[cursor]; cursor += 1
        if expected is not None and value != expected:
            raise ValueError(f"Expected {expected}, got {value}: {path.name}")
        return value

    def parse_joint(parent=None, end_site=False):
        nonlocal channel_count
        name = (joints[parent].name + "_EndSite") if end_site else take()
        index = len(joints)
        joint = Joint(name=name, parent=parent, end_site=end_site)
        if any(j.name == name for j in joints):
            raise ValueError(f"Duplicate joint name {name}: {path.name}")
        joints.append(joint)
        if parent is not None:
            joints[parent].children.append(index)
        take("{"); take("OFFSET")
        joint.offset = tuple(float(take()) for _ in range(3))
        if not all(math.isfinite(v) for v in joint.offset):
            raise ValueError(f"Nonfinite offset: {path.name}")
        if not end_site:
            take("CHANNELS"); count = int(take())
            if count < 0 or count > 6:
                raise ValueError(f"Invalid channel count: {path.name}")
            joint.channel_start = channel_count
            joint.channels = [take() for _ in range(count)]
            channel_count += count
        while tokens[cursor] != "}":
            token = take()
            if token == "JOINT":
                parse_joint(index)
            elif token == "End":
                take("Site"); parse_joint(index, True)
            else:
                raise ValueError(f"Unexpected hierarchy token {token}: {path.name}")
        take("}")

    take("HIERARCHY"); take("ROOT"); parse_joint()
    if cursor != len(tokens):
        raise ValueError(f"Trailing hierarchy tokens: {path.name}")
    match = re.match(r"\s*Frames:\s*(\d+)\s*Frame\s+Time:\s*([\d.eE+-]+)\s*", sections[1])
    if match is None:
        raise ValueError(f"Missing frame count or time: {path.name}")
    frame_count = int(match.group(1)); frame_time = float(match.group(2))
    if not math.isfinite(frame_time) or frame_time <= 0:
        raise ValueError(f"Invalid frame time: {path.name}")
    rows = sections[1][match.end():].splitlines()
    frames = []
    for row in rows:
        if not row.strip():
            continue
        values = [float(token) for token in row.split()]
        if len(values) != channel_count or not all(math.isfinite(v) for v in values):
            raise ValueError(f"Invalid motion row {len(frames)}: {path.name}")
        frames.append(values)
    if len(frames) != frame_count or not frames:
        raise ValueError(f"Expected {frame_count} frames, got {len(frames)}: {path.name}")
    return Capture(path, joints, frames, frame_time, channel_count)
