"""Adapt actual Windows samples after the receiving canonical rest is supplied.

Read-only inspection (stdlib only):
  python convert_manifest.py --samples ../output/iteration_02/motion_samples_120hz.json --inspect

Conversion requires --mapping, --execution, --hit-times and --out (a new file).
No model, motion, source samples or existing manifest is modified.

Mapping JSON must contain schema_version=1, source_samples_sha256,
normalization_confirmed=true, evidence (nonempty explanation), and
canonical_ready_camera.sword/shield, each with position=[x,y,z] and
rotation_xyzw=[x,y,z,w]. These are the receiving canonical source-ready sword
and production shield-idle pivot transforms, in the declared camera frame.
They MUST come from the receiving game's normalization, not the video idle.

Execution JSON must contain provenance (the exact schema object, from the
actual successful Windows authoring wrapper), camera_aspect_ratio=[16,9],
artifact_root, and artifacts=[{kind,relative_path}, ...]. Artifact hashes are
computed, never taken on trust. Do not synthesize execution timestamps here.

Hit-times JSON: {clip_name:{hit_seconds:<relative to active start>,basis:<text>}}
for each attack. A runtime contact choice is acceptable if basis says so;
the provided event observations do not establish an exact contact instant.

Final conversion requires jsonschema. The local preparation Python does not
currently have it; inspection and script preparation do not install packages.
"""
import argparse
import bisect
from datetime import datetime
import hashlib
import json
import math
from pathlib import Path

ATTACKS = {"right_diagonal": ("crossing starts", "crossing ends"),
           "left_reverse": ("crossing starts", "crossing ends"),
           "overhead": ("downstroke starts", "downstroke ends")}
NAMES = ("idle", "run", "takeoff", "air", "land", *ATTACKS)
ROLES = ("sword", "shield")
HERE = Path(__file__).resolve().parent


