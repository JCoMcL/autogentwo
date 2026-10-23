#!/usr/bin/env sh

die() {
	echo "[31m$@[0m" >&2
	exit 1
}

curr_dir() {
	CDPATH= cd -- "$(dirname -- "$0")" && pwd
}
export PATH="$(curr_dir):$PATH"

eval_template() {
	test -f "$1" || die "No such file: $1"
	eval "cat <<__TEMPLATE_EOF__
$(cat "$1")
__TEMPLATE_EOF__"
}

if test "$#" -gt 0; then
	for f in "$@"; do
		eval_template "$f"
	done
else
	eval_template /dev/stdin
fi
