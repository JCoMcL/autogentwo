#!/usr/bin/env sh

die() {
	echo "[31m$@[0m" >&2
	exit 1
}

warn() {
	echo "[0m[34m$@[0m" >&2
}

script_dir() {
	dirname $(which $0)
}

eval_template() {
	local PATH="$(script_dir):$PATH"
	eval "cat <<__TEMPLATE_EOF__
$(cat "$1")
__TEMPLATE_EOF__"
}

is_template() {
	out=${1%.templ*}
	if test -z "$out" || test "$1" = "$out"
	then return 1
	fi
	return 0
}

render_template() {
	if ! is_template "$1"
	then die "$1 does not look like a template"
	fi
	out=${1%.templ*}

	if test -f $out; then
		if test $NO_CLOBBER
		then die $out already exists
		else warn overwriting $out
		fi
	fi
	eval_template "$1" > "$out"
}

render_dir() {
	find "$1" -name '*.templ' | while IFS= read -r templ
	do render_template "$templ"
	done
}

NO_CLOBBER=
if test "$#" -gt 0; then
	for f in "$@"; do
		if test -d "$f"
		then render_dir "$f"
		else render_template "$f"
		fi
	done
else
	eval_template /dev/stdin
fi
