#!/bin/bash
#
# This script transforms a SmartOS USB Image into an OVA 
# <benr@joyent.com>	 - 2/14/14
#

# Tunables:
CPUS=1
RAM=2048		# in MB
ZPOOL_SIZE=40960	# in MB

## A pre-generated ZPOOL means we don't need to do the interactive installation 
##  of SmartOS; but the OVA will break if the MAC address used during that setup
##  doesn't match our MAC address in the new VM; therefore we must set it here:
MAC="080027B7B9DE"


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


## Download SmartOS USB (Raw) Image
printf "\n==> Downloading ${RELEASE}....\n\n"
cd $BASE/smartos_releases
if [[ -f ${FILENAME}.img.bz2 ]]; then
  echo "${FILENAME} already downloaded!"
else
  curl -O https://us-east.manta.joyent.com/Joyent_Dev/public/SmartOS/${URL}
  if [ $? -gt 0 ]; then
    echo "Download failed!  Please check your release string and try again!"
    cd $BASE && rm -r $TMPDIR
    exit 1
  fi
fi


## Convert RAW to VMDK
cd $BASE && mkdir $TMPDIR && cd $TMPDIR

printf "\n==> Uncompressing & Converting Raw to VMDK...\n\n"
bunzip2 --keep -c ../smartos_releases/${FILENAME}.img.bz2 > ${FILENAME}.img
VBoxManage convertfromraw ${FILENAME}.img boot.vmdk --format VMDK


## Create the VM:

printf "\n==> Creating VM\n"
VBoxManage createvm --name "${BOXNAME}" --register
## Get List: 'VBoxManage list ostypes'
VBoxManage modifyvm "${BOXNAME}" --ostype "Solaris11_64"
VBoxManage modifyvm "${BOXNAME}" --memory ${RAM}
VBoxManage modifyvm "${BOXNAME}" --cpus ${CPUS} --pae on --nestedpaging on --vtxvpid on
VBoxManage modifyvm "${BOXNAME}" --mouse ps2 --audio none
VBoxManage modifyvm "${BOXNAME}" --nic1 nat --nictype1 82540EM --macaddress1 ${MAC}
VBoxManage modifyvm "${BOXNAME}" --natpf1 "ssh,tcp,127.0.0.1,2222,,22"
VBoxManage storagectl "${BOXNAME}" --name "SATA Controller" --add sata
VBoxManage storageattach "${BOXNAME}" --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium ./boot.vmdk
VBoxManage storageattach "${BOXNAME}" --storagectl "SATA Controller" --port 1 --device 0 --type dvddrive --medium emptydrive
# Create empty 40G device for Zpool:
#VBoxManage createhd --filename ./zpool.vmdk --size ${ZPOOL_SIZE}
gzcat ../smartos-zpool.vmdk.gz > zpool.vmdk
VBoxManage storageattach "${BOXNAME}" --storagectl "SATA Controller" --port 2 --device 0 --type hdd --medium ./zpool.vmdk

## Package & Delete

printf "\n==> Packaging OVA & Deleting VM\n"
VBoxManage export "${BOXNAME}" --output ../${BOXNAME}.ova
VBoxManage unregistervm "${BOXNAME}" --delete

printf "\nOVA is ready: ${BOXNAME}.ova\n"

## Cleanup
cd $BASE
#rm -r $TMPDIR

END=`date +"%s"`
echo "Completed in $(( $END - $START )) seconds."
