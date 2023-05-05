#!/bin/bash
set -o errexit

# source ./scripts/lib.sh
root_fs="/dev/root"
boot_fs="/boot"
backup_dir="/media/backup"
img_file="${backup_dir}/raspi_os_$(date "+%Y-%m-%d").img"
device=""
loopdevice=""
mode="local"  #LOCAL or USB_Storage

mountr=/media/backup_root
mountb=/media/backup_boot

interactive_env(){
    ENV1="test"
    echo -n "please input ENV1 value(default is $ENV1):"
    read input_value
    if [ ! "$input_value" == "" ];then
        ENV1=$input_value
    fi
    echo "ENV1 is $ENV1"
}

perpare(){
    sudo apt-get -y install rsync dosfstools parted kpartx
    if [ ! -d "$backup_dir" ];then
    mkdir -p $backup_dir
    echo "exec: mkdir -p $backup_dir"
    fi
}

print_help() {
    echo "Usage:"
    echo "sudo ./Raspi-OS_backup.sh -r [rootfs tag] -b [boot part mount tag]" 
    echo "info: root_fs default is /dev/root & boot_fs default is /boot"
}

img_file_make() {
    echo "new img_file make start..."
    if [ -f "${img_file}" ];then
    sudo rm ${img_file}
    echo "exec: rm ${img_file}"
    fi

    bootsz=$(df -P | grep "${boot_fs}" | awk '{print $2}')
    rootsz=$(df -P | grep "${root_fs}" | awk '{print $3}')
    totalsz=$(echo $bootsz $rootsz | awk '{print int(($1+$2)*1.3)}')
    sudo dd if=/dev/zero of=$img_file bs=1K count=$totalsz
    echo "img_file size is $totalsz"
    echo "make done!"
}

img_file_parted() {
    echo "img_file parted start..."
    bootstart=$(sudo fdisk -l /dev/mmcblk0 | grep mmcblk0p1 | awk '{print $2}')
    bootend=$(sudo fdisk -l /dev/mmcblk0 | grep mmcblk0p1 | awk '{print $3}')
    rootstart=$(sudo fdisk -l /dev/mmcblk0 | grep mmcblk0p2 | awk '{print $2}')
    
    echo "boot: $bootstart >>> $bootend, root: $rootstart >>> end"
    
    rootend=$(sudo fdisk -l /dev/mmcblk0 | grep mmcblk0p2 | awk '{print $3}')
    sudo parted $img_file --script -- mklabel msdos
    sudo parted $img_file --script -- mkpart primary fat32 ${bootstart}s ${bootend}s
    sudo parted $img_file --script -- mkpart primary ext4 ${rootstart}s -1
    echo "parted done!"
}

img_file_format() {
    echo "img_file format start..."
    loopdevice=$(sudo losetup -f --show $img_file)
    device=/dev/mapper/$(sudo kpartx -va $loopdevice | sed -E 's/.*(loop[0-9])p.*/\1/g' | head -1)
    sleep 5
    sudo mkfs.vfat ${device}p1 -n boot
    sudo mkfs.ext4 ${device}p2
    echo "format done!"
}

boot_copy() {
    echo "boot files copy..."

    mkdir -p $mountb

    sudo mount -t vfat ${device}p1 $mountb
    sudo cp -rfp /boot/* $mountb
    sync 
    sudo umount $mountb
    echo "boot files copy done!"
}

rootfs_rsync() {
    echo "rootfs rsync start..."

    mkdir -p $mountr
    sudo mount -t ext4 ${device}p2 $mountr

    if [ -f /etc/dphys-swapfile ]; then
        SWAPFILE=`cat /etc/dphys-swapfile | grep CONF_SWAPFILE | cut -f 2 -d=`
        if [ "$SWAPFILE" = "" ]; then
            SWAPFILE=/var/swap
        fi
        EXCLUDE_SWAPFILE="--exclude $SWAPFILE"
    fi

    sudo rsync --force -rltWDEgopt --delete --stats --progress\
    $EXCLUDE_SWAPFILE \
    --exclude '.gvfs' \
    --exclude '/dev' \
    --exclude '/media' \
    --exclude '/mnt*' \
    --exclude '/proc' \
    --exclude '/run' \
    --exclude '/sys' \
    --exclude '/tmp' \
    --exclude '/var/cache' \
    --exclude '/lost\+found' \
    --exclude '${backup_dir}' \
    --exclude '${mountr}' \
    --exclude '${mountb}' \
    // $mountr

    for i in dev media mnt proc run sys boot; do
        if [ ! -d $mountr/$i ]; then
            sudo mkdir $mountr/$i
        fi
    done
    if [ ! -d $mountr/tmp ]; then
        sudo mkdir $mountr/tmp
        sudo chmod a+w $mountr/tmp
    fi

    sudo rm -f $mountr/etc/udev/rules.d/70-persistent-net.rules
    sync

    sudo umount $mountr
    # umount loop device
    sudo kpartx -d $loopdevice
    sudo losetup -d $loopdevice
    # sudo umount $usbmount
    rm -rf $mountb $mountr
    echo "rootfs rsync done!"
}

#main function for build
main() {

#set env variables
perpare
# if [ $# -eq 0 ]; then
# 	print_help
# 	exit 1
# fi

#parse command arguments
while getopts r:b:i:m:h option
do
 case "${option}"
 in
 r) root_fs=${OPTARG};;
 b) boot_fs=${OPTARG};;
 m) mode=${OPTARG};;
 h) print_help && exit 0;;
 *) print_help && exit 0;;
 esac
done

img_file_make
img_file_parted
img_file_format
boot_copy
rootfs_rsync
    echo "backup is finished."

}

main $@