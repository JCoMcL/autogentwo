#!/usr/bin/env sh

assert() {
	if $@
	then echo [0m[32m$@ passed[0m
	else echo [0m[31m$@ failed[0m
	fi
}
nassert() {
	if ! $@
	then echo [0m[32m$@ passed[0m
	else echo [0m[31m$@ failed[0m
	fi
}

cd $(dirname $(which $0))
. ./templ.sh < /dev/null

assert is_template "config file.templ"
assert is_template "file.conf..templ"
assert is_template ".templ.templ"
nassert is_template ".templ"
nassert is_template "file.conf.temp"
nassert is_template "file.conf.template"
