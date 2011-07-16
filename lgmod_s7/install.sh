#!/bin/sh
# OpenLGTV BCM installation script v.1.5 by xeros
# Source code released under GPL License
# Rewriten for lgmod S7 by mmm4m5m

cd "${0%/*}"

# config
date=$(date '+%Y%m%d-%H%M%S'); # TODO: long file names?
infofile="backup-$date-info.txt"
bkpdir="backup-$date"
rootfs=$(echo lgmod_*.sqfs)
lginit=mtd4_lg-init.sqfs
info=1
kill=1
install=''
dryrun=''
ROOTFS=/dev/mtd3
LGINIT=/dev/mtd4
rootfs_size=7340032
lginit_size=393216
lginit_bin_size=608572
required_free_ram=10000

# defaults
[ -f /mnt/lg/lginit/lginit ] && [ -f /mnt/lg/lginit/lg-init ] &&
	[ -f /etc/lgmod.sh ] && update=1 || update=''
[ -f /etc/lgmod.sh ] && backup='' || backup=1
update_backup=1


# command line
for i in "$@"; do
	[ "${i#infofile=}" != "$i" ] && log="${i#infofile=}"
	[ "${i#backup=}" != "$i" ] && bkpdir="${i#backup=}"
	[ "${i#rootfs=}" != "$i" ] && rootfs="${i#rootfs=}"
	[ "${i#lginit=}" != "$i" ] && lginit="${i#lginit=}"
	[ "$i" = info ]       && info=1
	[ "$i" = noinfo ]     && info=''
	[ "$i" = kill ]       && kill=1
	[ "$i" = nokill ]     && kill=''
	[ "$i" = install ]    && install=1
	[ "$i" = noinstall ]  && install=''
	[ "$i" = noupdate ]   && update=''
	[ "$i" = backup ]     && backup=1
	[ "$i" = nobackup ]   && backup=''
	[ "$i" = nobackup ]   && update_backup=''
	[ "$i" = dryrun ]     && dryrun=1
done
[ -n "$dryrun" ] && TEST_ECHO=echo || TEST_ECHO=''


err=0
# info
if [ -n "$info" ]; then
	(
	echo; echo '#' lsmod; lsmod || exit 10
	echo; echo '#' free; free || exit 11
	echo; echo '#' ps w -A; ps w -A || exit 12
	for i in /proc/version /proc/cpuinfo /proc/mounts /proc/mtd /etc/version_for_lg \
		/lg/model/RELEASE.cfg /etc/init.d/rcS /etc/rc.d/rc.sysinit /etc/rc.d/rc.local; do
		echo; echo '#' cat "$i"; cat "$i" || exit 13
	done
	echo; echo '#' printenv; printenv || exit 14
	echo; echo '#' export; export || exit 15
	echo; echo '#' dmesg; dmesg || exit 16
	) > "$infofile" || { err=$?; echo "Error($err): Info file failed: $infofile"; }
fi

# prepare
type which && which sync stat cat sed md5sum mkdir flash_eraseall || err=21; #rm mv
[ -f ./busybox ] || { err=22; echo "Error($err): File not found: busybox"; }
if [ -n "$install" ]; then
	[ -f "$rootfs" ] || { err=23; echo "Error($err): File not found: $rootfs"; }
	flash_eraseall --version | sed -e '2,$d' ||
		{ err=24; echo "ERROR($err): 'flash_erasesall' something??!"; }
fi
[ $err != 0 ] && exit $err
if [ -n "$install" ]; then
	md5cur=$(md5sum "$rootfs") && md5chk=$(cat "$rootfs.md5") &&
		[ "${md5cur% *}" = "${md5chk% *}" ] ||
		{ err=25; echo "ERROR($err): md5 mismatch: $rootfs"; }
	md5cur=$(md5sum "$lginit") && md5chk=$(cat "$lginit.md5") &&
		[ "${md5cur% *}" = "${md5chk% *}" ] ||
		{ err=26; echo "ERROR($err): md5 mismatch: $lginit"; }
fi
[ $err != 0 ] && exit $err


# backup
I=''
if [ -n "$backup" ] || [ -n "$update_backup" ]; then
	[ -d "$bkpdir" ]   && { err=31; echo "Error($err): Directory exist: $bkpdir"; exit $err; }
	mkdir -p "$bkpdir" || { err=32; echo "Error($err): Can't create directory: $bkpdir"; exit $err; }
	I="${ROOTFS#/dev/}_rootfs ${LGINIT#/dev/}_lginit"
