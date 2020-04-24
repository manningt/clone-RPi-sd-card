# clone-RPi-sd-card
shell scripts to copy an SD card on a Raspberry Pi.

The script assumes a 32GB or larger SD, and that the master SD (mmcblk0) is the source SD card.

An objective of the script and partitioning scheme was to make cloning an SD card fast (5 minutes) by copying a subset of the data on the card - not the whole card.  Hence the script only copies partions 1 & 2, the boot and linux root files and leaves partitions 3 & 4 empty.

The script uses `parted` (versus `fdisk`) to partition the disk. `parted` creates new UUID's for the partitions, hence `/etc/fstab` and `/boot/cmdline.txt` have to be modified to use the new PARTUUIDs.

The script could be made more general purpose by accepting arguments for the partition sizes and filesystem formats.

TODO: make scripts which save & restore images for the boot & root partitions, instead of copying them from a master SD. 
