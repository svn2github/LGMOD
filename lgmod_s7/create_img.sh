#!/bin/bash
# lgmod rootfs image creation script
# Originally written for OpenLGTV_BCM by xeros
# Modified for lgmod by hawkeye
# Modified for Saturn6/Saturn7 by mmm4m5m

S6=''; [ "$1" = S6 ] && { shift; S6=1; }; [ "$1" = S7 ] && shift
mksquashfs_bin=../pack/mksquashfs
mkepk_bin=../pack/mkepk
cd ${0%/*}
[ -f "$mksquashfs_bin" ] || { echo "ERROR: $mksquashfs_bin not found."; exit 1; }
[ -d trunk/rootfs ] || { echo 'ERROR: trunk/rootfs not found.'; exit 2; }

if [ -n "$S6" ]; then
	LGMOD_PLATFORM=S6
	LGMOD_VERSION="1.6.10"
	LGMOD_VERSION_EPK="37501"
	LGMOD_VERSION_ROOTFS="10610"
	size=1572864
	LGMOD_EXTROOT=`cat ./extroot.s6 | grep -v '^ *$\|^#'` # extroot for S6
else
	LGMOD_PLATFORM=S7
	LGMOD_VERSION="1.0.10"
	LGMOD_VERSION_EPK="30333"
	LGMOD_VERSION_ROOTFS="10010"
	size=7340032
	oinit=mtd4_lg-init
	sysmap=../Saturn7/linux-2.6.26-saturn7/System.map; # for modules.dep (relative path!)
	LGMOD_EXTROOT=`cat ./extroot.s7 | grep -v '^ *$\|^#'` # extroot for S7
fi
LGMOD_VER_TEXT="$LGMOD_PLATFORM $LGMOD_VERSION"
LGMOD_VER_FILE="${LGMOD_PLATFORM}_$LGMOD_VERSION_ROOTFS"
ofile=lgmod_$LGMOD_VER_FILE
ofext=lgmod_${LGMOD_PLATFORM}_extroot.tar.gz

rm -rf squashfs-init squashfs-root extroot-img $ofext $ofile.pak $ofile.epk $ofile.zip $ofile.sh.zip
#rm -rf $oinit.sqfs $ofile.sqfs


cp -r --preserve=timestamps trunk/rootfs-common squashfs-root || exit 5; # base rootfs-common
if [ -n "$S6" ]; then
	cp -r --preserve=timestamps trunk/rootfs-S6/* squashfs-root || exit 11; # merge rootfs-S6
else
	cp -r --preserve=timestamps trunk/lginit squashfs-init || exit 21
	find squashfs-init -name '.svn' | xargs rm -rf
	for i in squashfs-init/lginit; do
		sed -i -e "s/ver=/$LGMOD_VER_TEXT/g" $i; done
	$mksquashfs_bin squashfs-init $oinit.sqfs -le -all-root -noappend -b 524288 || exit 22
	rm -rf squashfs-init

	cp -r --preserve=timestamps trunk/rootfs/* squashfs-root || exit 23; # merge rootfs-S7
fi


# extroot
if [ -d extroot ]; then
	cp -r --preserve=timestamps extroot extroot-img || exit 24
	rm -f extroot-img/*.tar.gz; fi

# split extroot
if [ -n "$S6" ]; then
	rm -rf extroot-img/lib/modules*; # TODO
	IFS=$'\n'; for i in $LGMOD_EXTROOT; do
		mkdir -p extroot-img/${i%/*} && mv squashfs-root/$i extroot-img/${i%/*}/ || exit 26; done
else
	mkdir -p extroot-img/bin
	for i in free kill pgrep pkill pmap sysctl top uptime watch; do i=bin/$i
		mv squashfs-root/$i extroot-img/$i || exit 25
		ln -s busybox squashfs-root/$i; done
	IFS=$'\n'; for i in $LGMOD_EXTROOT; do
		mkdir -p extroot-img/${i%/*} && mv squashfs-root/$i extroot-img/${i%/*}/ || exit 26; done
fi
(cd extroot-img; tar czf ../$ofext *)


find squashfs-root -name '.svn' | xargs rm -rf
cd squashfs-root
for i in dev dev-lgmod etc_passwd; do i=$i.tar; g=$i.gz; b=$i.bz2
	[ -f $g ] && tar xzf $g; [ -f $b ] && tar xjf $b; rm -f $b $g; done
echo $LGMOD_VER_TEXT > var/www/cgi-bin/version
for i in etc/init.d/rcS etc/init.d/lgmod var/www/cgi-bin/footer.inc var/www/cgi-bin/header.inc; do
	sed -i -e "s/ver=/$LGMOD_VER_TEXT/g" $i; done
if [ -f "../$sysmap" ]; then
	D=tmp-depmod; d=lib/modules; v=2.6.26
	mkdir -p $D/$d; ln -s "$(pwd)/lib/modules" $D/$d/$v
	mv $d/$v $D/$v; ln -s "$(pwd)/../extroot-img" mnt/lg/user/extroot
	depmod -n -e -F "../$sysmap" -C <(echo search .) -b $D $v | grep '\.ko:' > $d/modules.dep
	cp -ax $d/modules.dep ../; mv $D/$v $d/$v; rm -rf mnt/lg/user/extroot $D
fi
cd ..
$mksquashfs_bin squashfs-root $ofile.sqfs -le -all-root -noappend -b 1048576 || exit 6

osize=`stat -c%s $ofile.sqfs`; o4096=$(( $osize / 4096 * 4096 ))
echo "Size: $osize / $size"
if [ "$osize" -gt "$size" ]; then
	echo "ERROR: Partition image too big for flashing ($osize - $size = $(( osize-size )))."; exit 3; fi
if [ "$osize" != "$o4096" ]; then
	echo "ERROR: Partition image is not multiple of 4096 ($osize / $o4096)."; exit 4; fi
[ "$1" = test ] || rm -rf extroot-img squashfs-root


zip -j $ofile.zip changelog.txt
if [ -n "$S6" ]; then
	$mkepk_bin -c $ofile.pak $ofile.sqfs root DVB-SATURN6 0x$LGMOD_VERSION_ROOTFS `date +%Y%m%d` RELEASE
	$mkepk_bin -m 0x$LGMOD_VERSION_EPK HE_DTV_GP_M_AAAAABAA $ofile.epk $ofile.pak
	zip -j $ofile.zip $ofile.epk; #$ofile.pak
	rm -f $ofile.pak; #$ofile.epk $ofile.sqfs
else
	#$mkepk_bin -c $ofile.pak $ofile.sqfs root DVB-SATURN 0x$LGMOD_VERSION_ROOTFS `date +%Y%m%d` RELEASE
	#$mkepk_bin -m 0x$LGMOD_VERSION_EPK HE_DTV_GP2M_AAAAABAA $ofile.epk $ofile.pak

	md5sum $oinit.sqfs > $oinit.sqfs.md5; md5sum $ofile.sqfs > $ofile.sqfs.md5
	zip -j $ofile.zip install.sh $oinit.sqfs $oinit.sqfs.md5 $ofile.sqfs $ofile.sqfs.md5
	rm -f $oinit.sqfs.md5 $ofile.sqfs.md5; #$oinit.sqfs $ofile.sqfs
	[ -f lgmod_S7_uImage ] && zip -j $ofile.zip lgmod_S7_uImage

	cat extract.sh $ofile.zip > $ofile.sh.zip
	rm -f $ofile.zip
fi
