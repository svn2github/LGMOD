#!/bin/sh
# OpenLGTV BCM rootfs image creation script by xeros
size=3145728
dir=OpenLGTV_BCM-src
ver=`cat $dir/etc/ver2`
cp -r $dir squashfs-root
cd squashfs-root
tar xzvf dev.tar.gz
rm -f dev.tar.gz
find . -name '.svn' | xargs rm -rf
cd ..
ofile=OpenLGTV_BCM-v$ver
mksquashfs squashfs-root $ofile.sqf
osize=`wc -c $ofile.sqf | awk '{print $1}'`
if [ "$osize" -gt "$size" ]
then
    echo ERROR: Partition image too big for flashing.
    rm -rf squashfs-root
    exit 1
else
    if [ "$osize" -lt "$size" ]
    then
	for i in `seq $(($size-$osize))`
	do
	    printf "\xff" >> $ofile.sqf
	done
    fi
fi
md5sum $ofile.sqf > $ofile.md5
zip $ofile.zip $ofile.sqf $ofile.md5 install.sh
rm -rf squashfs-root
