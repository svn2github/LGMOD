#!/bin/sh
# Source code released under GPL License
# OpenLGTV BCM installation script v.1.5 by xeros
# Rewriten for Saturn7 by mmm4m5m

# config
CHR=/tmp/install-root; USB=/tmp/install-usb; INS=/home/lgmod/install.sh
DIR=$(pwd); dir="${0%/*}"; [ -n "$dir" ] && { cd=$(pwd); cd "$dir"; DIR=$(pwd); cd "$cd"; }
rootfs=$(echo "$DIR/"lgmod_S7_*.sqfs)
MNT='/tmp /mnt/lg/lgapp /mnt/lg/lginit /mnt/lg/user /mnt/lg/cmn_data'

# command line
info=1; chroot=1; chrootonly=''
for i in "$@"; do
	[ "$i" = info ]    && info=1;   [ "$i" = noinfo ]   && info=''
	[ "$i" = chroot ]  && chroot=1; [ "$i" = nochroot ] && chroot=''
	[ "$i" = chrootonly ] && chrootonly=1; done

if [ "$1" = steps ]; then
	BOOT=/mnt/lg/user/lgmod/boot
	echo "# Steps - flash lginit only chroot to rootfs
	# 0. Start this script with absolute path
	# 1. Setup chroot, install lginit image only and try LGMOD
	echo 'LGI_CHROOT=sd?${rootfs#/mnt/usb?/Drive?}' >> $BOOT
	$0 lginitonly && reboot
	# 2. Optional: You could disable RELEASE before reboot
	echo 'RCS_NOREL=1' >> $BOOT && reboot
	# 3. Cleanup: rm $BOOT
		"
	exit
fi

INFO="$DIR"; ip=''; [ -f /mnt/lg/user/lgmod/ftp ] && ! tty > /dev/null &&
	ip=$(ifconfig eth0|grep addr|sed -e'2!d' -e's/^[^:]*://' -e's/ .*//'|grep -v 255 2>/dev/null)
[ -n "$ip" ] && INFO="<a href='ftp://$ip/${INFO#$(cat /mnt/lg/user/lgmod/ftp)}'>$INFO</a>"

err=0


mkdir -p "$CHR"; grep " $CHR " /proc/mounts || mount -t squashfs "$rootfs" "$CHR"
[ -f "$CHR$INS" ] || { err=7; echo "Error($err): File not found: $CHR$INS"; }
[ $err != 0 ] && exit $err


if [ -n "$info" ]; then
	"$CHR/home/lgmod/info.sh" root ''; # save to /tmp - common for root and chroot
fi

if [ -n "$chroot" ]; then
	mount -t sysfs installsysfs "$CHR/sys" &&
		mount -t proc  installproc  "$CHR/proc" &&
		mount -t usbfs installusbfs "$CHR/proc/bus/usb"
	if [ -d "$CHR/proc/bus/usb" ]; then
		for i in $MNT; do mount -o bind "$i" "$CHR$i"; done
		mkdir -p "$CHR$USB"; mount -o bind "$DIR" "$CHR$USB"

		if [ -d "$CHR$USB" ]; then
			echo "Output directory: $INFO"; echo
			if [ -n "$chrootonly" ]; then
				echo "For chroot : chroot $CHR /bin/sh"
				echo "For install: chroot $CHR $INS workdir=$USB busybox=/bin/busybox"
				chroot "$CHR" /bin/sh
				exit; # keep chroot environment
			else
				chroot "$CHR" "$INS" "$@" "workdir=$USB" busybox=/bin/busybox ||
					{ err=$?; [ $err -gt 99 ] && exit $err; }; # keep chroot environment
			fi
		else err=8; echo "Error($err): Chroot failed: $CHR$USB"; fi

		umount "$CHR$USB" && sleep 1 && rm -r "$CHR$USB"
		for i in $MNT; do umount "$CHR$i"; done
	else err=9; echo "Error($err): Chroot failed: $CHR/proc/bus/usb"; fi
	umount "$CHR/proc/bus/usb" "$CHR/proc" "$CHR/sys"
else
	echo "Output directory: $INFO"; echo
	cd "$DIR"; "$CHR$INS" "$@" ||
		{ err=$?; [ $err -gt 99 ] && exit $err; }; # keep root mounted
fi


sleep 1 && umount "$CHR" && sleep 1 && rm -r "$CHR"
exit $err
