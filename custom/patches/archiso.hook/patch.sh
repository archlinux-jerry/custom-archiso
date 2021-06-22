#!/bin/bash
set -ex

# https://gitlab.archlinux.org/archlinux/archiso/-/raw/9c44aeedd182e70194d2b90ca919dcad7ced42b1/archiso/initcpio/hooks/archiso
patch -p0 /usr/lib/initcpio/hooks/archiso < $(dirname "$0")/1.patch
