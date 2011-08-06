#!/bin/sh
# OpenLGTV BCM installation script v.1.5 by xeros
# Source code released under GPL License
# Rewriten for lgmod S7 by mmm4m5m

# config
CHR=/tmp/install-root
USB=/tmp/install-usb
DIR="${0%/*}"
rootfs=$(echo "$DIR/"lgmod_S7_*.sqfs)
MNT='/tmp /mnt/lg/lgapp /mnt/lg/lginit /mnt/lg/user /mnt/lg/cmn_data'

# command line
info=1; chroot=1
for i in "$@"; do
	[ "$i" = info ]   && info=1;   [ "$i" = noinfo ]   && info=''
	[ "$i" = chroot ] && chroot=1; [ "$i" = nochroot ] && chroot=''; done

err=0


# info
if [ -n "$info" ]; then
	( err=0; echo -ne '\n\n#$# INFO: '; date
		echo -e '\n\n$#' df -h; df -h | grep -v '^/dev/sd' || err=12
		echo -e '\n\n$#' busybox; busybox || err=12
		echo -e '\n\n$#' help; help || err=10
		echo -e '\n\n$#' dmesg; dmesg|grep ACTIVE;echo; dmesg || err=15
		for i in /etc/version_for_lg /mnt/lg/model/* /mnt/lg/cmn_data/*exc_log_[0-9]*.txt /lgsw/* \
			/etc/init.d/* /etc/rc.d/* /mnt/lg/user/lgmod/init/*; do [ ! -f "$i" ] && continue
			echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
			echo -e '\n\n$#' cat "$i"; cat "$i" || err=16
		done; echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
		echo -e '\n\n$# list some files'
		ls -lR /etc /mnt/lg/lginit /mnt/lg/user /mnt/lg/model /mnt/lg/lgapp /usr/local /mnt/lg/bt /mnt/lg/cmn_data /mnt/lg/res/lgres /mnt/lg/res/lgfont
		ls -l /mnt/lg/ciplus/cert | sed -e 's/ [^ ]*-/ ...-/'; # private info?
		ls -l /mnt/lg/ciplus /mnt/lg/ciplus/[^c]* /home/lgmod /mnt/lg/res/estreamer /mnt/addon /mnt/addon/* /mnt/addon/*/* /mnt/addon/*/*/*
	exit $err ) >> /tmp/install-info || err=$?
	[ $err != 0 ] && echo "Error($err): Info file failed: $infofile"; err=0
fi


INFO="$DIR"; ip=''; [ -f /mnt/lg/user/lgmod/ftp ] && ! tty > /dev/null &&
	ip=$(ifconfig eth0|grep addr|sed -e'2!d' -e's/^[^:]*://' -e's/ .*//'|grep -v 255 2>/dev/null)
[ -n "$ip" ] && INFO="<a href='ftp://$ip/${INFO#$(cat /mnt/lg/user/lgmod/ftp)}'>$INFO</a>"


mkdir -p "$CHR" && mount -t squashfs "$rootfs" "$CHR" || err=5
[ $err = 0 ] || { echo "Error($err): Mount root failed: $rootfs ($CHR)"; exit $err; }

if [ -n "$chroot" ]; then
	mount -t proc  installproc  "$CHR/proc" || err=6
	mount -t sysfs installsysfs "$CHR/sys" || err=6
	mount -t usbfs installusbfs "$CHR/proc/bus/usb" || err=6
	for i in $MNT; do mount -o bind "$i" "$CHR$i" || err=7; done
	mkdir -p "$USB" && mount -o bind "$DIR" "$CHR$USB" || err=8

	if [ $err != 0 ]; then echo "Error($err): Chroot failed."
	else
		echo "Output directory: $INFO"; echo
		chroot "$CHR" /home/lgmod/install-chroot.sh "$@" "workdir=$USB" busybox=/bin/busybox ||
			{ ERR=$?; [ $ERR -gt 99 ] && exit $ERR; }; # keep chroot environment
	fi

	umount "$CHR/sys" "$CHR/proc" "$CHR$USB" && rm -r "$CHR$USB"
	for i in $MNT; do umount "$CHR$i"; done
else
	echo "Output directory: $INFO"; echo
	cd "$DIR"; "$CHR/home/lgmod/install-chroot.sh" "$@" ||
		{ ERR=$?; [ $ERR -gt 99 ] && exit $ERR; }; # keep root mounted
fi

umount "$CHR" && rm -r "$CHR"
exit $err
