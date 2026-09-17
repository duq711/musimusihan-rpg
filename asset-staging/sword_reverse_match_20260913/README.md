> **사용자 거절 · 게임에서 원복됨 (2026-09-13)**
> 아래는 거절된 좌우 대칭 역베기 시도의 과거 구현·검사 기록입니다. 자연스러운 모션으로 승인된 결과가 아닙니다. 게임의 역베기와 연결 코드는 이 폴더의 `baseline/`으로 복원했으며, 승인된 기본 베기는 유지했습니다. 원복 검증 기록은 `../sword_reverse_restore_20260913/`을 참조합니다.

# Opposite cut from the approved forehand — 2026-09-13

The user accepted the existing right-to-left `right_diagonal` as complete and asked for a similar attack with the direction reversed. This supersedes the earlier request to retain the old `left_reverse` motion. The accepted forehand remains unchanged.

`baseline/` preserves the complete accepted delivery and runtime before this change. Its forehand canonical JSON SHA-256 is `57b8ec6068eb985402ff70b2a1f34e561c9a1868b64fb39e72050f51d2642a65`. `source_preservation.json` records exact preservation of that clip, all other unaffected clips, shield samples, combat timing and original assets.

`author_reverse.py` runs on Mac Blender 5.2.1 and produces `candidate_01/Reverse_From_Accepted_Forehand.blend` plus the delivered animation manifest. In the cut interval, camera X reflection mirrors the palm, blade length and blade-face normal. A second local width-axis reflection makes the resulting basis a proper rotation with determinant +1. No hand or sword mesh is reflected or negatively scaled. The original right hand's local wrist is transformed by the new pose and its fixed-length arm is solved again, instead of reflecting old arm joints. Existing reach compensation is retained and assessed in the actual render.

The reverse preparation moves from the common right-side idle to the left at unchanged grip height/depth in 0.20 seconds. Its wrist lays the blade in 0.14 seconds. These fit inside the unchanged minimum 0.22-second windup. ACTIVE begins continuously at the prepared left pose and joins the mirrored authored track within its existing first 0.10 seconds. The mirrored cut holds the same edge plane and contact timing as the approved forehand; recovery joins the common original idle. The forehand and overhead entry paths are preserved.

`preflight.log` verifies actual short/charged attacks, entry continuity, fixed arm lengths and capture configuration. `edge_alignment_verified.log` verifies both blade planes, the actual reflected path, wrist anchors and the accepted forehand. The first edge test run exposed a cross-parser numeric fingerprint mismatch; `edge_fingerprint_source_verification.log` checks the immutable approved baseline, and `edge_baseline_fingerprint_diagnostic.log` records the fingerprint measured from that baseline in Godot. The geometric assertions and motion were not loosened or modified to resolve this test issue.

The final comparison places the actual forehand and reverse recordings side by side at the same frame. It does not mirror video pixels. Original thumb and support-hand meshes are preserved; this work makes no separate claim of anatomical mesh repair. The prior natural-clash fixture issue belongs to the unchanged forehand and its previous validation record.
