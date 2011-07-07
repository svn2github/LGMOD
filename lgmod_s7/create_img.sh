#!/bin/bash
# lgmod rootfs image creation script
# Originally written for OpenLGTV_BCM by xeros
# Modified for lgmod by hawkeye
# Modified for S7 by mmm4m5m
LGMOD_VERSION="1.0.01"
LGMOD_VERSION_EPK="37501"
LGMOD_VERSION_ROOTFS="10001"
mkepk_bin=../pack/mkepk
mksquashfs_bin=../pack/mksquashfs

#_org_#size=1572864
dir=trunk/rootfs
#_new_# >>
size=7340032
cd ${0%/*}
if [ ! -f "$mksquashfs_bin" ]
then
    echo "ERROR: mksquashfs not found."
    exit 1
elif [ ! -d "$dir" ]
then
    echo "ERROR: $dir not found."
    #_new-tmp_#exit 1
fi
#_new_# <<

rm -r squashfs-root
cp -r $dir squashfs-root
cd squashfs-root
#_old_#tar xvjf dev.tar.bz2
#_new-tmp_#tar xvjpf dev.tar.bz2
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
#_new_#
o4096=$(( $osize / 4096 * 4096 ))

if [ "$osize" -gt "$size" ]
then
    echo "ERROR: Partition image too big for flashing."
    rm -f $ofile.sqfs
    #_new-tmp_#rm -rf squashfs-root
    exit 1
##__new__## >>
elif [ "$osize" != "$o4096" ]
then
    echo "ERROR: Partition image is not multiple of 4096."
    rm -f $ofile.sqfs
    #_new-tmp_#rm -rf squashfs-root
    exit 4
elif [ "$1" == 'noepk' ] || [ ! -f "$mkepk_bin" ]
then
    [ "$1" == 'noepk' ] || echo "WARNING: mkepk not found."
    #_new-tmp_#zip $ofile.zip $ofile.sqfs changelog.txt
    zip -j $ofile.zip $ofile.sqfs changelog.txt create_img.sh ../busybox-1.18.5/.config squashfs-root/mnt/lgmod/README
    mv $ofile.sqfs $ofile.zip ../
    exit
##__new__## <<
else
    if [ "$osize" -lt "$size" ]
    then
        $mkepk_bin -c $ofile.pak $ofile.sqfs root DVB-SATURN6 0x$LGMOD_VERSION_ROOTFS `date +%Y%m%d` RELEASE
        $mkepk_bin -m 0x$LGMOD_VERSION_EPK HE_DTV_GP_M_AAAAABAA $ofile.epk $ofile.pak
    fi
fi
zip $ofile.zip $ofile.epk changelog.txt
rm -f $ofile.pak
#_new-tmp_#rm -rf squashfs-root
mv $ofile.sqfs $ofile.zip $ofile.epk ../
