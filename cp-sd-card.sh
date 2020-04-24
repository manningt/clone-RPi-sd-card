#!/bin/bash
start=$(date +%s.%N)

# script assumes the following device ID's and the following mount points (dirs) have been created
#    create dirs command: sudo mkdir -p /mnt/boot2
TARGET_SD='sda'
SOURCE_SD='mmcblk0'
BOOT_MOUNT_PATH='/mnt/boot2'
ROOT_MOUNT_PATH='/mnt/root2'
NUM_PARTITIONS=4

echo "Making sd: /dev/${TARGET_SD} using partitions from: /dev/${SOURCE_SD}"
# creates the following 4 partitions leaving spaces for partitions to grow:
#Device        Start      End  Sectors  Size Type
#/dev/sda1      8192   532479   524288  256M Microsoft basic data
#/dev/sda2    532480 17309695 16777216    8G Linux filesystem
# !!Note: there is space between sda2 and sda3 for an 8G, but only using 4G
#/dev/sda3  17309696 25698303  8388608    4G F2FS (flash) or NTFS (mount on Mac) or Linux
#/dev/sda4  25698304 59252735 33554432   16G as above filesystem

do_parted_and_dd=1
# NOTE: cannot use mklabel gpt (global partition table) - RPi doesn't recognize it
if [ $do_parted_and_dd == 1 ]; then
  sudo parted --script /dev/${TARGET_SD} mklabel msdos \
    unit s \
    mkpart primary fat32 8192s 532479s \
    set 1 lba on \
    mkpart primary ext4 532480s 8839167s \
    mkpart primary ntfs 17309696s 25698303s \
    mkpart primary ntfs 25698304s 59252735s

  sync

  echo "Formatting the file systems"
  # options: -f/F force overwrite; -q quiet; -l/L/n label
  sudo mkfs.fat -n "boot" /dev/${TARGET_SD}1
  sudo mkfs.ext4 -Fq -L "root" /dev/${TARGET_SD}2
  sudo mkfs.f2fs -fq -l "data" /dev/${TARGET_SD}3
  sudo mkfs.exfat -q -n "mdata" /dev/${TARGET_SD}4

  echo "Copying the boot partition from /dev/${SOURCE_SD}p1 to /dev/${TARGET_SD}1"
  # could use cat or ddrescue instead; not using dd options: conv=noerror,sync - want to stop on errors
  DD_RC=$(sudo dd if=/dev/${SOURCE_SD}p1 of=/dev/${TARGET_SD}1 bs=1M)
  #echo "boot partition duplicate return info: ${DD_RC}"
  echo "Copying the root partition from /dev/${SOURCE_SD}p2 to /dev/${TARGET_SD}2 - takes 5 minutes"
  DD_RC=$(sudo dd if=/dev/${SOURCE_SD}p2 of=/dev/${TARGET_SD}2 bs=1M)
fi

# get partition ID's for source and target SD cards

# background: the new sd has new PARTUUIDs, so 2 files (/etc/fstab & /boot/cmdline.txt) on the new sd have
#    to be changed to match
# refer to this course material for more background on RPi booting:
#    https://tc.gts3.org/cs3210/2020/spring/lab/lab1.html
# here is an excerpt:
#  These specially-named files are recognized by the Raspberry Pi’s GPU on boot-up and used to configure
#  and boostrap the system. bootcode.bin is the GPU’s first-stage bootloader. Its primary job is to load
#  start.elf, the GPU’s second-stage bootloader. start.elf initializes the ARM CPU, configuring it as
#  indicated in config.txt, loads kernel8.img into memory, and instructs the CPU to start executing the
#  newly loaded code from kernel8.img.

# the following was the first method, which assumes the partition IDs are of the format:
#    306540d6-01, ie 9 characters followed by dash followed by partition number.
#NEW_PARTUUID="$(lsblk -o LABEL,PARTUUID $TARGET_DEV | grep rootfs | sed 's/rootfs //' | sed 's/-02//')"
#PREV_PARTUUID="$(lsblk -o LABEL,PARTUUID $SOURCE_DEV | grep rootfs | sed 's/rootfs //' | sed 's/-02//')"

# the following method of getting the PARTUUID allows each ID to be a completely different format:
NEW_PARTUUID=(0)
PREV_PARTUUID=(0)
PARTITION_NAMES=(0 boot root data mdata)
for (( n=1; n<=NUM_PARTITIONS; n++ ))
do
  NEW_PARTUUID[${n}]="$(lsblk -o PARTUUID /dev/${TARGET_SD}${n} | tail -1)"
  #note: had to use double quotes in sed to expand the varible
  PREV_PARTUUID[${n}]="$(lsblk -o NAME,PARTUUID /dev/${SOURCE_SD} | grep mmcblk0p${n} | sed "s/.*blk0p${n} //")"
done
#echo "New PARTUUID: ${NEW_PARTUUID[@]}"
#echo "Previous PARTUUID: ${PREV_PARTUUID[@]}"

echo "Changing root PARTUUID=${PREV_PARTUUID[2]} in ${BOOT_MOUNT_PATH}/cmdline.txt to ${NEW_PARTUUID[2]}"
sudo mount /dev/${TARGET_SD}1 $BOOT_MOUNT_PATH
if [ -e ${BOOT_MOUNT_PATH}/cmdline.txt ]; then
  sudo mv ${BOOT_MOUNT_PATH}/cmdline.txt ${BOOT_MOUNT_PATH}/cmdline-backup.txt
  sudo bash -c "sed 's/=${PREV_PARTUUID[2]}/=${NEW_PARTUUID[2]}/' ${BOOT_MOUNT_PATH}/cmdline-backup.txt \
   > ${BOOT_MOUNT_PATH}/cmdline.txt"
else
  echo "ERROR: ${BOOT_MOUNT_PATH}/cmdline.txt does not exist!"
fi
sudo umount $BOOT_MOUNT_PATH

sudo mount /dev/${TARGET_SD}2 $ROOT_MOUNT_PATH
if [ -e ${ROOT_MOUNT_PATH}/etc/fstab ]; then
  echo "Modifying PARTUUID in ${ROOT_MOUNT_PATH}/etc/fstab:"
  sudo cp ${ROOT_MOUNT_PATH}/etc/fstab ${ROOT_MOUNT_PATH}/etc/fstab-backup
  for (( n=1; n<=NUM_PARTITIONS; n++ ))
    do
      echo "  Changing ${PARTITION_NAMES[${n}]} PARTUUID=${PREV_PARTUUID[${n}]} to ${NEW_PARTUUID[${n}]}"
      sudo bash -c "sed 's/${PREV_PARTUUID[${n}]}/${NEW_PARTUUID[${n}]}/g' ${ROOT_MOUNT_PATH}/etc/fstab \
       > ${ROOT_MOUNT_PATH}/etc/fstab-tmp"
      sudo mv ${ROOT_MOUNT_PATH}/etc/fstab-tmp ${ROOT_MOUNT_PATH}/etc/fstab
    done
else
  echo "Error: ${ROOT_MOUNT_PATH}/etc/fstab does not exist!"
fi
sudo umount $ROOT_MOUNT_PATH

duration=$(echo "$(date +%s.%N) - $start" | bc)
execution_time=`printf "%.2f seconds." $duration`
echo "Done! Execution time: $execution_time"
