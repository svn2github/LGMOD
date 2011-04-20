#!/bin/bash
# OpenLGTV BCM rootfs image creation script by xeros
mkepk_bin=../../pack/mkepk
size=1572864
dir=trunk/rootfs
ver=`cat $dir/var/www/cgi-bin/version`
cp -r $dir squashfs-root
cd squashfs-root
tar xvjf dev.tar.bz2
tar xvjf etc_passwd.tar.bz2
rm -f dev.tar.bz2 etc_passwd.tar.bz2
find . -name '.svn' | xargs rm -rf
cd ..
ofile=LGMOD-v$ver
rm -f $ofile.pak $ofile.sqfs $ofile.epk $ofile.zip

mksquashfs squashfs-root $ofile.sqfs
osize=`wc -c $ofile.sqfs | awk '{print $1}'`

if [ "$osize" -gt "$size" ]
then
    echo "ERROR: Partition image too big for flashing."
    rm -f $ofile.sqfs
    rm -rf squashfs-root
    exit 1
else
    if [ "$osize" -lt "$size" ]
    then
        $mkepk_bin -c $ofile.pak $ofile.sqfs root DVB-SATURN6 0x$ver `date +%Y%m%d` RELEASE
        $mkepk_bin -m 0x36703 HE_DTV_GP_M_AAAAABAA $ofile.epk $ofile.pak
    fi
fi
zip $ofile.zip $ofile.epk
rm -f $ofile.pak $ofile.sqfs
rm -rf squashfs-root
mv $ofile.zip $ofile.epk ../../
