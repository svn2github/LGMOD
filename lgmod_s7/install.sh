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
	echo "# Steps
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


# info
if [ -n "$info" ]; then
	err=0
	{ echo -ne '\n\n#$#'" INFO($err): "; date
		echo -e '\n\n$#' df -h; df -h | grep -v '^/dev/sd' || err=12
		echo -e '\n\n$#' busybox; busybox || err=12
		echo -e '\n\n$#' help; help || err=10
		echo -e '\n\n$#' dmesg; dmesg|grep ACTIVE;echo; dmesg || err=15
		for i in /proc/version_for_lg /etc/version_for_lg /mnt/lg/model/* \
			/mnt/lg/user/lgmod/boot /mnt/lg/user/lgmod/init/*; do [ ! -f "$i" ] && continue
			echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
			echo -e '\n\n$#' cat "$i"; cat "$i" || err=16
		done; echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
		echo -e '\n\n$# list some files'
		ls -lR /etc /mnt/lg/lginit /mnt/lg/bt /mnt/lg/user /mnt/lg/cmn_data /mnt/lg/model \
			/mnt/lg/lgapp /mnt/lg/res/lgres /mnt/lg/res/lgfont /usr/local \
			/mnt/addon/bin /mnt/addon/lib /mnt/addon/stagecraft
		ls -l /mnt/addon /mnt/lg/ciplus /mnt/lg/res/estreamer
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
