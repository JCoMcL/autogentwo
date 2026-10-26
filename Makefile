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

/mnt/gentoo/etc: stage3.tar.xz /mnt/gentoo/
	#TODO assert /mnt/gentoo is another disk or partition
	tar xpvf $< --xattrs-include='*.*' --numeric-owner --overwrite -C /mnt/gentoo >/dev/null

/mnt/gentoo/etc/hostname: /mnt/gentoo/etc
	rsync -r etc/ $<
	scripts/templ.sh $<
	cp --no-target-directory --dereference -r /etc/resolv.conf $</resolv.conf
	cp world /mnt/gentoo/var/lib/portage/world
	scripts/genfstab.sh /mnt/gentoo > /mnt/gentoo/etc/fstab
	head -1 > $@ # ENTER YOUR NEW HOSTNAME

/mnt/gentoo/root/autogentwo:
	mkdir -p $@
	cp -r . /mnt/gentoo/root/autogentwo

.PHONY: finalize
finalize: /mnt/gentoo/root/autogentwo /mnt/gentoo/etc/hostname
	arch-chroot /mnt/gentoo/ /root/autogentwo/scripts/finalize.sh
	arch-chroot /mnt/gentoo/ /root/autogentwo/scripts/services.sh
	arch-chroot /mnt/gentoo/ /root/autogentwo/scripts/jcomcl.sh

stage3.tar.xz:
	scripts/download-files.sh "http://distfiles.gentoo.org/releases/$(GENTOO_ARCH)/autobuilds/current-stage3-$(GENTOO_ARCH)-openrc" asc xz sha256
	ls *.asc | grep -v *.tar.xz | xargs rm -f # remove any .asc files that don't have a corresponding .tar.xz file
	gpg --verify stage3-$(GENTOO_ARCH)-openrc-*.tar.xz.asc stage3-$(GENTOO_ARCH)-openrc-*.tar.xz
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

