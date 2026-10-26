#!/usr/bin/env sh

# Set up the jcomcl account: zsh, groups, doas, tty1 autologin, dotfiles.
error() {
	echo [0m[31m$@[0m >&2
}

warn() {
	echo [1m[34m"$@"[0m >&2
}

die() {
	error $@
	exit 1
}

USERNAME=jcomcl
DOTFILES=https://github.com/jcomcl/dotfiles.git

useradd --create-home --user-group --shell=/bin/zsh "$USERNAME"

# Every admin/permission group worth having. Omits the root-equivalent ones
# (disk mem kmem shadow tty), which would bypass doas entirely.
USER_GROUPS="wheel adm admin audio pipewire video input render lp lpadmin kvm usb cdrom cdrw plugdev netdev scanner dialout portage users uucp tape floppy android cuse sgx"

set -x
for g in $USER_GROUPS; do
	usermod $USERNAME --append --groups $g
done
set +x

if command -v doas; then set -x
	echo "permit nopass $USERNAME" >>/etc/doas.conf.new
	chown root:root /etc/doas.conf.new
	chmod 0400 /etc/doas.conf.new
	doas -C /etc/doas.conf.new || die "/etc/doas.conf.new rejected by doas -C"

	if test -f /etc/doas.conf &&
	! diff /etc/doas.conf /etc/doas.conf.new # `! diff` = files DO differ
		then mv /etc/doas.conf /etc/doas.conf.old
	fi

	mv /etc/doas.conf.new /etc/doas.conf

	ln -sfn doas /usr/bin/sudo

	set +x
elif command -v sudo; then
	warn "currently no sudo support"
	# note whether the system uses "admin" "adm" or "wheel" needs to be figured out
fi

if test -f /etc/inittab; then
	sed -i -E "s|(^c1:.*/sbin/agetty)(.*[[:space:]]tty1[[:space:]])|\1 --autologin $USERNAME\2|" \
	/etc/inittab
	grep -E "[[:space:]]tty1[[:space:]]" /etc/inittab
fi

if command -v yadm; then
	su - "$USERNAME" -s /bin/sh -c "yadm clone --no-bootstrap $DOTFILES"
	su - "$USERNAME" -s /bin/sh -c 'yadm submodule update --init --recursive'
fi

passwd "$USERNAME"
