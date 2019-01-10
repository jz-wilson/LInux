#!/bin/bash
#? To create a root LVM_based Ubuntu Image AMI
# * Reference:
# * https://help.ubuntu.com/lts/installation-guide/amd64/apds04.html

export DEBIAN_FRONTEND=noninteractive

set -o errexit

# Variables
DEVICE_SUFFIX='xvdb' # Default when attached on launch
DEVICE="/dev/${DEVICE_SUFFIX}"
VOLUME_GROUP_NAME='vg'
DEVICE1="/dev/${DEVICE_SUFFIX}1"
DEVICE2="/dev/${DEVICE_SUFFIX}2"
UBUNTU_IMAGE='https://cloud-images.ubuntu.com/releases/18.04/release/ubuntu-18.04-server-cloudimg-amd64.tar.gz'

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
	echo "${RED}Volume is not attached! Please attach it first, then re-run this script! ${NC}"
	exit 1
fi

# Partition EBS volume
sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' <<EOF | fdisk "${DEVICE}"
  o # clear the in memory partition table
  n # new partition
  p # primary partition
  1 # partition number 1
    # default - start at beginning of disk
  +1024M
  a # make a partition bootable
    n # new partition
  p # primary partition
  2 # partition number 2
    # default - start of next available on disk
    # default - end of disk
  w # write the partition table
EOF

mkdir -p '/mnt/boot/'
mkfs.ext4 "${DEVICE1}" -L cloudimg-boot >/dev/null
mount "${DEVICE1}" '/mnt/boot/'

# Initialize EBS volume for use by LVM
echo -e "${CYAN}Creating partition physical volume: ${DEVICE2} for use by LVM ${NC}\\n"
pvcreate "${DEVICE2}" >/dev/null

# Create a volume group
echo -e "${CYAN}Creating volume group: ${VOLUME_GROUP_NAME} on ${DEVICE2} ${NC}\\n"
vgcreate "${VOLUME_GROUP_NAME}" "${DEVICE2}" >/dev/null

declare -a LOGICAL_VOLUMES=(
	'var' 'home' 'log' 'opt' 'root' 'tmp' 'usr'
)

for LG in "${LOGICAL_VOLUMES[@]}"; do
	LOGICAL_VOLUME_PATH="/dev/mapper/vg-${LG}"
	echo -e "${YELLOW}Setting up Logical Volume: ${LG} ${NC}"
	# Create a logical volumes
	echo -e "Creating logical volume"
	if [ "${LG}" = 'home' ] || [ "${LG}" = 'opt' ] || [ "${LG}" = 'tmp' ]; then
		lvcreate -L 1G -n "${LG}" "${VOLUME_GROUP_NAME}" >/dev/null
	elif [ "${LG}" = 'usr' ]; then
		lvcreate -L 4G -n "${LG}" "${VOLUME_GROUP_NAME}" >/dev/null
	else
		lvcreate -L 2G -n "${LG}" "${VOLUME_GROUP_NAME}" >/dev/null
	fi

	# Format logical volume
	echo -e "Formatting logical volume"
	mkfs.xfs "${LOGICAL_VOLUME_PATH}" -f >/dev/null

	# Create mount location and mount logical volume
	echo -e "Creating logical volumes mount directory"
	if [ "${LG}" = 'log' ]; then
		MOUNT_PATH="/mnt/var/${LG}"
		mkdir -p "${MOUNT_PATH}"
		mount "${LOGICAL_VOLUME_PATH}" "${MOUNT_PATH}"
	elif [ "${LG}" = 'root' ]; then
		MOUNT_PATH="/mnt/"
		mkdir -p "${MOUNT_PATH}"
		mount "${LOGICAL_VOLUME_PATH}" "${MOUNT_PATH}"
	else
		MOUNT_PATH="/mnt/${LG}"
		mkdir -p "${MOUNT_PATH}"
		mount "${LOGICAL_VOLUME_PATH}" "${MOUNT_PATH}"
	fi
	echo -e "${GREEN}Logical Volume setup complete! ${NC}\\n\\n"