fi
if [ -n "$backup" ]; then
	echo 'NOTE: Backup /proc/mtd ...'
	I=$(cat /proc/mtd | sed -e 's/:.*"\(.*\)"/_\1/' | grep -v ' ') ||
		{ err=33; echo "ERROR($err): /proc/mtd (backup)"; exit $err; }
fi
[ $err != 0 ] && exit $err
if [ -n "$I" ]; then
	for i in $I; do
		echo "Backup: $i ..."
		[ -e "/dev/${i%_*}" ] || { err=34; echo "ERROR($err): /dev/${i%_*}"; exit $err; }
		cat "/dev/${i%_*}" > "$bkpdir/$i" || { err=35; echo "ERROR($err): $bkpdir/$i"; exit $err; }
		sync; echo 3 > /proc/sys/vm/drop_caches; sleep 1
	done
	size=$(stat -c %s "$bkpdir/mtd3_rootfs") && [ $rootfs_size = "$size" ] ||
		{ err=36; echo "ERROR($err): Invalid file size($size<>$rootfs_size): mtd3_rootfs"; }
	size=$(stat -c %s "$bkpdir/mtd4_lginit") && [ $lginit_size = "$size" ] ||
		{ err=37; echo "ERROR($err): Invalid file size($size<>$lginit_size): mtd4_lginit"; }
	# LG stock: tar -[cxtvO] [-X FILE] [-f TARFILE] [-C DIR] [FILE(s)]...
	./busybox tar cvzpf "backup-$date-user.tar.gz" /mnt/lg/user ||
		echo "WARNING: Create archive failed: /usr/lg/user"
	./busybox tar cvzpf "backup-$date-cmn_data.tar.gz" /mnt/lg/cmn_data ||
		echo "WARNING: Create archive failed: /usr/lg/cmn_data"
	sync
	echo; echo 'BACKUP DONE! SUCCESS!'
	echo '	For backup and installation, start: install.sh install'
	echo '	(Keep your backup safe! USB flash drive is NOT safe!)'
	echo
fi
[ $err != 0 ] && exit $err


## install - create lginit sqfs image
#if [ -n "$install" ] && [ -z "$update" ]; then
#	if [ ! -f "$lginit" ] && [ -d squashfs-root ]; then
#		rm -r squashfs-root && sync ||
#			{ err=41; echo "Error($err): '$lginit' - can't remove directory: squashfs-root"; exit $err; }
#	fi
#	if [ ! -f "$lginit" ] && [ ! -d squashfs-root ]; then
#		echo 'NOTE: Create lginit.sqfs image ...'
#		./unsquashfs "$bkpdir/mtd4_lginit" &&
#			mv squashfs-root/lginit squashfs-root/lg-init &&
#			./mksquashfs squashfs-root "$lginit" -le -all-root -noappend &&
#			rm -r squashfs-root && sync ||
#			{ err=42; echo "ERROR($err): '$lginit' - unsquashfs/mksquashfs failed"; exit $err; }
#	fi
#	# check partition image size
#	size=$(stat -c %s "$lginit") && [ "$size" -le "$lginit_size" ] ||
#		{ err=43; echo "ERROR($err): '$lginit' - size is too big for flashing($size)"; }
#	size4096=$(( $size / 4096 * 4096 )) && [ "$size" = "$size4096" ] ||
#		{ err=44; echo "ERROR($err): '$lginit' - size is not multiple of 4096($size)"; }
#fi


# install
if [ -n "$install" ]; then
	I=$(cat /proc/mtd | sed -e 's/:.*"\(.*\)"/\1/' -e 's/^mtd//' | grep -v ' \|0bbminfo\|1boot\|2mtdinfo\|5boot\|6crc32info\|8logo\|10nvram\|15kernel\|16lgapp\|20kernel\|22lgres' | sort -n) ||
		{ err=45; echo "ERROR($err): /proc/mtd (install)"; }
	[ "$(echo ${I//mtd})" = '3rootfs 4lginit 7model 9cmndata 11user 12ezcal 13estream 14opsrclib 17lgres 18lgfont 19addon 21lgapp 23cert 24authcxt' ] ||
		{ err=46; echo "ERROR($err): TV partitions mismath"; }
