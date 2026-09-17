"""Package verified hand detail plus its independently verified thumb roll.

Run only after directly reviewing final native and actual GPU captures.
"""
import argparse,hashlib,json,shutil,zipfile
from pathlib import Path

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def read(p):return json.loads(Path(p).read_text())
def json_digest(value):return hashlib.sha256(json.dumps(value,sort_keys=True).encode()).hexdigest()
def verify_report(path):
 report=read(path);assert report['status']=='passed' and not report['errors'],path
 assert report['verified_sha256'],path
 for filename,value in report['verified_sha256'].items():assert len(value)==64 and sha(filename)==value,filename
 return report
def require_report_input(report,path):
 assert report['verified_sha256'].get(str(Path(path).resolve()))==sha(path),path
def verify_native(folder,expected,renderer):
 report=read(folder/'render_report.json')
 assert report['status']=='complete' and report['source_file_unchanged'] and report['source_datablocks_unchanged']
 assert report['source_sha256']==sha(report['source']) and report['script_sha256']==sha(renderer)
 assert report['frames_sha256']==json_digest(report['frames'])
 assert report['camera_manifest_sha256']==sha(report['camera_manifest'])
 assert read(report['camera_manifest'])['frames']==report['frames']
 assert set(report['renders'])==expected
 for name,row in report['renders'].items():
  assert row['actual_blender_geometry'] and sha(folder/row['file'])==row['sha256']
  assert row['frame_sha256']==json_digest(report['frames'][name])
 return report
