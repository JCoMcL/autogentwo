#!/usr/bin/env sh

die() {
	echo "[31m$@[0m" >&2
	exit 1
}

eval_template() {
	test -f "$1" || die "No such file: $1"
	eval "echo \"$(<$1)\""
}

if test "$#" -gt 0; then
	for f in "$@"; do
		eval_template "$f"
	done
else
	eval_template /dev/stdin
fi
