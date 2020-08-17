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

makelivecd() {
    cd /
    echo 'Server = https://pkgbuild.meson.cc/$repo/os/$arch' > /etc/pacman.d/mirrorlist
    pacman-key --init
    pacman-key --populate archlinux
    pacman --noconfirm --needed -Syu base base-devel archiso python
    mkdir -p livecd
    cd livecd
    cp -r /usr/share/archiso/configs/releng/ archlive
    cd archlive
    cp build.sh build.sh.1
    sed -i 's/^\(.*shellx64\.efi.*\)$/#\1/g' build.sh # drop efi shell
    sed -i 's/^\(.*ucode\.img.*EFI.*\)$/#\1/g' build.sh # drop ucode
    diff build.sh.1 build.sh
    # drop ucode from loader
    cp -a efiboot/loader/entries efiboot/loader/entries.1
    sed -i '/ucode\.img/d' entries/*.conf
    diff -r efiboot/loader/entries.1 efiboot/loader/entries
    cp -a syslinux syslinux.1
    sed -i 's/^INITRD boot\/intel-ucode.img,boot\/amd-ucode.img,boot\/x86_64\/archiso.img$/INITRD boot\/x86_64\/archiso.img' syslinux/*.cfg
    diff -r syslinux.1 syslinux
    cat << EOF >> airootfs/root/customize_airootfs.sh
chsh -s /bin/bash root
passwd -d root
EOF
    cat << EOF >> packages.x86_64
nano
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
haveged
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
EOF
    cat packages.x86_64 packages.x86_64.remove packages.x86_64.remove |sort |uniq -u > packages.x86_64.final
    mv -f packages.x86_64.final packages.x86_64
    ./build.sh -v
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
    cp -avT work/iso "upload/${realver}/"
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
