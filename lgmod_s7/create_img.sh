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
else
	LGMOD_PLATFORM=S7
	LGMOD_VERSION="1.0.10"
	LGMOD_VERSION_EPK="30333"
	LGMOD_VERSION_ROOTFS="10010"
	size=7340032
	oinit=mtd4_lg-init
fi
LGMOD_VER_TEXT="$LGMOD_PLATFORM $LGMOD_VERSION"
LGMOD_VER_FILE="${LGMOD_PLATFORM}_$LGMOD_VERSION_ROOTFS"
ofile=lgmod_$LGMOD_VER_FILE
ofext=lgmod_${LGMOD_PLATFORM}_extroot.tar.gz

rm -rf squashfs-init squashfs-root extroot-img $ofext $ofile.pak $ofile.epk $ofile.zip $ofile.sh.zip
#rm -rf $oinit.sqfs $ofile.sqfs


# TODO: update svn rootfs-common
D=trunk/rootfs-common; rm -rf $D; mkdir $D
for i in  etc/dropbear etc/init.d etc/mtab etc/network etc/openrelease etc/auth.sh etc/environment etc/group \
	etc/hosts etc/inittab etc/profile etc/resolv.conf etc/securetty etc/shadow etc/termcap etc/TZ \
	lib/terminfo usr/share home var dev-lgmod.tar.gz etc_passwd.tar.gz lm; do
	d=$D/$i; dd=${d%/*}; mkdir -p $dd; cp -ar trunk/rootfs/$i $d; done
(cd $D; for i in etc/init.d/rcS-nvram etc/init.d/netcast home/lgmod/install.sh usr/lib/gconv; do
	rm -rf $i; done)
find $D -name '.svn' | xargs rm -rf

cp -r --preserve=timestamps trunk/rootfs-common squashfs-root || exit 5; # base rootfs-common
if [ -n "$S6" ]; then
	# TODO: update svn rootfs-S6
	D=trunk/rootfs-S6; [ -d $D ] || { mkdir $D && cd $D && svn co http://svn.openlgtv.org.ru/lgmod/trunk/rootfs . || exit 99; cd ../..; }
	(cd $D; rm -f etc/auth.sh etc/group etc/hosts etc/init.d/rcS etc/inittab etc/lgmod.sh \
		etc/mtab etc/profile etc/resolv.conf etc/securetty etc/shadow etc/TZ etc_passwd.tar.bz2
		[ -d modules ] && mv modules lib/modules; sed -i -e 's/^ramfs/#ramfs/' etc/fstab
		[ -h mnt/lg/cmn_data ] || ln -s user/cmn_data mnt/lg/cmn_data
		[ -h usr/sbin/scp ] || ln -s /mnt/lg/user/scp usr/sbin/scp)
	for i in lib/libncurses.so.5 lib/libncurses.so.5.7 usr/bin/dbclient usr/bin/dropbearkey usr/bin/tmux \
		usr/lib/libevent-1.4.so.2 usr/lib/libevent-1.4.so.2.1.3 usr/lib/dropbear/dropbearconvert usr/sbin/dropbear; do
		d=$D/$i; dd=${d%/*}; mkdir -p $dd; cp -ar trunk/rootfs/$i $d; done
	#find $D -name '.svn' | xargs rm -rf

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


# split extroot
if [ -d extroot ]; then
	cp -r --preserve=timestamps extroot extroot-img || exit 24
	rm -f extroot-img/*.tar.gz; fi
if [ -n "$S6" ]; then
	mkdir -p extroot-img/usr/bin
	for i in dbclient djmount dropbearkey; do i=usr/bin/$i
		mv squashfs-root/$i extroot-img/$i || exit 27; done
	mkdir -p extroot-img/lib/modules
	for i in catc.ko; do i=lib/modules/$i
		mv squashfs-root/$i extroot-img/$i || exit 28; done
else
	mkdir -p extroot-img/bin
	for i in bin/gdbserver; do
		mv squashfs-root/$i extroot-img/$i || exit 25; done
	for i in free kill pgrep pkill pmap sysctl top uptime watch; do i=bin/$i
		mv squashfs-root/$i extroot-img/$i || exit 26
		ln -s busybox squashfs-root/$i; done
	mkdir -p extroot-img/usr/bin
	for i in dbclient fusermount mount.fuse ulockmgr_server; do i=usr/bin/$i; #dropbearkey
		mv squashfs-root/$i extroot-img/$i || exit 27; done
fi
(cd extroot-img; tar czf ../$ofext *)
rm -rf extroot-img


find squashfs-root -name '.svn' | xargs rm -rf
cd squashfs-root
for i in dev dev-lgmod etc_passwd; do i=$i.tar; g=$i.gz; b=$i.bz2
	[ -f $g ] && tar xzf $g; [ -f $b ] && tar xjf $b; rm -f $b $g; done
echo $LGMOD_VER_TEXT > var/www/cgi-bin/version
for i in etc/init.d/rcS etc/init.d/lgmod var/www/cgi-bin/footer.inc var/www/cgi-bin/header.inc; do
	sed -i -e "s/ver=/$LGMOD_VER_TEXT/g" $i; done
cd ..
$mksquashfs_bin squashfs-root $ofile.sqfs -le -all-root -noappend -b 1048576 || exit 6

osize=`wc -c $ofile.sqfs | awk '{print $1}'`; o4096=$(( $osize / 4096 * 4096 ))
echo "Size: $osize / $size"
if [ "$osize" -gt "$size" ]; then
	echo "ERROR: Partition image too big for flashing ($osize - $size = $(( osize-size )))."; exit 3; fi
if [ "$osize" != "$o4096" ]; then
	echo "ERROR: Partition image is not multiple of 4096 ($osize / $o4096)."; exit 4; fi
[ "$1" == test ] || rm -rf squashfs-root


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

	cat extract.sh $ofile.zip > $ofile.sh.zip
	rm -f $ofile.zip
fi
