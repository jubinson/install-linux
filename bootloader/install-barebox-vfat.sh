#!/bin/sh

MOUNT_DIR=mnt
BLOCK_DEV=$1
SPL=MLO
BOOTLOADER=barebox.bin

partition_suffix=`lsblk -nr $BLOCK_DEV | awk 'FNR == 2 {print $1}' | sed 's/.$//'`
vfat_partition=/dev/$partition_suffix\1

echo "Making $vfat_partition active"
sfdisk $BLOCK_DEV -A 1 2>/dev/null
sleep 1

mkdir $MOUNT_DIR
mount $vfat_partition $MOUNT_DIR
echo "Copying $SPL and $BOOTLOADER to $vfat_partition"
cp $DATA_DIR$SPL $DATA_DIR$BOOTLOADER $MOUNT_DIR
umount $MOUNT_DIR
rmdir $MOUNT_DIR
