#!/usr/bin/env bash

die() {
	echo "[31m$@[0m" >&2
	exit 1
}

# Templates live next to this script's siblings and may call them.
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export script_dir

eval_template() {
	test -f "$1" || die "No such file: $1"
	# A heredoc keeps quotes and other literal characters intact while still
	# expanding $(...) and $variables. The old eval/echo version ate the
	# quotes out of CONFIG_CMDLINE="...".
	eval "cat <<__TEMPLATE_EOF__
$(<"$1")
__TEMPLATE_EOF__"
}

if test "$#" -gt 0; then
	for f in "$@"; do
		eval_template "$f"
	done
else
	eval_template /dev/stdin
fi
