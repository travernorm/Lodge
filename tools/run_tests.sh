#!/usr/bin/env bash
# Runs every Lodge check, the same way CI does:
#   1. imports the project
#   2. checks project.godot's input map matches tools/setup_input_map.gd
#   3. runs every tests/*_test.gd headless
# A test fails if it exits non-zero OR prints a script/engine error, because
# Godot can log a broken script and still exit 0.
#
# Usage (repo root):
#   tools/run_tests.sh                  # all tests
#   tools/run_tests.sh playthrough      # only tests whose name contains "playthrough"
# Godot is found from $GODOT, then `godot` on PATH, then the macOS app.
#   GODOT=/path/to/Godot tools/run_tests.sh

set -u
cd "$(dirname "$0")/.."

GODOT="${GODOT:-}"
if [ -z "$GODOT" ]; then
	if command -v godot >/dev/null 2>&1; then
		GODOT=godot
	elif [ -x /Applications/Godot.app/Contents/MacOS/Godot ]; then
		GODOT=/Applications/Godot.app/Contents/MacOS/Godot
	else
		echo "Can't find Godot. Set GODOT=/path/to/godot." >&2
		exit 2
	fi
fi

FILTER="${1:-}"
ERROR_PATTERN='SCRIPT ERROR|Parse Error|^ERROR:|^USER ERROR:'
TIMEOUT_SECS=300
LOG_DIR="$(mktemp -d)"
trap 'rm -rf "$LOG_DIR"' EXIT

run_godot() {
	if command -v timeout >/dev/null 2>&1; then
		timeout "$TIMEOUT_SECS" "$GODOT" --headless --path . "$@"
	else
		"$GODOT" --headless --path . "$@"
	fi
}

failed=()
passed=()

echo "== Import"
run_godot --import >"$LOG_DIR/import.log" 2>&1
if grep -Eq "$ERROR_PATTERN" "$LOG_DIR/import.log"; then
	grep -E "$ERROR_PATTERN" -A2 "$LOG_DIR/import.log"
	failed+=("import")
fi

if [ -z "$FILTER" ]; then
	echo "== Input map matches tools/setup_input_map.gd"
	cp project.godot "$LOG_DIR/project.godot"
	run_godot --script res://tools/setup_input_map.gd >"$LOG_DIR/input_map.log" 2>&1
	if ! cmp -s project.godot "$LOG_DIR/project.godot"; then
		diff "$LOG_DIR/project.godot" project.godot
		echo "project.godot's input map is out of date. Run tools/setup_input_map.gd and commit project.godot." >&2
		failed+=("input map")
	else
		passed+=("input map")
	fi
	cp "$LOG_DIR/project.godot" project.godot
fi

for test in tests/*_test.gd; do
	name="$(basename "$test" .gd)"
	if [ -n "$FILTER" ] && [[ "$name" != *"$FILTER"* ]]; then
		continue
	fi
	echo "== $name"
	log="$LOG_DIR/$name.log"
	run_godot --script "res://$test" >"$log" 2>&1
	code=$?
	if [ $code -ne 0 ] || grep -Eq "$ERROR_PATTERN" "$log"; then
		grep -E "FAIL|FAILED|failed|$ERROR_PATTERN" -A2 "$log" || tail -20 "$log"
		[ $code -ne 0 ] || echo "(exited 0 but printed an error)"
		failed+=("$name")
	else
		tail -1 "$log"
		passed+=("$name")
	fi
done

echo
echo "Passed: ${#passed[@]}  Failed: ${#failed[@]}"
if [ ${#failed[@]} -gt 0 ]; then
	printf '  FAILED  %s\n' "${failed[@]}"
	exit 1
fi
