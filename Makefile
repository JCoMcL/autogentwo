GENTOO_ARCH=amd64

etc: /etc/portage /etc/kernel
	mkdir -p $@
	rsync -r /etc/portage/ $@/portage || [ $$? -eq 23 ] # "ignore "Partial Transfer" (code: 23) errors, to be expected due to read access.
	rsync -r /etc/kernel/ $@/kernel

etc/portage/package.use/%: templates/%.templ
	scripts/templ.sh $< > $@

etc/portage/make.conf/00-mirrorselect.conf:
	mirrorselect -s3 -o > $@

stage3.tar.xz: gentoo-gpg-keys
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

