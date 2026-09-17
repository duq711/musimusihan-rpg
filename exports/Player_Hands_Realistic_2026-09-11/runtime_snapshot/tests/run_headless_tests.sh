#!/bin/zsh

# Run Godot's automated checks without opening a native window. Tests run one
# at a time and at a reduced macOS scheduling priority so they are less likely
# to disturb other desktop work.

set -u

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
godot_executable="${GODOT_EXECUTABLE:-/Users/duq711gmail.com/Desktop/Godot.app/Contents/MacOS/Godot}"
test_timeout_seconds="${GODOT_TEST_TIMEOUT_SECONDS:-180}"

if [[ ! -x "$godot_executable" ]]; then
	print -u2 -r -- "Godot executable not found: $godot_executable"
	exit 2
fi

if [[ "$test_timeout_seconds" != <-> ]] || (( test_timeout_seconds < 1 )); then
	print -u2 -r -- "GODOT_TEST_TIMEOUT_SECONDS must be a positive integer: $test_timeout_seconds"
	exit 2
fi

current_test_pid=""
current_test_log=""

function cleanup_test_log() {
	if [[ -n "$current_test_log" ]]; then
		/bin/rm -f -- "$current_test_log"
		current_test_log=""
	fi
}

trap cleanup_test_log EXIT

function stop_current_test() {
	local pid="$current_test_pid"
	if [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null; then
		return
	fi
	kill -TERM "$pid" 2>/dev/null || true
	for _attempt in {1..20}; do
		if ! kill -0 "$pid" 2>/dev/null; then
			return
		fi
		/bin/sleep 0.1
	done
	kill -KILL "$pid" 2>/dev/null || true
}

function handle_signal() {
	local signal_name="$1"
	local signal_exit="$2"
	print -u2 -r -- "Validation interrupted by $signal_name. Stopping its current Godot process."
	stop_current_test
	exit "$signal_exit"
}

trap 'handle_signal INT 130' INT
trap 'handle_signal TERM 143' TERM
trap 'handle_signal HUP 129' HUP

typeset -a test_paths

if (( $# == 0 )); then
	test_paths=("$script_dir"/*_test.gd(N))
else
	for requested in "$@"; do
		test_name="${requested##*/}"
		case "$test_name" in
			*_test.gd) ;;
			*_test) test_name="${test_name}.gd" ;;
			*.gd)
				print -u2 -r -- "Only *_test.gd automation scripts are allowed: $requested"
				exit 2
				;;
			*) test_name="${test_name}_test.gd" ;;
		esac
		test_path="$script_dir/$test_name"
		if [[ ! -f "$test_path" ]]; then
			print -u2 -r -- "Test not found: $test_name"
			exit 2
		fi
		test_paths+=("$test_path")
	done
fi

if (( ${#test_paths} == 0 )); then
	print -u2 -r -- "No automated tests found in $script_dir"
	exit 2
fi

typeset -a failed_tests
passed_count=0

for test_path in "${test_paths[@]}"; do
	test_name="${test_path:t}"
	print -r -- "[HEADLESS] $test_name"
	runner=(
		"$godot_executable"
		--headless
		--no-header
		--path "$project_dir"
		--script "res://tests/$test_name"
	)
	current_test_log="$(/usr/bin/mktemp -t sanctuary-headless)"
	if [[ -z "$current_test_log" || ! -f "$current_test_log" ]]; then
		print -u2 -r -- "Could not create a validation log."
		exit 2
	fi
	if [[ -x /usr/sbin/taskpolicy ]]; then
		/usr/sbin/taskpolicy -b /usr/bin/nice -n 10 "${runner[@]}" >"$current_test_log" 2>&1 &
	else
		/usr/bin/nice -n 10 "${runner[@]}" >"$current_test_log" 2>&1 &
	fi
	current_test_pid=$!
	test_started_at=$SECONDS
	timed_out=0
	while kill -0 "$current_test_pid" 2>/dev/null; do
		if (( SECONDS - test_started_at >= test_timeout_seconds )); then
			timed_out=1
			print -u2 -r -- "TIMEOUT after ${test_timeout_seconds}s: $test_name"
			stop_current_test
			break
		fi
		/bin/sleep 0.25
	done
	wait "$current_test_pid" 2>/dev/null
	exit_status=$?
	current_test_pid=""
	if (( timed_out )); then
		exit_status=124
	fi
	/bin/cat "$current_test_log"
	# Godot can return zero when an entry script fails to parse. Such a run
	# never executed its assertions and must not count as a passing test.
	if rg -q 'SCRIPT ERROR:|Failed to load script|Parse Error:' "$current_test_log"; then
		print -u2 -r -- "Script error detected in $test_name, regardless of engine exit status."
		exit_status=1
	fi
	cleanup_test_log
	if (( exit_status == 0 )); then
		(( passed_count += 1 ))
	else
		failed_tests+=("$test_name ($exit_status)")
	fi
done

print -r -- ""
print -r -- "Headless validation: $passed_count passed, ${#failed_tests} failed."

if (( ${#failed_tests} > 0 )); then
	for failed_test in "${failed_tests[@]}"; do
		print -u2 -r -- "FAILED: $failed_test"
	done
	exit 1
fi

exit 0
