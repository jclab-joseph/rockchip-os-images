#!/bin/sh

set -ex

# ENV
# - BOARD_DIR
# - ROOTFS_DIR
# - ROOTFS_ADD_SIZE
# - BOOT_ADD_DIR
# - DISK_OUT
# - KERNEL_VER

BOOT_SIZE=256
BOOT_UUID=$(uuidgen)

ROOTFS_SIZE=$(du -sm ${ROOTFS_DIR} | cut -f1)
ROOTFS_SIZE=$(($ROOTFS_SIZE + $ROOTFS_ADD_SIZE))

ROOTFS_OUT=/build/rootfs.ext4

ROOTFS_UUID=5d7fe326-d149-4be7-a57c-b71ed13784c8

mke2fs -L 'rootfs' -U ${ROOTFS_UUID} -N 0 -d "${ROOTFS_DIR}" -m 5 -r 1 -t ext4 "${ROOTFS_OUT}" ${ROOTFS_SIZE}M

DISK_SIZE=$((1 + $BOOT_SIZE + $ROOTFS_SIZE))
dd if=/dev/zero of=${DISK_OUT} bs=1M count=${DISK_SIZE}
dd if=${ROOTFS_OUT} of=${DISK_OUT} bs=1M seek=$((1 + $BOOT_SIZE)) conv=notrunc
rm ${ROOTFS_OUT}

sfdisk ${DISK_OUT} << EOF
label: dos
label-id: 0x13f6526d
device: ${DISK_OUT}
unit: sectors

start=2048, size=524288, type=0c, bootable
start=526336, size=+${ROOTFS_SIZE}M, type=83
EOF

cleanup () {
	umount ${MOUNT_ROOT}/* || true
	umount ${MOUNT_ROOT} || true

	[ -z "${ROOTFS_DEV:-}" ] || losetup -D ${ROOTFS_DEV} || true
	[ -z "${BOOT_DEV:-}" ] || losetup -D ${BOOT_DEV} || true
	
}
trap cleanup EXIT

BOOT_DEV=$(losetup -f ${DISK_OUT} --show -o $((512 * 2048)) --sizelimit $((512 * 524288)))
ROOTFS_DEV=$(losetup -f ${DISK_OUT} --show -o $((512 * 526336)))

mkfs.ext2 -L BOOT -U "${BOOT_UUID}" ${BOOT_DEV}

MOUNT_ROOT=/mnt/rootfs
mkdir -p "${MOUNT_ROOT}"

mount ${ROOTFS_DEV} ${MOUNT_ROOT}
mount ${BOOT_DEV} ${MOUNT_ROOT}/boot
mount --bind /dev ${MOUNT_ROOT}/dev

cp ${BOARD_DIR}/target-setup.sh ${MOUNT_ROOT}/tmp/target-setup.sh
cp tmp-copy/* ${MOUNT_ROOT}/tmp/

cp ${BOARD_DIR}/boot/* ${MOUNT_ROOT}/boot/
mkdir -p ${MOUNT_ROOT}/boot/grub/

sed "s/{ROOTFS_UUID}/${ROOTFS_UUID}/g; s/{KERNEL_VERSION}/${KERNEL_VER}/g" ./board/boot.template/boot.txt > /build/boot.txt
mkimage -A arm64 -T script -C none -n "boot script" -d /build/boot.txt ${MOUNT_ROOT}/boot/boot.scr

cat > ${MOUNT_ROOT}/etc/fstab <<EOF
# <file system> <mount point> <type> <options> <dump> <pass>
UUID=${ROOTFS_UUID} / ext4 errors=remount-ro 0 1
UUID=${BOOT_UUID} /boot ext2 defaults 0 1

EOF

chmod +x ${MOUNT_ROOT}/tmp/target-setup.sh
chroot ${MOUNT_ROOT} /tmp/target-setup.sh

rm -rf ${MOUNT_ROOT}/tmp/*

