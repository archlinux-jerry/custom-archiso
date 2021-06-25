#!/bin/bash
set -ex

# https://gitlab.archlinux.org/archlinux/archiso/-/raw/9c44aeedd182e70194d2b90ca919dcad7ced42b1/archiso/initcpio/hooks/archiso_pxe_http
pacman -S --asdeps --noconfirm --needed mkinitcpio-archiso
cp /usr/lib/initcpio/hooks/archiso_pxe_http $(dirname "$0")/archiso_pxe_http
patch -p0 $(dirname "$0")/archiso_pxe_http < $(dirname "$0")/1.patch

cp -v $(dirname "$0")/archiso_pxe_http $(dirname "$0")/../../rootoverlay/etc/initcpio/hooks/archiso_pxe_http
cat $(dirname "$0")/../../rootoverlay/etc/initcpio/hooks/archiso_pxe_http
