#!/bin/bash
set -ex

export MIRROR="${MIRROR:-https://mirror.pkgbuild.com}"
export MIRROR_DUP="${MIRROR_DUP:-5}"
export LIVECD_PROFILE="${LIVECD_PROFILE:-ultralite}"
echo "using mirror ${MIRROR}, MIRROR_DUP=${MIRROR_DUP}"
echo "using profile ${LIVECD_PROFILE}"

configure_archbootstrap() {
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
    cp -av "config-${LIVECD_PROFILE}" ./root.x86_64/"config-${LIVECD_PROFILE}"
    cp -av version ./root.x86_64/version
    cp -av custom ./root.x86_64/custom
    mount --bind root.x86_64 root.x86_64
    ./root.x86_64/bin/arch-chroot ./root.x86_64 bash "/${0}"
    umount root.x86_64 || true
}

makelivecd() {
    cd /
    for _ in $(seq ${MIRROR_DUP}); do
        echo 'Server = '"$MIRROR"'/$repo/os/$arch'
    done > /etc/pacman.d/mirrorlist
    pacman-key --init
    pacman-key --populate archlinux
    pacman --noconfirm --needed -Syu base base-devel archiso python

    # make sure patches apply
    /custom/patches/archiso_pxe_http.hook/patch.sh

    mkdir -p livecd
    cd livecd
    cp -r /usr/share/archiso/configs/releng releng
    cp -r /usr/share/archiso/configs/releng releng.1
    cd releng

    source "/config-${LIVECD_PROFILE}"
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
        cat md5sums.txt sha1sums.txt
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

if [ -e '/makelivecd.sh' ]; then
    makelivecd
    finalize
else
    configure_archbootstrap
    arch-chroot
fi
exit 0
