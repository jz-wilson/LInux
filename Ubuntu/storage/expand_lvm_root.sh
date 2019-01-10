#!/bin/bash
#? Expand the root volume of an AWS EBS Volume

export DEBIAN_FRONTEND=noninteractive

set -o errexit

# Variables
DEVICE_SUFFIX='xvda' # Default AWS EBS Volume Root
DEVICE="/dev/${DEVICE_SUFFIX}"
VOLUME_GROUP_NAME='vg'
LOGICAL_VOLUME='/dev/mapper/vg-var'
SIZE_INCREASE='20G'

# Make it Pretty :)
YELLOW='\e[93m'
GREEN='\e[32m'
CYAN='\e[36m'
RED='\e[31m'
NC='\e[0m' # No Color

# Make sure volume is attached
if test -b ${DEVICE}; then
	echo "${GREEN}Volume is attached! ${NC}"
else
	echo "${RED}Volume is not attached! Please confirm volume, then re-run this script! ${NC}"
	exit 1
fi

# Partition EBS volume
sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' <<EOF | fdisk "${DEVICE}"
  n # new partition
  p # primary partition
    # partition number - Default to next available number)
    # default - start at beginning of disk
  +1024M
  t # make a partition bootable
  8e # partition type - Linux LVM 
  w # write the partition table
EOF

# Make sure we can find the partition
partprobe

# Create physical volume
LATEST_PV=$(fdisk -l $DEVICE | grep '^/dev' | cut -d' ' -f1 | sort -r | head -n1)
n=${LATEST_PV##*[!0-9]}; p=${LATEST_PV%%$n}
NEXT_PV=$p$((n+1))
pvcreate $NEXT_PV

# Extend volume group with latest physical volume
vgextend $VOLUME_GROUP_NAME $NEXT_PV

# Extend logical volume with new storage!
lvextend -L+$SIZE_INCREASE $LOGICAL_VOLUME
xfs_growfs $LOGICAL_VOLUME