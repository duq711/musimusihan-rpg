#!/bin/zsh

# Godot 4.7's macOS embedded bootstrap uses an unhosted CALayer, not NSApp or
# NSWindow. The real renderer can draw SubViewports without desktop activation.
# --debug is required because the embedded driver needs EngineDebugger.
# Source audit: godotengine/godot 4.7-stable, platform/macos/godot_main_macos.mm,
# os_macos.mm, display_server_macos_embedded.mm. Do not replace --embedded with
# --display-driver macos, and do not attach this process to an editor debugger.

set -u
script_dir="${0:A:h}"
project_dir="${script_dir:h}"
godot_executable="${GODOT_EXECUTABLE:-/Users/duq711gmail.com/Desktop/Godot.app/Contents/MacOS/Godot}"
preview_timeout_seconds="${GODOT_PREVIEW_TIMEOUT_SECONDS:-180}"
preview_name="${1:-player_appearance_preview.gd}"
preview_name="${preview_name:t}"

if [[ "$(/usr/bin/uname -s)" != Darwin || ! -x "$godot_executable" ]]; then
	print -u2 -r -- "This safe embedded renderer requires the audited macOS Godot executable."
	exit 2
fi
case "$preview_name" in
	player_appearance_preview.gd) preview_pass_marker='^PLAYER APPEARANCE PREVIEW PASS:' ;;
	performance_preview.gd) preview_pass_marker='^PERFORMANCE PREVIEW PASS:' ;;
	dark_fantasy_scene_preview.gd) preview_pass_marker='^DARK FANTASY SCENE PREVIEW PASS:' ;;
	dark_fantasy_gallery_preview.gd) preview_pass_marker='^DARK FANTASY GALLERY PREVIEW PASS:' ;;
	player_arm_preview.gd) preview_pass_marker='^PLAYER ARM PREVIEW PASS:' ;;
	*)
		print -u2 -r -- "Only reviewed player appearance, arm, gallery, production scene and performance previews are enabled."
		exit 2
		;;
esac
if [[ "$preview_timeout_seconds" != <-> ]] || (( preview_timeout_seconds < 1 )); then
	print -u2 -r -- "GODOT_PREVIEW_TIMEOUT_SECONDS must be a positive integer."
	exit 2
fi
if [[ ! -f "$script_dir/$preview_name" ]]; then
	print -u2 -r -- "Missing reviewed preview: $preview_name"
	exit 2
fi
# Fail closed before the real display bootstrap if the executable was replaced.
# --headless prevents even an unsupported embedded flag from reaching NSApp.
audited_version="4.7.stable.official.5b4e0cb0f"
actual_version="$("$godot_executable" --headless --version 2>/dev/null)"
if [[ "$actual_version" != "$audited_version" ]]; then
	print -u2 -r -- "Embedded preview refused: this executable does not match the audited Godot version."
	exit 2
fi
preview_log="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/codex-player-preview.XXXXXX")"
if [[ -z "$preview_log" || ! -f "$preview_log" ]]; then
	print -u2 -r -- "Could not create the temporary embedded preview log."
	exit 2
fi
preview_pid=""
preview_log_emitted=0
function cleanup_preview_log() {
	[[ -f "$preview_log" ]] && /bin/rm -f -- "$preview_log"
}
function emit_preview_log() {
	if (( ! preview_log_emitted )); then
		/bin/cat "$preview_log"
		preview_log_emitted=1
	fi
}
function preview_log_contains() {
	if (( $+commands[rg] )); then
		rg --quiet -- "$1" "$preview_log"
	else
		/usr/bin/grep -Eq -- "$1" "$preview_log"
	fi
}
function stop_preview() {
	if [[ -n "$preview_pid" ]] && kill -0 "$preview_pid" 2>/dev/null; then
		kill -TERM "$preview_pid" 2>/dev/null || true
		for _attempt in {1..20}; do
			kill -0 "$preview_pid" 2>/dev/null || return
			/bin/sleep 0.1
		done
		kill -KILL "$preview_pid" 2>/dev/null || true
	fi
}
trap 'cleanup_preview_log' EXIT
trap 'stop_preview; emit_preview_log; exit 130' INT
trap 'stop_preview; emit_preview_log; exit 143' TERM
trap 'stop_preview; emit_preview_log; exit 129' HUP

# No interactive environment flag is supplied or evaluated by this harness.
# The production project uses Forward+ / Vulkan; preserve those actual shaders.
preview_rendering_driver="vulkan"
if [[ "$preview_name" == "performance_preview.gd" ]]; then
	preview_rendering_driver="${GODOT_PERFORMANCE_DRIVER:-vulkan}"
	if [[ "$preview_rendering_driver" != "vulkan" && "$preview_rendering_driver" != "metal" ]]; then
		print -u2 -r -- "Performance driver must be the audited embedded vulkan or metal backend."
		exit 2
	fi
fi
runner=("$godot_executable" --embedded --debug --audio-driver Dummy
	--rendering-method forward_plus --rendering-driver "$preview_rendering_driver"
	--disable-crash-handler --path "$project_dir"
	--script "res://tests/$preview_name")
if [[ "$preview_name" == "performance_preview.gd" && "${PERFORMANCE_QA_SCHEDULING:-background}" == "normal" ]]; then
	"${runner[@]}" >"$preview_log" 2>&1 &
elif [[ -x /usr/sbin/taskpolicy ]]; then
	/usr/sbin/taskpolicy -b /usr/bin/nice -n 10 "${runner[@]}" >"$preview_log" 2>&1 &
else
	/usr/bin/nice -n 10 "${runner[@]}" >"$preview_log" 2>&1 &
fi
preview_pid=$!
preview_started_at=$SECONDS
timed_out=0
while kill -0 "$preview_pid" 2>/dev/null; do
	if (( SECONDS - preview_started_at >= preview_timeout_seconds )); then
		timed_out=1
		print -u2 -r -- "Embedded preview timed out after ${preview_timeout_seconds}s."
		stop_preview
		break
	fi
	/bin/sleep 0.25
done
wait "$preview_pid" 2>/dev/null
preview_status=$?
preview_pid=""
emit_preview_log
if (( preview_status != 0 )); then
	print -u2 -r -- "Embedded renderer process exited with status ${preview_status}."
fi
if (( timed_out )); then
	exit 124
fi
# Godot can return zero after a script failed to parse or run. A successful
# capture requires its explicit completion marker and an error-free log.
if preview_log_contains 'SCRIPT ERROR|Failed to load script|Parse Error'; then
	print -u2 -r -- "Embedded preview failed: Godot reported a script error."
	exit 1
fi
if [[ "$preview_name" == "performance_preview.gd" ]] && preview_log_contains '^ERROR:'; then
	print -u2 -r -- "Performance preview failed: Godot reported an engine error."
	exit 1
fi
if ! preview_log_contains "$preview_pass_marker"; then
	print -u2 -r -- "Embedded preview failed: explicit completion marker is missing."
	exit 1
fi
exit "$preview_status"
