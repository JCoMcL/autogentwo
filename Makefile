GENTOO_ARCH=amd64
#TODO this whole Makefile thing just doesn't really work at all. Just use a script

.PHONY: update
update:
	mkdir -p etc
	rsync --exclude-from=portage.exclude -r /etc/portage/ etc/portage
	rsync -r /etc/kernel/ etc/kernel
	rsync -r /etc/sysctl.d/ etc/sysctl.d
	rsync -r /etc/udev etc/udev
	cp /var/lib/portage/world world

.PHONY: /mnt/gentoo/etc
/mnt/gentoo/etc: stage3.tar.xz
	#tar xpvf $< --xattrs-include='*.*' --numeric-owner --overwrite -C /mnt/gentoo >/dev/null
	rsync -r etc/ $@
	scripts/templ.sh $@
	cp --no-target-directory --dereference -r /etc/resolv.conf $@/resolv.conf
	cp world /mnt/gentoo/var/lib/portage/world
	scripts/genfstab.sh /mnt/gentoo > /mnt/gentoo/etc/fstab

stage3.tar.xz:
	scripts/download-files.sh "http://distfiles.gentoo.org/releases/$(GENTOO_ARCH)/autobuilds/current-stage3-$(GENTOO_ARCH)-openrc" asc xz sha256
	ls *.asc | grep -v *.tar.xz | xargs rm -f # remove any .asc files that don't have a corresponding .tar.xz file
	gpg --verify stage3-$(GENTOO_ARCH)-openrc-*.tar.xz.asc
	sha256sum --check stage3-$(GENTOO_ARCH)-openrc-*.tar.xz.sha256
	ln -sf stage3-$(GENTOO_ARCH)-openrc-*.tar.xz $@

.PHONY: gentoo-gpg-keys
gentoo-gpg-keys:
	if ls /usr/share/openpgp-keys/gentoo-release.asc; \
	then gpg --import /usr/share/openpgp-keys/gentoo-release.asc; \
	else gpg --keyserver hkps://keys.gentoo.org --recv-keys; \
	fi

.PHONY: clean
clean:
	rm -f stage3*.tar.xz
	rm -f stage3*.tar.xz.asc
	rm -f stage3*.tar.xz.sha256

