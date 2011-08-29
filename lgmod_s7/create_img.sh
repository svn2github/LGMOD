#!/bin/bash
# lgmod rootfs image creation script
# Originally written for OpenLGTV_BCM by xeros
# Modified for lgmod by hawkeye
# Modified for lgmod S7 by mmm4m5m
LGMOD_VERSION="1.0.10"
LGMOD_VERSION_EPK="30333"
LGMOD_VERSION_ROOTFS="10010"
ofile=lgmod_S7_$LGMOD_VERSION_ROOTFS
oinit=mtd4_lg-init
size=7340032

mkepk_bin=../pack/mkepk
mksquashfs_bin=../pack/mksquashfs
dir=trunk/rootfs
cd ${0%/*}
if [ ! -f "$mksquashfs_bin" ]; then
    echo "ERROR: mksquashfs not found."; exit 1
elif [ ! -d "$dir" ]; then
    echo "ERROR: $dir not found."; exit 2
fi
rm -r squashfs-init squashfs-root $oinit.sqfs.md5 $ofile.sqfs.md5 $ofile.pak $ofile.epk $ofile.zip
#rm -r $oinit.sqfs $ofile.sqfs

cp -r --preserve=timestamps trunk/lginit squashfs-init
find squashfs-init -name '.svn' | xargs rm -rf
for i in squashfs-init/lginit; do
	sed -i -e "s/ver=/S7 $LGMOD_VERSION/g" $i; done
$mksquashfs_bin squashfs-init $oinit.sqfs -le -all-root -noappend -b 524288

cp -r --preserve=timestamps $dir squashfs-root
find squashfs-root -name '.svn' | xargs rm -rf
cd squashfs-root
for i in dev.tar.gz dev-lgmod.tar.gz etc_passwd.tar.gz; do tar xzf $i; done
rm -f dev.tar.gz dev-lgmod.tar.gz etc_passwd.tar.gz
echo $LGMOD_VERSION > var/www/cgi-bin/version
for i in etc/init.d/rcS etc/init.d/lgmod var/www/cgi-bin/footer.inc var/www/cgi-bin/header.inc; do
	sed -i -e "s/ver=/S7 $LGMOD_VERSION/g" $i; done
cd ..
$mksquashfs_bin squashfs-root $ofile.sqfs -le -all-root -noappend -b 1048576

osize=`wc -c $ofile.sqfs | awk '{print $1}'`
echo "Size: $osize / $size"
o4096=$(( $osize / 4096 * 4096 ))
if [ "$osize" -gt "$size" ]; then
    echo "ERROR: Partition image too big for flashing ($osize / $size)."
    rm -rf squashfs-root $ofile.sqfs
    exit 3
elif [ "$osize" != "$o4096" ]; then
    echo "ERROR: Partition image is not multiple of 4096 ($osize / $o4096)."
    rm -rf squashfs-root $ofile.sqfs
    exit 4
elif [ "$1" == 'pak' ] || [ "$1" == 'epk' ]; then
    $mkepk_bin -c $ofile.pak $ofile.sqfs root DVB-SATURN 0x$LGMOD_VERSION_ROOTFS `date +%Y%m%d` RELEASE
    $mkepk_bin -m 0x$LGMOD_VERSION_EPK HE_DTV_GP2M_AAAAABAA $ofile.epk $ofile.pak
    zip -j $ofile.zip $ofile.pak $ofile.epk
    #mv $ofile.epk ../
    rm -f $ofile.pak $ofile.epk
fi

md5sum $oinit.sqfs > $oinit.sqfs.md5; md5sum $ofile.sqfs > $ofile.sqfs.md5
zip -j $ofile.zip $oinit.sqfs $oinit.sqfs.md5 $ofile.sqfs $ofile.sqfs.md5 changelog.txt install.sh
cat extract.sh $ofile.zip > $ofile.sh.zip
rm -rf squashfs-root squashfs-init $oinit.sqfs.md5 $ofile.sqfs.md5; #$oinit.sqfs $ofile.sqfs
#mv $ofile.zip ../
rm -rf $ofile.zip
