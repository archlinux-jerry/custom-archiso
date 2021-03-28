#!/bin/bash
set -ex

configure_archbootstrap() {
    MIRROR="https://pkgbuild.meson.cc"
    ISO_DIR="iso/latest"
    MD5SUM="${MIRROR}/${ISO_DIR}/md5sums.txt"
    curl -o md5sum "$MD5SUM"
    md5=$(cat md5sum |grep -F '.tar.gz')
    bootstrap_tarball=$(awk '{print $2;}' <<< "$md5")
    echo "$md5" > md5sum
    echo "$bootstrap_tarball" |python3 -c 'print(input().split("-")[2])' > version
    curl -o "$bootstrap_tarball" "${MIRROR}/${ISO_DIR}/${bootstrap_tarball}"
    md5sum -c md5sum
    tar xzf "$bootstrap_tarball"
}
arch-chroot() {
    cp -av $0 ./root.x86_64/$0
    cp -av version ./root.x86_64/version
    mount --bind root.x86_64 root.x86_64
    ./root.x86_64/bin/arch-chroot ./root.x86_64 bash "/${0}"
}

remove_dead_link() {
python - $@ << EOF
from pathlib import Path
from sys import argv
for f in Path(argv[-2]).rglob('*'):
    if f.is_symlink():
        if f.resolve().exists():
            pass
        elif (Path(argv[-1]).resolve() / (f.resolve().relative_to('/'))).exists():
            pass
        else:
            print('rm', str(f))
            f.unlink()
EOF
}

makelivecd() {
    cd /
    echo 'Server = https://pkgbuild.meson.cc/$repo/os/$arch' > /etc/pacman.d/mirrorlist
    pacman-key --init
    pacman-key --populate archlinux
    pacman --noconfirm --needed -Syu base base-devel archiso python
    mkdir -p livecd
    cd livecd
    cp -r /usr/share/archiso/configs/releng releng
    cp -r /usr/share/archiso/configs/releng releng.1
    cd releng
    # drop speech from sdboot, just forget about syslinux
    rm -f efiboot/loader/entries/archiso-x86_64-speech-linux.conf
    # drop ucode from loader
    sed -i '/ucode\.img/d' efiboot/loader/entries/*.conf
    sed -i 's|^INITRD .*$|INITRD /%INSTALL_DIR%/boot/x86_64/initramfs-linux.img|g' syslinux/*.cfg
    # not using customize_airootfs.sh
    {
        sed -i 's|/usr/bin/zsh|/bin/bash|g' airootfs/etc/passwd
        [ "$(cat airootfs/etc/shadow)" == 'root::14871::::::' ]
        remove_dead_link airootfs/etc/systemd/system airootfs
    }
    # alter packages
    # compat: https://gitlab.archlinux.org/archlinux/archiso/-/blob/e43017c955ab9e3d6394098e49fe588bd848d3e2/configs/releng/packages.x86_64
    cat << EOF >> packages.x86_64
nano
bash-completion
EOF
    cat << EOF > packages.x86_64.remove
b43-fwcutter
bind-tools
broadcom-wl
clonezilla
crda
darkhttpd
ddrescue
dhclient
edk2-shell
efibootmgr
fsarchiver
grml-zsh-config
hdparm
ipw2100-fw
ipw2200-fw
iwd
kitty-terminfo
lftp
linux-firmware
lynx
man-db
man-pages
mc
memtest86+
ndisc6
nmap
nvme-cli
openconnect
openvpn
partclone
parted
partimage
pptpclient
reflector
rsync
rxvt-unicode-terminfo
sdparm
sg3_utils
smartmontools
systemd-resolvconf
tcpdump
terminus-font
termite-terminfo
testdisk
usb_modeswitch
usbutils
vim
vpnc
wireless-regdb
wireless_tools
wpa_supplicant
xl2tpd
zsh
amd-ucode
intel-ucode
alsa-utils
brltty
espeakup
fatresize
gpart
livecd-sounds
squashfs-tools
tmux
udftools
cloud-init
usbmuxd
sof-firmware
EOF
    cat packages.x86_64 |sort |uniq > packages.x86_64.dedup
    cat packages.x86_64.dedup packages.x86_64.remove packages.x86_64.remove |sort |uniq -u > packages.x86_64.final
    mv -f packages.x86_64.final packages.x86_64
    rm packages.x86_64.remove packages.x86_64.dedup
    # print diff
    {
        pushd ..
        diff -r releng.1 releng || true
        popd
    }
    mkarchiso -v .
}
finalize() {
    mkdir upload
    pushd out
        ls -alh || true
        realver=$(ls -1 *.iso |python3 -c 'print(input().split("-")[1])')
    popd
    ver=$(cat /version)
    mkdir "upload/${realver}"
    pushd upload
        ln -s "$realver" "$ver"
        ln -s "$realver" "latest"
    popd
    # move iso
    mv out/*.iso "upload/${realver}/"
    pushd "upload/${realver}"
        md5sum *.iso > md5sums.txt
        sha1sum *.iso > sha1sums.txt
    popd
    # copy netboot content
    cp -av work/iso/arch "upload/${realver}/"
    # makelink /archlinux/iso -> ../
    mkdir upload/archlinux
    # generic archlinux mirror structure
    pushd upload/archlinux
        ln -s .. iso
    popd
    # mirror.pkgbuild.com structure
    pushd upload
        ln -s . iso
    popd
}

if [ -e '/etc/debian_version' ]; then
    configure_archbootstrap
    arch-chroot
elif [ -e '/etc/arch-release' ]; then
    makelivecd
    finalize
else
    exit 1
fi
exit 0
