#!/bin/bash
# lgmod rootfs image creation script
# Originally written for OpenLGTV_BCM by xeros
# Modified for lgmod by hawkeye
LGMOD_VERSION="1.6.6"
LGMOD_VERSION_EPK="36906"
LGMOD_VERSION_ROOTFS="10606"
mkepk_bin=../pack/mkepk
mksquashfs_bin=../pack/mksquashfs

size=1572864
dir=trunk/rootfs
rm -r squashfs-root
cp -r $dir squashfs-root
cd squashfs-root
tar xvjf dev.tar.bz2
tar xvjf etc_passwd.tar.bz2
rm -f dev.tar.bz2 etc_passwd.tar.bz2
find . -name '.svn' | xargs rm -rf
cd ..

echo $LGMOD_VERSION > ./squashfs-root/var/www/cgi-bin/version
sed -i -e "s/ver=/$LGMOD_VERSION/g" ./squashfs-root/var/www/cgi-bin/footer.inc
sed -i -e "s/ver=/$LGMOD_VERSION/g" ./squashfs-root/var/www/cgi-bin/header.inc
sed -i -e "s/ver=/$LGMOD_VERSION/g" ./squashfs-root/etc/lgmod.sh

ofile=lgmod_$LGMOD_VERSION_ROOTFS
rm -f $ofile.pak $ofile.sqfs $ofile.epk $ofile.zip

$mksquashfs_bin squashfs-root $ofile.sqfs -le -all-root -noappend
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
        $mkepk_bin -c $ofile.pak $ofile.sqfs root DVB-SATURN6 0x$LGMOD_VERSION_ROOTFS `date +%Y%m%d` RELEASE
        $mkepk_bin -m 0x$LGMOD_VERSION_EPK HE_DTV_GP_M_AAAAABAA $ofile.epk $ofile.pak
    fi
fi
zip $ofile.zip $ofile.epk changelog.txt
rm -f $ofile.pak
rm -rf squashfs-root
mv $ofile.sqfs $ofile.zip $ofile.epk ../