def read(path):
    return json.loads(Path(path).read_text(encoding="utf-8-sig"))


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write_new(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("x", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2, allow_nan=False)
        handle.write("\n")


def vec(value, length):
    result = [float(v) for v in value]
    if len(result) != length or not all(math.isfinite(v) for v in result):
        raise ValueError("Expected a finite vector of length " + str(length))
    return result


def unit(q):
    q = vec(q, 4)
    norm = math.sqrt(sum(x*x for x in q))
    if abs(norm-1) > 1e-4:
        raise ValueError("Quaternion is not normalized: " + str(norm))
    return [x/norm for x in q]


def multiply(a, b):
    w,x,y,z = a; v,i,j,k = b
    return [w*v-x*i-y*j-z*k, w*i+x*v+y*k-z*j,
            w*j-x*k+y*v+z*i, w*k+x*j-y*i+z*v]


def rotate(q, p):
    return multiply(multiply(q, [0, *p]), [q[0], -q[1], -q[2], -q[3]])[1:]


def slerp(a, b, f):
    a, b = unit(a), unit(b)
    dot = sum(x*y for x,y in zip(a,b))
    if dot < 0:
        b = [-x for x in b]; dot = -dot
    dot = min(1.0, max(-1.0, dot))
    if dot > .9995:
        q = [(1-f)*x+f*y for x,y in zip(a,b)]
        n = math.sqrt(sum(x*x for x in q))
        return [x/n for x in q]
    angle = math.acos(dot)
    return [(math.sin((1-f)*angle)*x+math.sin(f*angle)*y)/math.sin(angle)
            for x,y in zip(a,b)]


def active_bounds(clip):
    first, last = ATTACKS[clip["name"]]
    events = {e["event"]:e["time_s"] for e in clip["source_events"]}
    start = clip["source_window_s"][0]
    # Reported decimal event times are exact contract instants; subtracting
    # floats must not turn a phase seam into a nearby but unequal timestamp.
    return round(events[first]-start, 12), round(events[last]-start, 12)


def validate_raw(raw):
    if raw["schema_version"] != "camera_pose_draft_1":
        raise ValueError("Unsupported raw sample format")
    if raw["coordinate_system"] != "camera_x_right_y_up_z_back" or raw["units"] != "meters" or raw["quaternion_order"] != "wxyz":
        raise ValueError("Unexpected source coordinates")
    if set(c["name"] for c in raw["clips"]) != set(NAMES) or len(raw["clips"]) != 8:
        raise ValueError("Expected exactly eight distinct clips")
    if abs(raw["camera_fov_y_degrees"]-76) > 1e-5:
        raise ValueError("Camera field of view differs from the contract")
    for clip in raw["clips"]:
        samples = clip["samples"]; times = [s["time_s"] for s in samples]
        if len(times) < 2 or times[0] != 0 or abs(times[-1]-clip["duration_s"]) > 1e-9:
            raise ValueError("Missing clip endpoints: " + clip["name"])
        if any(b <= a or b-a > 1/60+1e-8 for a,b in zip(times,times[1:])):
            raise ValueError("Invalid or undersampled timeline: " + clip["name"])
        if clip["loop"] != (clip["name"] in ("idle","run","air")):
            raise ValueError("Incorrect loop flag: " + clip["name"])
        for sample in samples:
            for role in ROLES:
                vec(sample["tracks"][role]["position_m"], 3)
                unit(sample["tracks"][role]["quaternion_wxyz"])


def inspect(raw, samples_path):
    validate_raw(raw)
    attacks = {}
    for clip in raw["clips"]:
        if clip["name"] not in ATTACKS:
            continue
        a,b = active_bounds(clip)
        times = [s["time_s"] for s in clip["samples"]]
        attacks[clip["name"]] = {
            "windup_seconds":a, "active_seconds":round(b-a,12),
            "recovery_seconds":round(clip["duration_s"]-b,12),
            "known_exact_seams_seconds":[0,a,b,clip["duration_s"]],
            "seams_missing_from_raw_grid":[t for t in (a,b) if not any(abs(t-v)<1e-10 for v in times)],
            "hit_seconds":None,
            "hit_time_status":"not established by supplied source_events; requires explicit runtime choice or observation"}
    return {"status":"semantic_pending", "source_samples_path":str(samples_path.resolve()),
            "source_samples_sha256":sha(samples_path), "source_format_valid":True,
            "received_schema_saved":True, "received_schema_applied":False,
            "source_ready_control_camera":{role:{"position":raw["source_idle"]["pivots_camera_m"][role],
                "rotation_xyzw":[0,0,0,1]} for role in ROLES},
            "source_ready_basis_evidence":"author_motion.py creates camera-parented controls at the measured pivots with identity rotation and reparents source meshes preserving world transforms before video idle is applied",
            "video_idle_is_not_source_ready":raw["tracks"],
            "conversion_formula":"M_canonical(t) = M_raw_control(t) * inverse(T(source_idle.pivot_camera_m)) * M_receiving_canonical_ready",
            "missing":["Receiving canonical source-ready sword and production shield-idle transforms, with normalization evidence",
                "Exact attack hit_seconds relative to active start, with observation/runtime-choice basis",
                "Actual successful Windows authoring execution provenance and artifact list"],
            "attacks":attacks,
            "sampling_note":"Exact phase/contact instants are inserted using source-sample linear position and shortest SLERP. Existing raw source files remain unchanged. This describes sample interpolation, not new animation authoring.",
            "limits":["Schema receipt alone does not establish canonical normalization.",
                "No exact visual agreement with the reference video is asserted.",
                "The original authoring report identifies these motions as an independently authored preview."]}


def at_time(clip, role, t):
    samples = clip["samples"]; times = [s["time_s"] for s in samples]
    i = bisect.bisect_left(times, t)
    if i < len(times) and abs(times[i]-t)<1e-10:
        pose = samples[i]["tracks"][role]
        return vec(pose["position_m"],3), unit(pose["quaternion_wxyz"])
    if i == 0 or i == len(times):
        raise ValueError("Interpolation outside authored duration")
    f = (t-times[i-1])/(times[i]-times[i-1])
    a,b = (samples[k]["tracks"][role] for k in (i-1,i))
    return ([(1-f)*x+f*y for x,y in zip(a["position_m"],b["position_m"])],
            slerp(a["quaternion_wxyz"],b["quaternion_wxyz"],f))


def convert(raw, samples_path, mapping, execution, hits):
    from jsonschema import Draft202012Validator, FormatChecker
    schema = read(HERE/"motion_manifest.schema.json")
    if mapping.get("schema_version") != 1 or mapping.get("source_samples_sha256") != sha(samples_path):
        raise ValueError("Mapping must identify the exact source sample file")
    if mapping.get("normalization_confirmed") is not True or not mapping.get("evidence", "").strip():
        raise ValueError("Receiving normalization has not been explicitly confirmed")
    if execution.get("camera_aspect_ratio") != [16,9]:
        raise ValueError("The actual camera aspect ratio must be verified")
    provenance = execution["provenance"]
    actual_times = {}
    for field in ("started_at_utc", "completed_at_utc"):
        dt = datetime.fromisoformat(provenance[field].replace("Z", "+00:00"))
        if dt.tzinfo is None or dt.utcoffset().total_seconds() != 0:
            raise ValueError("Actual execution timestamps must be in UTC")
        actual_times[field] = dt
    if actual_times["completed_at_utc"] < actual_times["started_at_utc"]:
        raise ValueError("Execution completion precedes its start")
    bases = {}
    for role in ROLES:
        rest = mapping["canonical_ready_camera"][role]
        p = vec(rest["position"],3); q = unit([rest["rotation_xyzw"][3], *rest["rotation_xyzw"][:3]])
        bases[role] = (p,q)
    output_clips = {}; inserted = {}
    for clip in raw["clips"]:
        name = clip["name"]; duration = clip["duration_s"]
        target = {"kind":"attack" if name in ATTACKS else "locomotion",
                  "duration_seconds":duration,"loop":clip["loop"],
                  "nominal_sample_hz":raw["sample_rate_hz"],"tracks":{},"reference_segments":[]}
        window = clip["source_window_s"]
        if window:
            observations = "; ".join(str(e["time_s"])+"s: "+e["event"]+" ("+e.get("basis","unspecified")+")" for e in clip["source_events"])
            target["reference_segments"] = [{"start_seconds":window[0],"end_seconds":window[1],"observations":observations}]
        source_times = [s["time_s"] for s in clip["samples"]]
        required = [0,duration]
        if name in ATTACKS:
            a,b = active_bounds(clip); hit = float(hits[name]["hit_seconds"])
            if not 0 < hit <= b-a+1e-10 or not hits[name]["basis"].strip():
                raise ValueError("Invalid or unexplained contact time: " + name)
            target["timing"] = {"windup_seconds":a,"active_seconds":round(b-a,12),
                "hit_seconds":hit,"recovery_seconds":round(duration-b,12),
                "runtime_mapping":"phase_resample","reference_charge":0.0}
            target["notes"] = "Contact timing basis: "+hits[name]["basis"]
            required += [a,round(a+hit,12),b]
        # Preserve all actual sample instants, substituting the mathematically
        # exact seam value only when an existing timestamp is within 1e-10 s.
        times = sorted({next((r for r in required if abs(t-r)<1e-10),t) for t in source_times} | set(required))
        inserted[name] = [t for t in times if not any(abs(t-s)<1e-10 for s in source_times)]
        for role in ROLES:
            canonical_p,canonical_q = bases[role]
            pivot = raw["source_idle"]["pivots_camera_m"][role]
            offset = [x-y for x,y in zip(canonical_p,pivot)]
            track = []; previous = None
            for t in times:
                p,q = at_time(clip,role,t)
                p = [x+y for x,y in zip(p,rotate(q,offset))]
                q = unit(multiply(q,canonical_q))
                if previous is not None and sum(x*y for x,y in zip(q,previous)) < 0:
                    q = [-x for x in q]
                previous = q
                track.append({"time_seconds":t,"position":p,"rotation_xyzw":[*q[1:],q[0]]})
            target["tracks"][role] = track
        output_clips[name] = target
    source_paths = [p for p in raw["source_sha256"] if p.replace("\\","/").endswith("/SwordHold_Static.blend")]
    if len(source_paths) != 1:
        raise ValueError("Cannot identify the preserved source Blender file")
    artifact_root = Path(execution["artifact_root"]).resolve(); artifacts = []
    for entry in execution["artifacts"]:
        relative = Path(entry["relative_path"])
        path = (artifact_root/relative).resolve()
        if relative.is_absolute() or not path.is_relative_to(artifact_root) or not path.is_file():
            raise ValueError("Artifact must be an existing file within artifact_root")
        artifacts.append({"kind":entry["kind"],"relative_path":relative.as_posix(),"sha256":sha(path)})
    manifest = {"schema_version":1,"status":"authored_windows_output",
        "reference_video_url":"https://youtu.be/sU7jk2OQlgc",
        "source":{"godot_model_path":schema["properties"]["source"]["properties"]["godot_model_path"]["const"],
            "godot_model_sha256":schema["properties"]["source"]["properties"]["godot_model_sha256"]["const"],
            "blender_input_path":source_paths[0],"blender_input_sha256":raw["source_sha256"][source_paths[0]]},
        "coordinate_system":{k:v["const"] for k,v in schema["properties"]["coordinate_system"]["properties"].items()},
        "camera":{"vertical_fov_degrees":76.0,"aspect_ratio":[16,9],"animated":False},
        "provenance":provenance,"clips":output_clips,"artifacts":artifacts}
    Draft202012Validator(schema, format_checker=FormatChecker()).validate(manifest)
    return manifest, {"status":"schema_validated_receiving_semantic_review_required",
        "inserted_exact_sample_times":inserted,"normalization_evidence":mapping["evidence"],
        "source_samples_sha256":sha(samples_path),"hit_time_basis":hits,
        "note":"Receiver must verify canonical mesh normalization and in-game transforms. Schema validation cannot prove that visual correspondence or runtime integration succeeds."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--samples",type=Path,required=True)
    parser.add_argument("--inspect",action="store_true")
    parser.add_argument("--report",type=Path)
    parser.add_argument("--mapping",type=Path)
    parser.add_argument("--execution",type=Path)
    parser.add_argument("--hit-times",type=Path)
    parser.add_argument("--out",type=Path)
    args = parser.parse_args(); raw = read(args.samples)
    readiness = inspect(raw,args.samples)
    if args.inspect:
        if args.report: write_new(args.report,readiness)
        print(json.dumps(readiness,indent=2)); return
    if not all((args.mapping,args.execution,args.hit_times,args.out)):
        parser.error("Conversion requires actual --mapping, --execution, --hit-times and a new --out")
    if args.out.exists() or args.out.with_suffix(".conversion.json").exists():
        parser.error("Choose unused output paths; existing files are preserved")
    manifest, report = convert(raw,args.samples,read(args.mapping),read(args.execution),read(args.hit_times))
    write_new(args.out,manifest)
    report["manifest_sha256"] = sha(args.out)
    write_new(args.out.with_suffix(".conversion.json"),report)
    print(json.dumps(report,indent=2))


if __name__ == "__main__":
    main()
