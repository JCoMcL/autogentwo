#!/usr/bin/env sh

die() {
	echo "[31m$@[0m" >&2
	exit 1
}

warn() {
	echo "[0m[34m$@[0m" >&2
}

script_dir() {
	$(dirname $(which $0))
}

eval_template() {
	export PATH="$(script_dir):$PATH"
	eval "cat <<__TEMPLATE_EOF__
$(cat "$1")
__TEMPLATE_EOF__"
}

is_template() {
	case "$1" in
		*.templ)
			;;
		*)
			return 1
	esac
	out=${1%.templ}
	if test -z "$out" || test "$1" = "$out"
	then return 1
	fi
	return 0
}

render_template() {
	out=${1%.templ}
	if ! is_template "$1"
	then die "$1 does not look like a template"
	fi

	if test -f $out; then
		if test NO_CLOBBER
		then die $out already exists
		else warn overwriting $out
		fi
	fi
	eval_template "$1" > "$out"
}

echo $0
NO_CLOBBER=
if test "$#" -gt 0; then

	for f in "$@"; do
		eval_template "$f"
	done
elif test -e /dev/stdin
	then eval_template /dev/stdin
fi
