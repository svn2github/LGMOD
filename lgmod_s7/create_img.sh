#!/bin/bash
# lgmod rootfs image creation script
# Originally written for OpenLGTV_BCM by xeros
# Modified for lgmod by hawkeye
# Modified for lgmod S7 by mmm4m5m
LGMOD_VERSION="1.0.09"
LGMOD_VERSION_EPK="30333"
LGMOD_VERSION_ROOTFS="10009"
mkepk_bin=../pack/mkepk
mksquashfs_bin=../pack/mksquashfs

dir=trunk/rootfs
size=7340032
cd ${0%/*}
if [ ! -f "$mksquashfs_bin" ]
then
    echo "ERROR: mksquashfs not found."
    exit 1
elif [ ! -d "$dir" ]
then
    echo "ERROR: $dir not found."
    exit 1
fi

rm -r squashfs-root
cp -r --preserve=timestamps $dir squashfs-root
cd squashfs-root
tar xzf dev.tar.gz
tar xzf dev-lgmod.tar.gz
tar xvzf etc_passwd.tar.gz
rm -f etc_passwd.tar.gz
find . -name '.svn' | xargs rm -rf
cd ..

echo $LGMOD_VERSION > ./squashfs-root/var/www/cgi-bin/version
sed -i -e "s/ver=/S7 $LGMOD_VERSION/g" ./squashfs-root/var/www/cgi-bin/footer.inc
sed -i -e "s/ver=/S7 $LGMOD_VERSION/g" ./squashfs-root/var/www/cgi-bin/header.inc
sed -i -e "s/ver=/S7 $LGMOD_VERSION/g" ./squashfs-root/etc/lgmod.sh
sed -i -e "s/ver=/S7 $LGMOD_VERSION/g" ./squashfs-root/etc/init.d/lgmod

ofile=lgmod_S7_$LGMOD_VERSION_ROOTFS
rm -f $ofile.pak $ofile.sqfs $ofile.epk $ofile.zip

$mksquashfs_bin squashfs-root $ofile.sqfs -le -all-root -noappend
md5sum $ofile.sqfs > $ofile.sqfs.md5
osize=`wc -c $ofile.sqfs | awk '{print $1}'`
o4096=$(( $osize / 4096 * 4096 ))

if [ "$osize" -gt "$size" ]
then
    echo "ERROR: Partition image too big for flashing."
    rm -f $ofile.sqfs
    rm -rf squashfs-root
    exit 1
elif [ "$osize" != "$o4096" ]
then
    echo "ERROR: Partition image is not multiple of 4096."
    rm -f $ofile.sqfs
    rm -rf squashfs-root
    exit 4
elif [ "$1" == 'pak' ] || [ "$1" == 'epk' ]
then
    $mkepk_bin -c $ofile.pak $ofile.sqfs root DVB-SATURN 0x$LGMOD_VERSION_ROOTFS `date +%Y%m%d` RELEASE
    $mkepk_bin -m 0x$LGMOD_VERSION_EPK HE_DTV_GP2M_AAAAABAA $ofile.epk $ofile.pak
    zip -j $ofile.zip $ofile.pak $ofile.epk
    rm -f $ofile.pak
    mv $ofile.epk ../
fi
md5sum mtd4_lg-init.sqfs > mtd4_lg-init.sqfs.md5
zip -j $ofile.zip $ofile.sqfs* mtd4_lg-init.sqfs* changelog.txt install.sh squashfs-root/bin/busybox
rm -rf $ofile.sqfs.md5 mtd4_lg-init.sqfs.md5 squashfs-root
mv $ofile.sqfs $ofile.zip ../