fi
if [ -n "$install" ] && [ -z "$update" ] && [ -f /mnt/lg/lginit/lginit ] && [ ! -f /mnt/lg/lginit/lg-init ]; then
	size=$(stat -c %s /mnt/lg/lginit/lginit) && [ $lginit_bin_size = "$size" ] ||
		{ err=47; echo "ERROR($err): Invalid file size($size<>$lginit_bin_size): lginit"; }
fi
[ $err != 0 ] && exit $err

# install - free ram
if [ -n "$install" ] && [ -n "$kill" ]; then
	echo 'NOTE: Freeing memory (killing daemons) ...'
	# lgmod services: udhcpc ntpd telnetd tcpsvd djmount httpd
	for i in udhcpc ntpd tcpsvd djmount; do
		killall "$i"; pkill "$i";
	done
	sleep 2
fi
if [ -n "$install" ]; then
	sync; echo 3 > /proc/sys/vm/drop_caches; sleep 1
	free=$(free | sed -e '2!d' -e 's/ \+/+/g' | cut -d + -f 4,6) &&
		free=$(( $free )) && [ $free -ge $required_free_ram ] ||
		{ err=48; echo "ERROR($err): Low memory - very few bytes available ($free < $required_free_ram)??!"; }
fi
[ $err != 0 ] && exit $err

# install - lginit
if [ -n "$install" ] && [ -z "$update" ]; then
	echo

	for i in 1 2; do
		[ $i != 1 ] && echo "$i: $LGINIT - Trying again ..."

		for j in 1 2; do
			[ $j != 1 ] && echo "$j: Trying again ..."
			echo "$j: NOTE: Erase $LGINIT ..."; ERR=0
			$TEST_ECHO flash_eraseall "$LGINIT" && break; ERR=$?
			if [ $ERR = 138 ]; then echo "$j: Error($err): $LGINIT - Bus error($ERR) OK!?"
			else err=51; echo "$j: ERROR($err): $LGINIT - Critical($ERR)?"; fi
			# TODO: try alternative erase (xeros)
		done

		echo "$i: NOTE: Write $LGINIT ..."; ERR=0
		[ -n "$dryrun" ] && break
		cat "$lginit" > "$LGINIT" && break; ERR=$?
		err=52; echo "$i: ERROR($err): $LGINIT - Critical($ERR)!?"
	done
fi

# install - rootfs
if [ -n "$install" ]; then # && [ $err = 0 ]
	# rootfs - run once just before erase
	echo | cat || { err=50; echo "Error($err): Cat failed!"; exit $err; }

	for i in 1 2; do
		[ $i != 1 ] && echo "$i: $ROOTFS - Trying again ..."

		for j in 1 2; do
			[ $j != 1 ] && echo "$j: Trying again ..."
			echo "$j: NOTE: Erase $ROOTFS ..."; ERR=0
			$TEST_ECHO flash_eraseall "$ROOTFS" && break; ERR=$?
			if [ $ERR = 138 ]; then echo "$j: ERROR($err): $ROOTFS - Bus error($ERR) OK!?"
			else err=55; echo "$j: ERROR($err): $ROOTFS - Critical($ERR)!!"; fi
			# TODO: try alternative erase (xeros)
		done

		echo "$i: NOTE: Write $ROOTFS ..."; ERR=0
		[ -n "$dryrun" ] && break
		cat "$rootfs" > "$ROOTFS" && break; ERR=$?
		err=56; echo "$i: ERROR($err): $ROOTFS - Critical($ERR)!!!"
	done
fi

if [ -n "$install" ]; then
	sync
	if [ $err = 0 ]; then
		echo; echo 'FLASH DONE! SUCCESS! You can "reboot" now.'
		echo '	(Also you could copy and save all messages above.)'
		echo
	else
		echo; echo 'WARNING: Something is wrong!!!'
		echo '	1) do not touch TV and remote control'
		echo '	2) save and check messages above (copy messages from screen'
		echo '		or find the log file of your serial terminal program)'
		echo '		or get a screenshots)'
		echo '	3) ask for assistance (forum/irc)'
		echo 'ADVANCED: lgmod busybox is in zip file, wiki tells how to erase & write partitions'
		exit $err
	fi
fi


exit 0
