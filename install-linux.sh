#!/bin/sh

VFAT_SIZE=128 # in Mb
MOUNT_DIR=mnt
ROOTFS_FIND=boot
HOSTNAME_WILDCARD=hostname*
ROOTFS_WILDCARD=*rootfs*
KERNEL_WILDCARD=?Image*
DEVTREE_WILDCARD=*.dtb
MODULES_WILDCARD=modules*
UDEV_WILDCARD=*.rules

# Make sure only root can run our script
if [ "$(id -u)" != 0 ]; then
   echo "This script must be run as root"
   exit 1
fi

# Print usage
if [ "$#" -eq 0 ];  then
    echo "usage: `basename $0` BLOCK-DEVICE [INSTALL-BOOTLOADER]"
    echo "  BLOCK-DEVICE is the block device to write to"
    echo "  INSTALL-BOOTLOADER is the shell script to install the bootloader"
    exit 1
fi

# Check first argument is a block device
if [ ! -b "$1" ]; then
    echo "$1 is not a block device"
    exit 1
fi
BLOCK_DEV=$1

# Check second argument is not empty
if [ "$2" ]; then
    INSTALL_BOOTLOADER=$2
fi

# Check block device is a disk
block_type=`lsblk -nr $BLOCK_DEV | awk 'NR == 1 {print $6}'`
if [ "$block_type" != "disk" ]; then
    echo "$BLOCK_DEV is not a disk"
    exit 1
fi

# Check block device is a storage medium
block_size=`sfdisk -s $BLOCK_DEV 2>/dev/null`
if [ -z "$block_size" ]; then
    echo "No medium found on $BLOCK_DEV"
    exit 1
fi

# Check block device is not mounted
block_mounted=`mount | grep $BLOCK_DEV`
if [ "$block_mounted" ]; then
    echo "$BLOCK_DEV is already mounted, please unmount it"
    exit 1
fi

# Check presence of Linux kernel
linux_kernel=`ls $KERNEL_WILDCARD 2>/dev/null`
if [ -z "$linux_kernel" ]; then
    echo "Linux kernel is missing, please add one"
    exit 1
fi

# Check presence of device tree
device_tree=`ls $DEVTREE_WILDCARD 2>/dev/null`
if [ -z "$device_tree" ]; then
    echo "Device tree is missing, please add one"
    exit 1
fi

# Check presence of one root file system
rootfs=`ls $ROOTFS_WILDCARD 2>/dev/null`
rootfs_num=`echo $rootfs | wc -w`
if [ "$rootfs_num" -eq 0 ]; then
    echo "Root file system is missing, please add one"
    exit 1
elif [ "$rootfs_num" -ge 2 ]; then
    echo "Several root file systems, only one is allowed"
    exit 1
fi

# Ask for user confirmation to program block device
echo
echo -n "All existing data on $BLOCK_DEV will be deleted, do you want to continue? [y/n] "
read answer
answer_yes=`echo $answer | grep -e ^[Yy][Ee][Ss]$ -e ^[Yy]$`
if [ ! "$answer_yes" ]; then
    echo "Operation aborted"
    exit 1
fi

echo "Operation confirmed, performing installation"
echo

# Erase current partition table
dd if=/dev/zero of=$BLOCK_DEV bs=1M count=16 status=none

# Create 2 partitions: vfat (VFAT_SIZE) and Linux (remaining)
echo "Creating vfat and Linux partitions on $BLOCK_DEV"
sfdisk -uS --force $BLOCK_DEV >/dev/null 2>&1 << EOF
2048,$(($VFAT_SIZE*2048)),c
$(((1+$VFAT_SIZE)*2048)),;
EOF

# Get partitions names
partition_suffix=`lsblk -nr $BLOCK_DEV | awk 'FNR == 2 {print $1}' | sed 's/.$//'`
vfat_partition=/dev/$partition_suffix\1
linux_partition=/dev/$partition_suffix\2

# Format vfat partition
echo "Formating $vfat_partition with vfat"
mkfs.vfat -F 32 $vfat_partition >/dev/null 2>&1

# Format Linux partition
echo "Formating $linux_partition with ext4"
mkfs_version=`mkfs.ext4 -V 2>&1 | awk 'NR == 1 {print $2}' | grep -o ^[0-9]*.[0-9]*`
if ! echo $mkfs_version | awk '{ exit ($1 <= 1.42)}'; then
    mkfs.ext4 -F $linux_partition >/dev/null 2>&1
else
    mkfs.ext4 -F -O ^metadata_csum,^64bit $linux_partition >/dev/null 2>&1
fi

# Create mount dir
mkdir -p $MOUNT_DIR

# Mount Linux partition
echo
echo "Mounting $linux_partition"
mount $linux_partition $MOUNT_DIR

# Extract root file system
echo "Extracting `basename $rootfs`"
tar xf $rootfs -C $MOUNT_DIR --warning=no-timestamp

# Move root file system to Linux partition root
rootfs_dir=`find $MOUNT_DIR -type d -name $ROOTFS_FIND`
rootfs_dir=${rootfs_dir#$MOUNT_DIR/}
rootfs_dir=${rootfs_dir%$ROOTFS_FIND}
if [ "$rootfs_dir" ]; then
    mv $MOUNT_DIR/$rootfs_dir* $MOUNT_DIR
    rm -rf $MOUNT_DIR/$rootfs_dir
fi

# Set partitions mounting
filename=$MOUNT_DIR/etc/fstab
fstab_root="UUID=$(blkid -o value -s UUID $linux_partition) / ext4 noatime 0 1"
fstab_boot="UUID=$(blkid -o value -s UUID $vfat_partition) /boot vfat noatime 0 1"
echo $fstab_root > $filename
echo $fstab_boot >> $filename

# Set hostname
hostname=`cat $HOSTNAME_WILDCARD 2>/dev/null`
hostname=`echo $hostname | awk '{print $1}'`
filename=$MOUNT_DIR/etc/hostname
if [ "$hostname" ]; then
    echo "Setting hostname to $hostname"
    echo $hostname > $filename
fi

# Install kernel modules
kernel_modules=`ls $MODULES_WILDCARD 2>/dev/null`
for i in $kernel_modules; do
    echo "Extracting `basename $i`"
    tar xf $i -C $MOUNT_DIR --warning=no-timestamp
done

# Install udev rule
udev_rule=`ls $UDEV_WILDCARD 2>/dev/null`
for i in $udev_rule; do
    echo "Copying `basename $i`"
    cp $i $MOUNT_DIR/etc/udev/rules.d/
done

# Unmout Linux partition
echo "Unmounting $linux_partition"
umount $MOUNT_DIR

# Mount vfat partition
echo
echo "Mounting $vfat_partition"
mount $vfat_partition $MOUNT_DIR

# Copy all data
for i in `find . -maxdepth 1 ! -type d ! -name .gitignore ! -name LICENSE ! -name README.md`; do
    echo "Copying `basename $i`"
    cp $i $MOUNT_DIR
done

# Unmout vfat partition
echo "Unmounting $vfat_partition"
umount $MOUNT_DIR

# Delete mount dir
rmdir $MOUNT_DIR 2>/dev/null

# Install Bootloader
if [ -n "$INSTALL_BOOTLOADER" ]; then
    echo
    echo "Installing Bootloader"
    ./$INSTALL_BOOTLOADER $BLOCK_DEV
fi

echo
echo "Linux is installed on $BLOCK_DEV"
echo