def main():
 p=argparse.ArgumentParser();p.add_argument('--candidate',required=True);p.add_argument('--visually-reviewed',action='store_true');p.add_argument('--gpu-reviewed',action='store_true');a=p.parse_args();assert a.visually_reviewed and a.gpu_reviewed
 stage=Path(__file__).resolve().parents[1];root=stage.parents[1];game=root/'godot-game';model=stage/'mac_output'/a.candidate
 # The detail proof remains bound to source08; the thumb-only proof binds source08 to this candidate.
 detail_path=model/'prior_detail_verification_report.json';rotation_path=model/'thumb_rotation_verification.json'
 detail=verify_report(detail_path);rotation=verify_report(rotation_path)
 source=Path(rotation['source_iteration']).resolve();assert source!=model.resolve()
 source_blend=source/'bilateral_hands_finger_detail.blend';blend=model/'bilateral_hands_finger_detail.blend'
 assert sha(detail_path)==sha(source/'verification_report.json')
 for filename in ('bilateral_hands_finger_detail.blend','left_hand_finger_detail.glb','right_hand_finger_detail.glb','realistic_hands_basecolor.png','realistic_hands_normal.png','realistic_hands_roughness.png'):
  require_report_input(detail,source/filename);require_report_input(rotation,source/filename);require_report_input(rotation,model/filename)
 require_report_input(rotation,model/'thumb_rotation_report.json')
 authored=read(model/'thumb_rotation_report.json')
 assert Path(authored['source']).resolve()==source_blend and authored['source_sha256']==sha(source_blend)
 assert authored['blend_sha256']==sha(blend) and rotation['checks']['materials_exact_iteration08']
 orientation={}
 for side in ('left','right'):
  observed=rotation['checks']['editable_'+side]['thumb_rotation']['nail_thumb']
  orientation[side]={'authored_roll_degrees':authored['hands'][side]['angle_degrees'],'measured_normal_separation_from_four_nails_degrees':observed['separation_from_four_nails_degrees'],'measured_top_area_normal_native':observed['measured_top_area_normal_native'],'outward_radial_normal_dot':observed['outward_radial_normal_dot']}
  assert authored['hands'][side]['export']['sha256']==sha(model/f'{side}_hand_finger_detail.glb')
 for row in authored['renders'].values():assert row['actual_blender_render'] and sha(model/row['file'])==row['sha256']
 prior=read(stage/'baseline/preserved_previous.json');assert len(prior)==111 and all(sha(root/p)==v for p,v in prior.items())
 expected={f'{d}_{v}' for d in ('thumb','index','middle','ring','little') for v in ('dorsal','palmar')}
 refs=stage/'reference/individual';record=read(refs/'generation_record.json');prompts=read(refs/'prompts.json');assert set(record)==expected and set(prompts)==expected
 for name,r in record.items():
  assert r['mode']=='built-in image_gen' and r['one_digit_one_face'] and r['directly_visually_reviewed']
  assert sha(refs/r['file'])==r['sha256'] and r['prompt']==prompts[name]
 renderer=stage/'tools/render_individual_fingers.py'
 before=verify_native(stage/'baseline/individual_renders',expected,renderer);after=verify_native(model/'individual',expected,renderer)
 local=verify_native(model/'thumb_local',{'thumb_dorsal','thumb_palmar'},renderer)
 assert before['frames_sha256']==after['frames_sha256'] and after['source_sha256']==local['source_sha256']==sha(blend)
 assert local['frames_sha256']!=after['frames_sha256'],'Intrinsic thumb views must follow the rolled thumb'
 for name in expected-{'thumb_dorsal','thumb_palmar'}:assert local['frames'][name]==after['frames'][name],'Supplemental camera may only change thumb views'
 profile=read(model/'profile/profile_report.json');assert profile['actual_blender_geometry'] and profile['source_unchanged'] and profile['source_sha256']==after['source_sha256']
 assert set(profile['renders'])=={'thumb_oblique','thumb_profile'}
 for row in profile['renders'].values():assert sha(model/'profile'/row['file'])==row['sha256']
 headless=stage/'godot_headless_final.log';log=headless.read_text();assert 'Headless validation: 7 passed, 0 failed.' in log and 'ERROR:' not in log
 for side in ('left','right'):assert sha(model/f'{side}_hand_finger_detail.glb')==sha(game/f'assets/3d/player/hands_detailed/{side}_hand_detailed.glb')
 names={'player_finger_joints':{'open','palm','wrist_side','roots','middles','tips','fist','bow_draw','chest_touch','controls','skin_dorsal_neutral','skin_palm_neutral'},'player_hands_detailed':{'free_hands','free_hands_greybox','bow_draw','bow_release','chest_touch','chest_lift'}}
 previews={};sources=set()
 for kind,images in names.items():
  folder=game/'artifacts/visual_qa'/kind/'finger_detail_final_01';m=read(folder/'capture_manifest.json')
  assert {c['image'].removesuffix('.png') for c in m['captures']}==images and not m['failures']
  assert m['display_driver']=='embedded' and m['actual_renderer']=='vulkan' and m['sources_unchanged_during_capture'] and m['expedition_inventory_and_cursor_preserved']
  for path,value in m['source_sha256'].items():
   path=path.removeprefix('res://');assert len(value)==64 and sha(game/path)==value,path;sources.add(path)
  for c in m['captures']:
   assert c['passed'] and sha(folder/c['image'])==c['image_sha256']
   if kind=='player_finger_joints':
    assert c['wrist_gpu_buffers']['passed'] and c['actual_pbr_bindings']['passed']
    pixels=c['actual_pbr_bindings']['bound_texture_pixels'];assert pixels
    for row in pixels.values():assert row['passed'] and row['actual_pixel_sha256']==row['source_pixel_sha256']
  previews[kind]={'images':len(images),'directly_visually_reviewed':True,'manifest_sha256':sha(folder/'capture_manifest.json')}
 summary={
  'status':'passed','candidate':a.candidate,'reference_count':10,
  'reference_strategy':'Each separate image shows only one digit and one face.','image_generation_mode':'built-in image_gen',
  'independent_verification_chain':{
   'approved_proportions_to_detail':{'candidate':source.name,'report':detail_path.name,'report_sha256':sha(detail_path)},
   'detail_to_final_thumb_orientation':{'candidate':a.candidate,'report':rotation_path.name,'report_sha256':sha(rotation_path)},
   'all_recorded_input_sha256_rechecked':True},
  'thumb_orientation':orientation,
  'native_before_after_renders':{'before':10,'after':10,'all_final_faces_directly_visually_reviewed':True,'same_camera_and_lighting_frames':before['frames_sha256'],'fixed_hand_space_views_retained_for_honest_shape_comparison':True},
  'supplemental_thumb_renders':{'intrinsic_dorsal_and_palmar':2,'oblique_and_profile':2,'all_directly_visually_reviewed':True,'purpose':'Separate intrinsic faces follow the actual rolled thumb for comparison with the two single-face AI references; the original ten global camera frames remain intact.','local_frames_sha256':local['frames_sha256'],'local_render_report_sha256':sha(model/'thumb_local/render_report.json'),'profile_report_sha256':sha(model/'profile/profile_report.json')},
  'headless':{'passed':7,'failed':0,'log_sha256':sha(headless)},'gpu':previews,'preserved_previous_files':111,
  'limitations':[
   'AI references guide surface detail; this is a rigged game model, not a photogrammetric reconstruction or an exact pixel match.',
   'The thumb nail and its exposed skin bed are rolled together around the thumb axis. Approved bone rest axes are retained; this is not a newly authored anatomical opposition rig.',
   'The glove and overall finger lengths are retained. The thumb silhouette changes with its corrected roll; the other four finger poses remain.',
   'Fine relief uses baked 4K PBR maps; it is not all separate mesh geometry.',
   'Nail seating is sampled on the actual distal nail bed in eight poses per hand; continuous surface penetration and whole-fist self collision are not exhaustively simulated.',
   'Unrelated full-project tests were not run.']}
 (stage/'validation_summary.json').write_text(json.dumps(summary,indent=2)+'\n')
 dest=root/'exports/Player_Finger_Detail_2026-09-11';archive=dest.with_suffix('.zip');assert not dest.exists() and not archive.exists();dest.mkdir()
 def copy(src,dst):dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dst)
 for item in model.iterdir():
  if item.is_file() and item.suffix in ('.blend','.glb','.png','.json'):copy(item,dest/item.name)
 for src,rel in [(refs,'references'),(model/'individual','individual_after'),(model/'thumb_local','thumb_local'),(model/'profile','thumb_profile'),(stage/'baseline/individual_renders','individual_before')]:shutil.copytree(src,dest/rel)
 for label,r in [('global',after),('thumb_local',local)]:copy(Path(r['camera_manifest']),dest/'validation/cameras'/f'{label}.json')
 for name in ('README.md','iteration_review.json','validation_summary.json','godot_integration.json'):copy(stage/name,dest/name)
 for item in (stage/'tools').glob('*.py'):copy(item,dest/'tools'/item.name)
 for item in stage.glob('*.log'):copy(item,dest/'validation'/item.name)
 copy(stage/'baseline/preserved_previous.json',dest/'validation/preserved_previous.json')
 for kind in names:shutil.copytree(game/'artifacts/visual_qa'/kind/'finger_detail_final_01',dest/'godot_preview'/kind)
 sources.update(['tests/player_finger_joints_test.gd','tests/player_hands_detailed_test.gd','scripts/test_room_catalog.gd','assets/3d/player/hands_detailed/README.md','README.md','TEST_ROOM.md','design/TEAM_ROLES.md'])
 for path in sources:
  if Path(path).suffix in ('.gd','.md'):copy(game/path,dest/'runtime_snapshot'/path)
 files={str(f.relative_to(dest)):{'bytes':f.stat().st_size,'sha256':sha(f)} for f in sorted(dest.rglob('*')) if f.is_file()};(dest/'FILE_MANIFEST.json').write_text(json.dumps(files,indent=2)+'\n')
 with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
  for f in sorted(dest.rglob('*')):
   if f.is_file():z.write(f,str(f.relative_to(dest.parent)))
 with zipfile.ZipFile(archive) as z:
  assert z.testzip() is None
  for f in dest.rglob('*'):
   if f.is_file():assert hashlib.sha256(z.read(str(f.relative_to(dest.parent)))).hexdigest()==sha(f)
 assert all(sha(root/p)==v for p,v in prior.items())
 result={'status':'passed','package':str(dest),'files':len(files)+1,'zip_sha256':sha(archive),'zip_bytes':archive.stat().st_size,'zip_crc_and_exact_content':True,'prior_files_unchanged':111};(stage/'package_verification.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
if __name__=='__main__':main()
