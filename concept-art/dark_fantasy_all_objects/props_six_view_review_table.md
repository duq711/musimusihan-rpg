# Actual six-view prop review

Reviewed 51 production objects against their individual generated concepts. Final capture: `final_iteration_03`. Each object covers front, back, left, right, top and bottom. This is a qualitative visual review, not a claim of pixel identity with a concept.

All 51 were directly reviewed in final02. The four subsequently changed objects were directly compared again in final03; decoded pixel comparison checked the other 47 objects across 282 views. Of those, 238 views are identical and 44 differ. All 11 objects with any difference were visually rechecked; the remaining 36 objects have exact six-view pixel identity. Animation and sparse surface-render variance are recorded in `props_final_pixel_consistency.json`.

The completed aggregate contains 126 objects and 756 Vulkan views. All 85 recorded source hashes and 756 directional image hashes were independently verified. The source manifest also confirms unchanged inputs and preserved expedition/cursor state. First aggregate observations remain in `props_final_review.json`.

| Object | Production factory | Final observed comparison |
| --- | --- | --- |
| 사냥용 장궁 (`hunting_bow`) | `archery_visuals.gd::create_bow` | Smooth bent limbs and dark wood are intact; reference uses different front/side orientation and an un-nocked pose. |
| 사냥용 화살 (`hunting_arrow`) | `archery_visuals.gd::create_arrow` | Actual broadhead and feather silhouette present; reference axes and tilted end views differ from true projection. |
| 쇠사슬 철퇴 (`chain_flail`) | `flail_visuals.gd::create_flail` | Dark iron, grip and linked chain read coherently; reference has a hanging rather than held gameplay pose. |
| 가시 철퇴 머리 (`flail_head`) | `flail_visuals.gd::create_head` | Dark iron/spikes intact in all views; standalone production head omits the reference's attached chain/socket. |
| 철퇴 사슬 (`flail_chain`) | `flail_visuals.gd::create_chain` | All alternating links present; production chain is finer than the generated reference, with correct axial end views. |
| 성유물 보급 상자 (`reliquary_chest`) | `loot_chest.gd::_build_visuals` | Final correction verified: iron bands are charcoal rather than pale stone, fasteners seated, closed lid ends and bottom braces intact. Original stepped hinge/contact slats and simpler edge wear remain. |
| 피의 룬 가시 함정 (`blood_rune_trap`) | `trap.gd::_build_visuals` | Final correction verified: circular plate is darker muted stone with original nine spikes and rune response intact. Actual trigger geometry and underside supports remain authoritative. |
| 납골당 아치문 (`dungeon_archway`) | `hideout.gd::_add_arch` | Darkened stone and closed upper jamb gaps confirmed. Curved-stone overhead texture striping and simpler moulding remain. |
| 고딕 석조 기둥 (`dungeon_pillar`) | `hideout.gd::_add_pillar` | Dark clustered drums and continuous capital confirmed; top and underside carving simpler than concept. |
| 폐허 예배당 계단 (`dungeon_stairs`) | `hideout.gd::_build_entry_and_stairs` | Ten steps and side masonry intact; exact horizontal cameras flatten riser depth. Surface weathering remains simpler. |
| 탈출 성소 차원문 (`extraction_portal`) | `game.gd::_build_extraction_gate` | Pointed dark stone opening intact; portal uses existing rune membrane instead of concept's red cloud. Overhead projection striping remains. |
| 머리 없는 성인 석상 (`headless_saint`) | `hideout.gd::_build_broken_saint` | Figure and plinth now consistent darker stone. Robe silhouette present; folds/arms and base ornament remain much simpler than concept. |
| 은신처 잿불 화로 (`hideout_hearth`) | `hideout.gd::_build_hearth` | Final correction verified: three round charred logs use generated coal grain; the low stone foundation is continuous and ring blocks align tangentially. Rounded hollow pot and cup have rolled rims, attached curved handles, closed bottoms and corrected outward/cavity normals. Original placements, hearth toggle and lighting remain intact; surface wear and the reference's wider platform remain simpler. |
| 세발 나무 의자 (`wooden_stool`) | `hideout.gd::_build_small_stool` | Three splayed legs and closed circular seat intact, appropriately dark oak; less worn edge detail than concept. |
| 낡은 보관 선반 (`storage_shelf`) | `hideout.gd::_build_shelf` | Three plank levels and supports intact in darker oak; gameplay shelf wider and thinner than generated concept. |
| 버려진 무기 거치대 (`weapon_rack`) | `hideout.gd::_build_weapon_rack` | Darker rack and shared sword/shield art intact; original rack proportions and rotated placement retained. |
| 은신처 나무 상자 (`hideout_crate`) | `hideout.gd::_add_crate` | Distinct boards, bands and closed bottom intact, dark oak consistent; wear detail and corner framing remain simpler. |
| 은신처 참나무 통 (`hideout_barrel`) | `hideout.gd::_add_barrel` | Bulging staves, black hoops and closed ends intact; curved triplanar surfaces show horizontal projection striping. |
| 빗물 양동이 (`rain_bucket`) | `hideout.gd::_add_bucket` | Open vessel, rolled rim and arcing handle intact with dark iron. Reference has more seams and riveted attachments. |
| 축축한 벽 망토 (`hanging_cloak`) | `hideout.gd::_add_hanging_cloth` | Folded, ragged silhouette visible from all directions; actual charcoal cloth much darker and less layered than reference. |
| 말리는 약초 다발 (`drying_herbs`) | `hideout.gd::_add_hanging_herbs` | Five leafy bundles intact with muted drying colors; leaf clusters remain regular and sparser than reference. |
| 다 탄 밀랍 양초 (`used_candles`) | `hideout.gd::_add_candle_cluster` | Three differing heights, wicks and flame volumes intact. Gameplay candles thinner than concept; wax detail modest. |
| 봉인된 납골실 철문 (`ossuary_gate`) | `hideout.gd::_add_iron_gate` | Dark square bars, pointed tips and brace rivets intact. Real gate is wider with finer bars than concept. |
| 좁은 배수 철문 (`drain_gate`) | `hideout.gd::_add_iron_gate` | Narrow dark gate intact; actual canonical factory has pointed tips while generated reference has flat tips. No geometry change in final color batch. |
| 해골 납골 벽감 (`ossuary_niches`) | `hideout.gd::_add_niche_wall` | Dark stone frame and backing are now consistent. Real production grid is 5×3 versus reference 3×2, with anatomical skulls. |
| 풍화된 해골 (`weathered_skull`) | `hideout.gd::_add_skull` | Final correction verified: anatomical cranium, jaw, teeth and underside read in neutral gray ivory. The source jaw remains open and finer color variation is simpler than concept. |
| 납골당 깨진 석재 (`hideout_rubble`) | `hideout.gd::_add_rubble_cluster` | Dark chipped loose masonry intact; generated concept incorrectly depicts a stacked wall rather than the loose rubble cluster. |
| 젖은 벽 이끼 (`moss_patch`) | `hideout.gd::_add_moss_patch` | Irregular muted green wall overlay intact; concept includes an invented stone backing absent from this individual production patch. |
| 불꽃과 불티 (`flame_and_sparks`) | `hideout.gd::_add_flame` | Bright flame volume and warm sparks visible from all six directions; overhead shape remains rounded, without billboard matte. |
| 천장 물방울 (`water_drips`) | `hideout.gd::_add_water_drips` | Final correction verified: pale tiny glints are visible in the tall falling field from all views. Individual beads remain very small at full-system framing, appropriate to production scale. |
| 짚 침상 (`straw_bed`) | `hideout.gd::_build_sleeping_cell` | All frame posts, folded pads and underside planks intact; darker cloth/wood coherent, much broader/thinner gameplay proportions remain. |
| 진흙 묻은 깔개 (`mud_mat`) | `hideout.gd::_build_entry_and_stairs` | Muted brown ground mat intact; retained low-profile rectangle has less woven fringe/detail than generated reference. |
| 철제 버팀 입구 판자문 (`hidden_hatch`) | `hideout.gd::_build_entry_and_stairs` | Dark wooden hatch and iron bracing intact; actual hatch is vertical in production, whereas generated concept depicts a horizontal floor hatch. |
| 빈 삼베 자루 (`empty_sack`) | `hideout.gd::_build_storage_room` | Folded cloth vessel intact in subdued brown; opening reads flatter without production ambient occlusion, fewer creases than concept. |
| 부서진 작업대 (`broken_workbench`) | `hideout.gd::_build_workshop` | Four separate legs, stretcher and planked top/bottom confirmed. Wood is dark; source bench proportions remain wider than concept. |
| 낡은 숫돌 (`whetstone`) | `hideout.gd::_build_workshop` | Dark chipped rectangular stone intact on all six faces; source placement yaw preserved. |
| 녹슨 바이스 (`rusty_vice`) | `hideout.gd::_build_workshop` | Final correction verified: real opposing jaws, open clearance, cast base, threaded spindle and T-handle replace the old single box. All fit original production envelope. Cast contours and pitting remain simpler than reference. |
| 납골당 천장 석조 아치 (`gothic_voussoir_arch`) | `game.gd::_add_gothic_arch` | Continuous dark curved arch retained; production rise/span lower than concept and side/top texture projection is striped. |
| 천장 녹슨 사슬 (`hanging_chain`) | `game.gd::_add_hanging_chain` | Alternating oval links intact with dark iron; gameplay links much finer and longer than concept's short heavy chain. |
| 던전 폐석 더미 (`dungeon_rubble`) | `game.gd::_add_rubble_cluster` | Chipped dark rubble pieces intact, with original loose placement; edge damage less deep than concept. |
| 바닥 물 반사 자국 (`wet_floor_patch`) | `game.gd::_add_wet_patch` | Irregular subtle dark wet overlay intact; true edge-on views intentionally thin. Concept includes invented stone thickness. |
| 축축한 납골당 벽 (`ossuary_wall`) | `game.gd::_add_visual_box` | Dark staggered masonry and recessed mortar remain visible. Opaque perimeter seals close real room junctions; a recessed core stays beneath the chipped stone. Production arch headers use the same wall family. The concept's decorative ossuary inset is absent from a generic wall. |
| 젖은 판석 바닥 (`wet_flagstone_floor`) | `game.gd::_add_visual_box` | Dark rectangular paving retains the actual floor footprint. Recessed opaque backing and perimeter seals close joined panels without covering the stone surface. Concept uses more irregular polygonal flagstones and finer wet surface detail. |
| 납골당 석조 천장 (`crypt_ceiling`) | `game.gd::_add_visual_box` | Dark ceiling and underside ribs remain visible, with a recessed opaque core and closed perimeter. The production central-hall wall-to-ceiling seam is sealed. Ribs are thinner than concept; true horizontal projection is retained. |
| 부서진 제단 (`broken_altar`) | `game.gd::_add_visual_box` | Mouldings, corner piers and circular relief present in dark stone; carving and edge wear remain simpler than generated concept. |
| 원정 야영 모닥불 (`campfire`) | `camp_visuals.gd::create_camp` | Final correction verified: flame starts on the logs through warmth and flicker, and generated coal grain, fissures and charred ends are readable under warm light. Ring remains dark stone. Fire/log/ring silhouettes are simpler than the concept. |
| 야영 침낭 (`camp_bedroll`) | `camp_visuals.gd::create_camp` | Folded pad, rolled end, straps and closed seams intact in darker cloth. Gameplay bedroll lies horizontally; generated reference camera labels imply a different orientation. |
| 고기 굽는 꼬챙이 (`roasting_spit`) | `camp_visuals.gd::create_camp + set_cooking` | Dark irregular charred roast pieces now replace the smooth red spheres. Real support, shaft and progress-driven turning remain intact. Fine carving, roast ties and reference's continuous joint remain simpler. |
| 버섯 수프 냄비 (`mushroom_soup_pot`) | `camp_visuals.gd::create_camp + set_cooking` | Final correction verified: dark cauldron and existing feet/handles/spoon intact. Sixteen visible sliced mushrooms, herbs and subtle broth variation replace a nearly empty flat surface. Ingredient detail remains simpler than concept. |
| 행군 스튜 냄비 (`trail_stew_pot`) | `camp_visuals.gd::create_camp + set_cooking` | Final correction verified: dense dark stew morsels and herbs sit within the rim over subtly varied broth. Dark cauldron and production feet/handles/spoon retained; food detail remains simpler than concept. |
| 요리 수증기 (`cooking_steam`) | `camp_visuals.gd::create_camp + set_cooking` | Soft wisps visible from all directions. Repeating billboard wisps lack reference's volumetric top/underside curl; transparent field has no hard matte. |
