#!/bin/bash

SRC_IMAGE=$1
SRC_TYPE=$2
PRI_KEY=$3
MAKE_DATE=`date +%Y%m%d`
DST_IMAGE=`basename $SRC_IMAGE`

./mksquashfs $SRC_IMAGE $DST_IMAGE.squashfs -noappend -le
./mkepk -c $DST_IMAGE.pak $DST_IMAGE.squashfs boot LGTV 0x0001 $MAKE_DATE RELEASE
./mkepk -m 0x0001 HE_PDP_GP_M_AAAAABAA $DST_IMAGE.epk $DST_IMAGE.pak
rm -f $DST_IMAGE.pak
./imgmake TRUE $DST_IMAGE.epk NULL $MAKE_DATE FALSE $PRI_KEY 
rm -f $DST_IMAGE.epk