done

# Download Ubuntu 18.04 and mount to /mnt
echo -e "${CYAN}Downloading Ubuntu... ${NC}\\n"
curl ${UBUNTU_IMAGE} -o '/tmp/ubuntu-18.04-server-cloudimg-amd64.tar.gz' >/dev/null
tar -C /tmp -xzf /tmp/ubuntu-18.04-server-cloudimg-amd64.tar.gz
mkdir -p /tmp/work
mount -o loop /tmp/bionic-server-cloudimg-amd64.img /tmp/work
rsync -ahp /tmp/work/ /mnt
echo -e "${GREEN}Ubuntu is now mounted into /mnt ${NC}\\n"

# Mounting dev so we can see the LMV VG's
echo -e "${CYAN}Mounting Bullshit...${NC}\\n"
mount -o bind /dev/ /mnt/dev

# Configure /etc/fstab
cat <<<'/dev/mapper/vg-root /              xfs     defaults        0       1
# /boot was on /dev/sda1 during installation
LABEL=cloudimg-boot /boot          ext4    defaults        0       2
/dev/mapper/vg-home /home          xfs     nodev,nosuid,noexec 0       2
/dev/mapper/vg-opt /opt            xfs     nodev,nosuid    0       2
/dev/mapper/vg-tmp /tmp            xfs     nodev,nosuid    0       2
/dev/mapper/vg-usr /usr            xfs     nodev           0       2
/dev/mapper/vg-var /var            xfs     nodev,nosuid    0       2
/dev/mapper/vg-log /var/log        xfs     nodev,nosuid,noexec 0       2
proc             /proc         proc    defaults                 0    0
sysfs              /sys          sysfs   defaults                 0    0
' >/mnt/etc/fstab

# Start chroot
echo -e "${CYAN}Run chroot commands in /mnt ${NC}\\n"
mount -o bind /dev/ /mnt/dev
# Mount Partitions from /etc/fstab
chroot /mnt mount -a

# Copy over overwritten dirs from mount action
rsync -ahp /tmp/work/ /mnt

# Configure /etc/fstab
cat <<<'/dev/mapper/vg-root /              xfs     defaults        0       1
# /boot was on /dev/sda1 during installation
LABEL=cloudimg-boot /boot          ext4    defaults        0       2
/dev/mapper/vg-home /home          xfs     nodev,nosuid,noexec 0       2
/dev/mapper/vg-opt /opt            xfs     nodev,nosuid    0       2
/dev/mapper/vg-tmp /tmp            xfs     nodev,nosuid    0       2
/dev/mapper/vg-usr /usr            xfs     nodev           0       2
/dev/mapper/vg-var /var            xfs     nodev,nosuid    0       2
/dev/mapper/vg-log /var/log        xfs     nodev,nosuid,noexec 0       2
proc             /proc         proc    defaults                 0    0
sysfs              /sys          sysfs   defaults                 0    0
' >/mnt/etc/fstab
mount -o bind /dev/ /mnt/dev

# Use local resolv.conf to make sure we can use DNS
rm /mnt/etc/resolv.conf
cp /etc/resolv.conf /mnt/etc/resolv.conf

cat <<EOF | chroot /mnt /bin/bash
mount -t proc none /proc
mount -t sysfs none /sys
# Install Grub and Update it
grub-install ${DEVICE}
grub-mkconfig ${DEVICE} -o /boot/grub/grub.cfg
# Run Updates
export DEBIAN_FRONTEND=noninteractive
apt update
apt full-upgrade -yqq
# Enable ENA Driver
apt-get upgrade -yqq linux-aws
apt autoremove -yqq
EOF

# Suspend LVM for File Consistency
echo -e "${CYAN}Suspending LVM...${NC}"
dmsetup suspend /dev/vg/*

echo -e "${GREEN}LVM Partitioning complete, you may now create a snapshot of this instance! ${NC}"
