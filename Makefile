GENTOO_ARCH=amd64

etc: /etc/portage /etc/kernel /etc/sysctl.d /etc/udev
	mkdir -p $@
	rsync --exclude-from=portage.exclude -r /etc/portage/ $@/portage
	rsync -r /etc/kernel/ $@/kernel
	rsync -r /etc/sysctl.d/ $@/sysctl.d
	rsync -r /etc/udev $@/udev

world: /var/lib/portage/world
	cp /var/lib/portage/world $@

etc/portage/package.use/%: templates/%.templ
	scripts/templ.sh $< > $@

etc/portage/make.conf/00-mirrorselect.conf:
	mirrorselect -s3 -o > $@

/mnt/gentoo/etc: stage3.tar.xz
	tar xpvf $< --xattrs-include='*.*' --numeric-owner -C /mnt/gentoo

/mnt/gentoo/etc/%: etc/% /mnt/gentoo/etc
	rsync -r $< $@

/mnt/gentoo/var/lib/portage/world: world
	cp $< $@

/mnt/gentoo/etc/resolv.conf: /etc/resolv.conf
	cp --no-target-directory --dereference $< $@

/mnt/gentoo/etc/fstab:
	genfstab -U /mnt/gentoo > $@

/mnt/gentoo: \
	/mnt/gentoo/etc/portage/ \
	/mnt/gentoo/etc/kernel/ \
	scripts/templ.sh templates/root-device.config.templ > /mnt/gentoo/etc/kernel/root-device.config #TODO, template invocation should be automatic
	/mnt/gentoo/etc/resolv.conf \
	/mnt/gentoo/var/lib/portage/world \
	/mnt/gentoo/etc/dracut.conf.d \
	/mnt/gentoo/etc/fstab \
	/mnt/gentoo/etc/ccache.conf \
	/mnt/gentoo/etc/locale.gen

stage.tar.xz: gentoo-gpg-keys
	scripts/download-files.sh http://distfiles.gentoo.org/releases/$(GENTOO_ARCH)/autobuilds/current-stage3-$(GENTOO_ARCH)-openrc asc xz sha256
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

