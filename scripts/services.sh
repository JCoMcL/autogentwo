#!/usr/bin/env sh

add_service() {
	rc-service $1 start
	rc-update add $1 default
}

# neccesary for system function
add_service elogind
add_service dbus
add_service acpid
add_service chronyd

# assume these should be enabled if installed
add_service iwd
add_service bluetooth

# nice to have
add_service sshd
