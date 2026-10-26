#!/usr/bin/env sh

set -x
emerge --sync || emerge-webrsync
emerge --update sys-devel/mold dev-util/ccache dev-vcs/git
emaint sync --repo jortage
emaint sync --repo guru
emerge --update =go-1.26.2::jortage
emerge --update @world
