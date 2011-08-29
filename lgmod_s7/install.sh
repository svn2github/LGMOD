#!/bin/sh
# Source code released under GPL License
# OpenLGTV BCM installation script v.1.5 by xeros
# Rewriten for Saturn7 by mmm4m5m

# config
CHR=/tmp/install-root; USB=/tmp/install-usb; INS=/home/lgmod/install.sh
DIR="${0%/*}"
rootfs=$(echo "$DIR/"lgmod_S7_*.sqfs)
MNT='/tmp /mnt/lg/lgapp /mnt/lg/lginit /mnt/lg/user /mnt/lg/cmn_data'

# command line
info=1; chroot=1
for i in "$@"; do
	[ "$i" = info ]   && info=1;   [ "$i" = noinfo ]   && info=''
	[ "$i" = chroot ] && chroot=1; [ "$i" = nochroot ] && chroot=''; done

if [ "$1" = steps ]; then
	INIT=/mnt/lg/user/lgmod/init; USB=/tmp/lgmod/chrusb
	usb="$USB${rootfs#/mnt/usb?/Drive?}"; usb="${usb%/*}"
	echo "#
# 0. Steps - start this script using absolute path to script file
# 1. Prepare - replace 'sd?' with the actual device name
mount | grep /dev/sd && mkdir -p $INIT
echo 'LGI_MENU=1' >> $INIT/lginit
echo 'LGI_CHROOT=sd?${rootfs#/mnt/usb?/Drive?}' >> $INIT/lginit
# 2. Install - lginit image only and then reboot (restart TV)
install.sh lginiton <ARGUMENTS> && reboot
# 3. Check - wait few sec. Change options and reboot
echo 'RCS_NOREL=1' >> $INIT/rcS && reboot
# 4. Install - rootfs
cd $usb; $INS <ARGUMENTS>
# 5. Cleanup - do not forget
rm -r $INIT
#	"
fi


# info
if [ -n "$info" ]; then
	err=0
	{ echo -ne "\n\n#$# INFO($err): "; date
		echo -e '\n\n$#' df -h; df -h | grep -v '^/dev/sd' || err=12
		echo -e '\n\n$#' busybox; busybox || err=12
		echo -e '\n\n$#' help; help || err=10
		echo -e '\n\n$#' dmesg; dmesg|grep ACTIVE;echo; dmesg || err=15
		for i in /etc/version_for_lg /mnt/lg/model/* /mnt/lg/cmn_data/*exc_log_[0-9]*.txt /lgsw/* \
			/etc/init.d/rcS /etc/rc.d/rc.* /mnt/lg/user/lgmod/init/*; do [ ! -f "$i" ] && continue
			echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
			echo -e '\n\n$#' cat "$i"; cat "$i" || err=16
		done; echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
		echo -e '\n\n$# list some files'
		ls -lR /etc /mnt/lg/lginit /mnt/lg/user /mnt/lg/model /mnt/lg/lgapp /usr/local /mnt/lg/bt /mnt/lg/cmn_data /mnt/lg/res/lgres /mnt/lg/res/lgfont
		ls -l /mnt/lg/ciplus/cert | sed -e 's/ [^ ]*-/ ...-/'; # private info?
		ls -l /mnt/lg/ciplus /mnt/lg/ciplus/[^c]* /home/lgmod /mnt/lg/res/estreamer /mnt/addon /mnt/addon/* /mnt/addon/*/* /mnt/addon/*/*/*
	} >> /tmp/install-info
	[ $err != 0 ] && echo "Error($err): Info file failed: $infofile"
fi

err=0


INFO="$DIR"; ip=''; [ -f /mnt/lg/user/lgmod/ftp ] && ! tty > /dev/null &&
	ip=$(ifconfig eth0|grep addr|sed -e'2!d' -e's/^[^:]*://' -e's/ .*//'|grep -v 255 2>/dev/null)
[ -n "$ip" ] && INFO="<a href='ftp://$ip/${INFO#$(cat /mnt/lg/user/lgmod/ftp)}'>$INFO</a>"

mkdir -p "$CHR"; mount -t squashfs "$rootfs" "$CHR"
[ -f "$CHR$INS" ] || { err=7; echo "Error($err): File not found: $CHR$INS"; }


[ $err != 0 ] && exit $err

if [ -n "$chroot" ]; then
	mount -t sysfs installsysfs "$CHR/sys" &&
		mount -t proc  installproc  "$CHR/proc" &&
		mount -t usbfs installusbfs "$CHR/proc/bus/usb"
	if [ -d "$CHR/proc/bus/usb" ]; then
		for i in $MNT "$USB"; do mount -o bind "$i" "$CHR$i"; done
		mkdir -p "$CHR$USB"; mount -o bind "$USB" "$CHR$USB"

		if [ -d "$CHR$USB" ]; then
			echo "Output directory: $INFO"; echo
			chroot "$CHR" "$INS" "$@" "workdir=$USB" busybox=/bin/busybox ||
				{ err=$?; [ $err -gt 99 ] && exit $err; }; # keep chroot environment
		else err=8; echo "Error($err): Chroot failed: $CHR$USB"; fi

		umount "$CHR$USB" && rm -r "$CHR$USB"
		for i in $MNT; do umount "$CHR$i"; done
	else err=9; echo "Error($err): Chroot failed: $CHR/proc/bus/usb"; fi
	umount "$CHR/proc/bus/usb" "$CHR/proc" "$CHR/sys"
else
	echo "Output directory: $INFO"; echo
	cd "$DIR"; "$CHR$INS" "$@" ||
		{ err=$?; [ $err -gt 99 ] && exit $err; }; # keep root mounted
fi


umount "$CHR" && rm -r "$CHR"
exit $err
