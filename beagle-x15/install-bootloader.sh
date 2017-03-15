#!/bin/sh

MOUNT_DIR=mnt
BLOCK_DEV=$1

sfdisk $BLOCK_DEV -A 1
sleep 1

partition_suffix=`lsblk -nr $BLOCK_DEV | awk 'FNR == 2 {print $1}' | sed 's/.$//'`
vfat_partition=/dev/$partition_suffix\1

mkdir $MOUNT_DIR
mount $vfat_partition $MOUNT_DIR
cp MLO $MOUNT_DIR
cp u-boot.img $MOUNT_DIR
umount $MOUNT_DIR
rmdir $MOUNT_DIR
