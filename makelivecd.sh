#!/bin/bash
set -ex

configure_archbootstrap() {
    MIRROR="https://jpn.mirror.pkgbuild.com"
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
    ./root.x86_64/bin/arch-chroot ./root.x86_64 bash $0
}

makelivecd() {
    cd /
    echo 'Server = https://mirror.pkgbuild.com/$repo/os/$arch' > /etc/pacman.d/mirrorlist
    pacman-key --init
    pacman-key --populate archlinux
    pacman --noconfirm --needed -Syu base base-devel archiso
    mkdir -p livecd
    cd livecd
    cp -r /usr/share/archiso/configs/releng/ archlive
    cd archlive
    cat << EOF >> airootfs/root/customize_airootfs.sh
chsh -s /bin/bash root
pacman --noconfirm -Rscn zsh
passwd -d root
sed -i 's/#\(PermitRootLogin \).\+/\1no/' /etc/ssh/sshd_config
EOF
    cat << EOF > packages.x86_64
arch-install-scripts
btrfs-progs
dhcpcd
diffutils
dmraid
dnsmasq
dnsutils
dosfstools
elinks
ethtool
exfat-utils
f2fs-tools
gnu-netcat
gpm
gptfdisk
jfsutils
linux-atm
lsscsi
lvm2
mdadm
mtools
nano
ndisc6
netctl
nfs-utils
nilfs-utils
ntfs-3g
ntp
openssh
ppp
reiserfsprogs
rp-pppoe
sg3_utils
sudo
usb_modeswitch
wget
wvdial
xfsprogs
linux
EOF
    ./build.sh -v
}
finalize() {
    mkdir upload
    pushd out
        ls -alh || true
        realver=$(ls -1 *.iso |python3 -c 'print(input().split("-")[2])')
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
    pushd upload/archlinux
        ln -s .. iso
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
