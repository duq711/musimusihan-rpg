extends SceneTree
const ART := preload("res://scripts/cave_art_direction.gd")
var failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var snapshot := ExpeditionSession.capture_snapshot()
	var mouse := Input.mouse_mode
	var ground: ShaderMaterial = ART.geological_material(true)
	var rock: ShaderMaterial = ART.geological_material(false)
	_check(ground.shader == rock.shader and ground.shader == ART.GEOLOGY, "terrain and loose stones retain the real shared geology shader")
	_check(bool(ground.get_shader_parameter("ground_surface")) and float(ground.get_shader_parameter("fracture_mix")) == 0.0, "actual mine soil takes the uniform zero-fracture path")
	_check(not bool(rock.get_shader_parameter("ground_surface")) and float(rock.get_shader_parameter("fracture_mix")) > 0.0, "actual bedrock keeps its authored fracture photographs and relief")
	for material in [ground, rock]:
		for key in ["albedo_map", "normal_map", "roughness_map", "height_map", "fracture_albedo", "fracture_normal", "concept_grain"]:
			_check(material.get_shader_parameter(key) is Texture2D, "optimization must retain every original photographic texture binding: " + key)
	var code: String = ART.GEOLOGY.code
	_check(code.contains("if (!ground_surface) { height=photograph(height_map,p,w).r; }") and code.contains("if (!ground_surface) {\n  vec3 grain=photograph(concept_grain,p*1.9,w);"), "ground avoids exactly its unused crevice height and concept grain reads")
	_check(code.count("if (fracture_mix != 0.0)") == 2, "zero fracture uniformly skips only fracture albedo and normal sampling")
	_check(code.contains("float macro=noise(world_position*0.28)+0.35*noise(world_position*0.73+4.7);") and code.contains("mix(0.73,1.17,smoothstep(0.2,1.0,macro))"), "macro noise stays active because final color still consumes it")
	_check(code.contains("texture(map,p.zy).rgb*w.x+texture(map,p.xz).rgb*w.y+texture(map,p.xy).rgb*w.z") and not code.contains("textureGrad") and not code.contains("if (w."), "triplanar weights, implicit derivatives and grazing-axis samples stay unchanged")
	_check(code.contains("AO=ground_surface?1.0:mix(0.85,1.0,smoothstep(0.16,0.6,height));") and code.contains("ROUGHNESS=clamp(mix(dry_roughness,wet_roughness,damp)+ (rough-0.5)*0.16,0.19,0.96);"), "surface occlusion and roughness retain their original formulas")
	var rng := RandomNumberGenerator.new()
	rng.seed = 450707
	for sample in range(128):
		var albedo := Vector3(rng.randf(), rng.randf(), rng.randf())
		var fracture := Vector3(rng.randf(), rng.randf(), rng.randf())
		var grain := Vector3(rng.randf(), rng.randf(), rng.randf())
		var normal := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		var fractured_normal := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		# Original zero-weight reads cannot contribute to the output. This
		# exercises arbitrary photograph/normal samples, including negative
		# relief components, without replacing texture derivatives or weights.
		_check(albedo.lerp(fracture, 0.0).lerp(grain, 0.0).is_equal_approx(albedo), "soil color equals the original zero-contribution texture formula")
		_check(normal.lerp(fractured_normal, 0.0).is_equal_approx(normal), "soil relief equals the original zero-contribution fracture formula")
	_check(ExpeditionSession.capture_snapshot() == snapshot and Input.mouse_mode == mouse, "geology checks preserve expedition and input")
	for message in failures:
		push_error(message)
	if failures.is_empty():
		print("CAVE GEOLOGY PERFORMANCE PASS: actual uniform material paths, all photographic bindings, unused ground/zero-fracture reads skipped, unchanged world projection derivatives, macro color, occlusion and roughness")
	quit(0 if failures.is_empty() else 1)


func _check(value: bool, message: String) -> void:
	if not value and not failures.has(message):
		failures.append(message)
