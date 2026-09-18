#!/usr/bin/env sh
# Set up the jcomcl account: zsh, groups, doas, tty1 autologin, dotfiles.
set -e

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

step() {
	echo [1m:: $@[0m
}

USERNAME=jcomcl
DOTFILES=https://github.com/jcomcl/dotfiles.git

# Every admin/permission group worth having. Omits the root-equivalent ones
# (disk mem kmem shadow tty), which would bypass doas entirely.
USER_GROUPS="wheel audio video input render kvm usb cdrom cdrw plugdev
lpadmin netdev scanner dialout portage pipewire users uucp tape floppy
android cuse sgx"

test "$(id -u)" -eq 0 || die "must run as root"

step "account"
# useradd -G fails the whole call on an unknown group, and early in an install
# half of these don't exist yet (lpadmin ships with cups, pipewire with
# pipewire), so filter to what the system actually has.
SUPP=
for g in $USER_GROUPS; do
	if getent group "$g" >/dev/null; then
		SUPP="$SUPP,$g"
	else
		warn "skipping absent group: $g"
	fi
done

# -U gives a per-user primary group; `users` comes in as a supplementary
useradd -m -U -s /bin/zsh -G "${SUPP#,}" -c "$USERNAME" "$USERNAME"

step "doas"
echo "permit nopass $USERNAME" >/etc/doas.conf
chown root:root /etc/doas.conf
chmod 0400 /etc/doas.conf
doas -C /etc/doas.conf || die "/etc/doas.conf rejected by doas -C"
ln -sfn doas /usr/bin/sudo

step "autologin"
sed -i -E "s|(^c1:.*/sbin/agetty)(.*[[:space:]]tty1[[:space:]])|\1 --autologin $USERNAME\2|" \
	/etc/inittab
grep -E "[[:space:]]tty1[[:space:]]" /etc/inittab

step "dotfiles"
# --no-bootstrap: don't run repo-supplied code unprompted.
su - "$USERNAME" -s /bin/sh -c "yadm clone --no-bootstrap $DOTFILES"
# Submodules are registered but empty after yadm's bare clone, and
# --recurse-submodules on `yadm clone` does not cover them.
su - "$USERNAME" -s /bin/sh -c 'yadm submodule update --init --recursive'

step "password"
passwd "$USERNAME"

step "done"
