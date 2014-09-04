#!/bin/bash
#
# This script transforms a SmartOS USB Image into an OVA 
# <benr@joyent.com>	 - 2/14/14
#

# Tunables:
CPUS=1
RAM=2048		# in MB
ZPOOL_SIZE=40960	# in MB




## Determine release to get
RELEASE=$1
if [[ -z $RELEASE ]]; then
  RELEASE=`curl -s https://us-east.manta.joyent.com//Joyent_Dev/public/SmartOS/latest | cut -d/ -f5`
  echo "    Release image not specified; defaulting to latest (${RELEASE})"
fi

URL="${RELEASE}/smartos-${RELEASE}-USB.img.bz2"
FILENAME="smartos-${RELEASE}-USB"
BOXNAME="smartos-${RELEASE}"

START=`date +"%s"`
BASE=$PWD
TMPDIR="tmp.$$/"

rm -rf $TMPDIR
mkdir $TMPDIR && cd $TMPDIR

## Download SmartOS USB (Raw) Image

printf "\n==> Downloading ${RELEASE}....\n\n"
curl -O https://us-east.manta.joyent.com/Joyent_Dev/public/SmartOS/${URL}
if [ $? -gt 0 ]; then
  echo "Download failed!  Please check your release string and try again!"
  cd $BASE && rm -r $TMPDIR
  exit 1
fi


## Convert RAW to VMDK

printf "\n==> Uncompressing & Converting Raw to VMDK...\n\n"
bunzip2 ${FILENAME}.img.bz2
VBoxManage convertfromraw ${FILENAME}.img boot.vmdk --format VMDK


## Create the VM:

printf "\n==> Creating VM\n"
VBoxManage createvm --name "${BOXNAME}" --register
## Get List: 'VBoxManage list ostypes'
VBoxManage modifyvm "${BOXNAME}" --ostype "Solaris11_64"
VBoxManage modifyvm "${BOXNAME}" --memory ${RAM}
VBoxManage modifyvm "${BOXNAME}" --cpus ${CPUS} --pae on --nestedpaging on --vtxvpid on
VBoxManage modifyvm "${BOXNAME}" --mouse ps2 --audio none
VBoxManage modifyvm "${BOXNAME}" --nic1 nat --nictype1 82540EM
VBoxManage modifyvm "${BOXNAME}" --natpf1 "ssh,tcp,127.0.0.1,2222,,22"
VBoxManage storagectl "${BOXNAME}" --name "SATA Controller" --add sata
VBoxManage storageattach "${BOXNAME}" --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium ./boot.vmdk
VBoxManage storageattach "${BOXNAME}" --storagectl "SATA Controller" --port 1 --device 0 --type dvddrive --medium emptydrive
# Create empty 40G device for Zpool:
VBoxManage createhd --filename ./zpool.vmdk --size ${ZPOOL_SIZE}
VBoxManage storageattach "${BOXNAME}" --storagectl "SATA Controller" --port 2 --device 0 --type hdd --medium ./zpool.vmdk

## Package & Delete

printf "\n==> Packaging OVA & Deleting VM\n"
VBoxManage export "${BOXNAME}" --output ../${BOXNAME}.ova
VBoxManage unregistervm "${BOXNAME}" --delete

printf "\nDone.\n"

## Cleanup
cd $BASE
rm -r $TMPDIR

END=`date +"%s"`
echo "Completed in $(( $END - $START )) seconds."
