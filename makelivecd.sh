#!/bin/bash
set -ex

export MIRROR="${MIRROR:-https://mirror.pkgbuild.com}"
export MIRROR_AARCH64="${MIRROR_AARCH64:-https://ftp.halifax.rwth-aachen.de/archlinux-arm}"
export MIRROR_DUP="${MIRROR_DUP:-5}"
export LIVECD_PROFILE="${LIVECD_PROFILE:-ultralite}"
echo "using profile ${LIVECD_PROFILE}"
source "config-${LIVECD_PROFILE}"
[[ "$ISO_ARCH" == "aarch64" ]] && MIRROR="$MIRROR_AARCH64"
echo "using mirror ${MIRROR}, MIRROR_DUP=${MIRROR_DUP}"

configure_archbootstrap_x86_64() {
    ISO_DIR="iso/latest"
    SHA256SUM="${MIRROR}/${ISO_DIR}/sha256sums.txt"
    curl -o sha256sum "$SHA256SUM"
    sha256=$(cat sha256sum |grep -F '.tar.gz' |grep -Fv 'archlinux-bootstrap-x86_64.tar')
    bootstrap_tarball=$(awk '{print $2;}' <<< "$sha256")
    echo "$sha256" > sha256sum
    echo "$bootstrap_tarball" |python3 -c 'print(input().split("-")[2])' > version
    curl -o "$bootstrap_tarball" "${MIRROR}/${ISO_DIR}/${bootstrap_tarball}"
    sha256sum -c sha256sum
    tar xzf "$bootstrap_tarball"
}
configure_archbootstrap_aarch64() {
    ISO_DIR="os"
    MD5SUM="${MIRROR}/${ISO_DIR}/ArchLinuxARM-aarch64-latest.tar.gz.md5"
    curl -o md5sum "$MD5SUM"
    md5=$(cat md5sum |grep -F '.tar.gz')
    bootstrap_tarball=$(awk '{print $2;}' <<< "$md5")
    echo "$md5" > md5sum
    date '+%Y-%m-01' > version
    curl -o "$bootstrap_tarball" "${MIRROR}/${ISO_DIR}/${bootstrap_tarball}"
    md5sum -c md5sum
    mkdir root.x86_64
    ln -s root.x86_64 root.aarch64
    tar xzf "$bootstrap_tarball" -C root.x86_64
    cp /usr/bin/qemu-aarch64-static root.x86_64/usr/bin/
    cp contrib/arch-chroot root.x86_64/usr/bin/
    chmod +x root.x86_64/usr/bin/arch-chroot
}

arch-chroot() {
    cp -av $0 ./root.x86_64/$0
    cp -av "config-${LIVECD_PROFILE}" ./root.x86_64/"config-${LIVECD_PROFILE}"
    cp -av version ./root.x86_64/version
    cp -av custom ./root.x86_64/custom
    mount --bind root.x86_64 root.x86_64
    ./root.x86_64/bin/arch-chroot ./root.x86_64 bash "/${0}"
    umount root.x86_64 || true
}

makelivecd() {
    cd /
    source "/config-${LIVECD_PROFILE}"
    [[ "$ISO_ARCH" == "x86_64" ]] && {
        for _ in $(seq ${MIRROR_DUP}); do
            echo 'Server = '"$MIRROR"'/$repo/os/$arch'
        done > /etc/pacman.d/mirrorlist
        pacman-key --init
        pacman-key --populate archlinux
        pacman --noconfirm --needed -Sy archlinux-keyring
        pacman --noconfirm --needed -Syu base base-devel python archiso
    }
    [[ "$ISO_ARCH" == "aarch64" ]] && {
        for _ in $(seq ${MIRROR_DUP}); do
            echo 'Server = '"$MIRROR"'/$arch/$repo'
        done > /etc/pacman.d/mirrorlist
        pacman-key --init
        pacman-key --populate archlinuxarm
        pacman --noconfirm --needed -Sy archlinuxarm-keyring
        rm -fv /usr/bin/arch-chroot
        pacman --noconfirm --needed -Syu base base-devel python \
            dosfstools mtools squashfs-tools arch-install-scripts libisoburn

        curl -Lo aarch64.tar.gz "https://github.com/archlinux-jerry/archiso-aarch64/archive/aarch64.tar.gz"
        tar -xvf aarch64.tar.gz
        rm -rf /usr/share/archiso/
        cp -rv archiso-aarch64-aarch64 /usr/share/archiso
        cp /usr/share/archiso/archiso/mkarchiso /usr/bin/mkarchiso
        chmod +x /usr/bin/mkarchiso
        pushd /usr/share/archiso/configs/releng
            mv packages.aarch64 packages.x86_64
            ln -s packages.x86_64 packages.aarch64
        popd
    }

    # make sure patches apply
    /custom/patches/archiso_pxe_http.hook/patch.sh

    mkdir -p livecd
    cd livecd
    cp -r /usr/share/archiso/configs/releng releng
    cp -r /usr/share/archiso/configs/releng releng.1
    cd releng

    pre_build

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
        sha256sum *.iso > sha256sums.txt
        b2sum *.iso > b2sums.txt
        cat md5sums.txt sha1sums.txt sha256sums.txt b2sums.txt
    popd
    # copy netboot content
    cp -av work/iso/arch "upload/${realver}/"
    [[ "$ISO_ARCH" == "aarch64" ]] && mcopy -snv -i "work/efiboot.img" "::/arch/boot" "upload/${realver}/arch/"
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

if [ -e '/makelivecd.sh' ]; then
    makelivecd
    finalize
else
    configure_archbootstrap_${ISO_ARCH}
    arch-chroot
fi
exit 0
