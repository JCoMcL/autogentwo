#!/usr/bin/env sh

failures=0

# Each test runs in a subshell so a failed test cannot take the suite with it.
assert() {
	if ( "$@" )
	then printf '\033[0m\033[32m%s passed\033[0m\n' "$*"
	else printf '\033[0m\033[31m%s failed\033[0m\n' "$*"
		failures=$((failures + 1))
	fi
}
nassert() {
	if ! ( "$@" )
	then printf '\033[0m\033[32m%s passed\033[0m\n' "$*"
	else printf '\033[0m\033[31m%s failed\033[0m\n' "$*"
		failures=$((failures + 1))
	fi
}

test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1
templ="$test_dir/templ.sh"
. "$templ" < /dev/null

# End-to-end: templ.sh template > output, the way the Makefile uses it.

t_cli_render() {
	dir=$(mktemp -d) || return 1
	printf 'x=$GREETING\n' >"$dir/x.templ"
	out=$(GREETING=hello "$templ" "$dir/x.templ" 2>/dev/null)
	rm -rf "$dir"
	test "$out" = 'x=hello'
}

t_cli_space_path() {
	dir=$(mktemp -d) || return 1
	printf 'hi\n' >"$dir/a b.templ"
	out=$("$templ" "$dir/a b.templ" 2>/dev/null)
	rm -rf "$dir"
	test "$out" = hi
}

t_cli_stdin() {
	out=$(printf 'stdin\n' | "$templ" 2>/dev/null)
	test "$out" = stdin
}

# Commands in a template must resolve against templ.sh's own directory
# (the Makefile relies on this for $(fs-uuid.sh ...)).
t_cli_sibling_helper() {
	dir=$(mktemp -d) || return 1
	cp "$templ" "$dir/templ.sh"
	printf '#!/bin/sh\necho sibling\n' >"$dir/helper"
	chmod +x "$dir/helper"
	printf 'x=$(helper)\n' >"$dir/x.templ"
	out=$("$dir/templ.sh" "$dir/x.templ" 2>/dev/null)
	rm -rf "$dir"
	test "$out" = 'x=sibling'
}

t_cli_stderr_empty() {
	dir=$(mktemp -d) || return 1
	printf 'hi\n' >"$dir/x.templ"
	err=$("$templ" "$dir/x.templ" 2>&1 >/dev/null)
	rm -rf "$dir"
	test -z "$err"
}

# Sourcing templ.sh must not execute anything or leak into the caller.

t_source_is_quiet() {
	! (cd "$test_dir" && sh -c '. ./templ.sh' </dev/null 2>&1 | grep . )
}

t_source_preserves_path() {
	res=$(cd "$test_dir" && sh -c 'before=$PATH; . ./templ.sh </dev/null >/dev/null 2>&1; test "$PATH" = "$before" && echo same || echo changed')
	test "$res" = same
}

assert t_cli_render
assert t_cli_space_path
assert t_cli_stdin
assert t_cli_sibling_helper
assert t_cli_stderr_empty
assert t_source_is_quiet
assert t_source_preserves_path

assert is_template "config file.templ"
assert is_template "file.conf..templ"
assert is_template ".templ.templ"
nassert is_template ".templ"
nassert is_template "file.conf.temp"
nassert is_template "file.conf.template"

if test "$failures" -gt 0
then
	printf '%s test(s) failed\n' "$failures"
	exit 1
fi
