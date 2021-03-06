#!/bin/sh
# Source code released under GPL License
# OpenLGTV BCM installation script v.1.5 by xeros
# Rewriten for Saturn7 by mmm4m5m

# defaults
workdir=''; busybox=/tmp/install-root/bin/busybox; lginitmd5=''; lginit=''
info=1; cmagic=1; dvrchk=1
kill=1; backup_kill=''
backup=1; update_backup=1
install=''; update=''; lginitonly=''; dryrun=''; dryerr=''
#[ -f /mnt/lg/lginit/lginit ] && [ -f /mnt/lg/lginit/lg-init ] && backup='' && update=1
[ -f /mnt/lg/lginit/lginit-exec ] && backup=''

# command line
for i in "$@"; do
	[ "${i#workdir=}" != "$i" ]   && workdir="${i#workdir=}"
	[ "${i#busybox=}" != "$i" ]   && busybox="${i#busybox=}"
	[ "${i#lginitmd5=}" != "$i" ] && lginitmd5="${i#lginitmd5=}"
	[ "${i#lginit=}" != "$i" ]    && lginit="${i#lginit=}"
	[ "$i" = info ]       && info=1;    [ "$i" = noinfo ]    && info=''
	[ "$i" = cmagic ]     && cmagic=1;  [ "$i" = nocmagic ]  && cmagic=''
	[ "$i" = dvrchk ]     && dvrchk=1;  [ "$i" = nodvrchk ]  && dvrchk=''
	[ "$i" = kill ]       && kill=1;    [ "$i" = nokill ]    && kill=''
	[ "$i" = kill ]       && backup_kill=1
	[ "$i" = backup ]     && backup=1;  [ "$i" = nobackup ]  && backup=''
	[ "$i" = nobackup ]   && update_backup=''
	[ "$i" = install ]    && install=1; [ "$i" = noinstall ] && install=''
	#[ "$i" = update ]    && update=1;  [ "$i" = noupdate ]  && update=''
	[ "$i" = lginitonly ] && { install=1; lginitonly=1; }
	[ "$i" = dryrun ]     && dryrun=1;  [ "$i" = dryerr ]    && dryerr=1
done; [ -n "$dryrun$dryerr" ] && TEST_ECHO=echo || TEST_ECHO=''
[ -n "$workdir" ] && cd "$workdir"

# config
date=$(date '+%Y%m%d-%H%M%S')
infofile="backup-$date-info.txt"
bkpdir="backup-$date"
rootfs=$(echo lgmod_S7_*.sqfs)
lginitA=mtd4_lginitA.sqfs; lginitB=mtd4_lginitB.sqfs; lginitC=mtd4_lginitC.sqfs; lginitD=mtd4_lginitD.sqfs
lginitAmd5='1e6ee0f4d9d08f920c406c2173f855a3'; # common S7
lginitBmd5='bb43933fb79dd2077151df09ab67f893'; # FW 4.01.xx, 4.60.xx
lginitCmd5='146533ffe3cbd4c1804e58f5c0104852'; # US models
lginitDmd5='c1c28439be79d4d94220592b6d4c8fa9'; # 37LV3500-ZG with FW 3.01.06/3.01.10 is different (?)
required_free_ram=10000
KILL='addon_mgr stagecraft udhcpc ntpd tcpsvd djmount'
	# LG: addon_mgr stagecraft
	# LGMOD: udhcpc ntpd telnetd tcpsvd djmount httpd

# consts
ROOTFS=/dev/mtd3; LGINIT=/dev/mtd4
rootfs_size=7340032; lginit_size=393216
CRAMFS_MAGIC='0x73736572706D6F43'
RELEASE_MAGIC='0x464C457F'

# info
if [ -n "$info" ]; then
	/home/lgmod/info.sh chroot "$infofile"
fi

err=0


# prepare
ERR=$(which dmesg grep sort md5sum awk mkdir stat killall pkill sleep cut sed free flash_eraseall cat sync) ||
	{ err=24; echo "Error($err): Command not found:" $ERR; }
[ -f $busybox ] || { err=26; echo "Error($err): File not found: busybox"; }; #devmem tar
if [ -n "$install" ] && [ -n "$cmagic" ]; then
	# LG rc.local and BCM lginit sh script
	APP_XIP=`cat /proc/cmdline | awk -v RS='[ ]' -F= '/appxip_addr=/ { print $2 }'`
	FONT_XIP=`cat /proc/cmdline | awk -v RS='[ ]' -F= '/fontxip_addr=/ { print $2 }'`
	if [ "${APP_XIP}" != "" ] && [ "${APP_XIP}" != "0x0" ]; then
		cramfs_magic=`$busybox devmem $((APP_XIP+16)) 64` || { err=21; echo 'ERROR: devmem APP_XIP+16'; }
		release_magic=`$busybox devmem $((APP_XIP+1024*4)) 32` || { err=21; echo 'ERROR: devmem APP_XIP+1024*4'; }
		[ "$cramfs_magic" != "$CRAMFS_MAGIC" ] && { err=22; echo "ERROR: $cramfs_magic ($CRAMFS_MAGIC)"; }
		[ "$release_magic" != "$RELEASE_MAGIC" ] && { err=22; echo "ERROR: $release_magic ($RELEASE_MAGIC)"; }
	fi
	if [ "${FONT_XIP}" != "" ] && [ "${FONT_XIP}" != "0x0" ]; then
		cramfs_magic=`$busybox devmem $((FONT_XIP+16)) 64` || { err=21; echo 'ERROR: devmem FONT_XIP+16'; }
		[ "$cramfs_magic" != "$CRAMFS_MAGIC" ] && { err=22; echo "ERROR: $cramfs_magic ($CRAMFS_MAGIC)"; }
	fi
fi
if [ -n "$dvrchk" ]; then
	DVR=`cat /proc/cmdline | awk -v RS='[ ]' -F= '/dvr=/ { print $2 }'`
	[ "$DVR" != 0 ] && { err=23; echo "ERROR($err): EZ ADJUST / DVR Ready = 1"; }
	dmesg | grep 'fdisk\|allocation failure' && { err=23; echo "ERROR($err): EZ ADJUST / DVR Ready = 1 (?)"; }
fi
if [ -n "$install" ]; then
	[ -f "$rootfs" ] || { err=25; echo "Error($err): File not found: $rootfs"; }
	flash_eraseall --version | sed -e '2,$d' ||
		{ err=26; echo "ERROR($err): 'flash_erasesall' something??!"; }
	I=$(cat /proc/mtd | sed -e 's/:.*"\(.*\)"/\1/' -e 's/^mtd//' | grep -v ' \|0bbminfo\|5boot\|6crc32info\|8logo\|15kernel\|16lgapp\|20kernel\|22lgres\|23cert\|24authcxt' | sort -n) ||
		{ err=27; echo "ERROR($err): /proc/mtd (install)"; }
	[ "$(echo ${I//mtd})" = '1boot 2info 3rootfs 4lginit 7model 9cmndata 10nvram 11user 12ezcal 13estream 14opsrclib 17lgres 18lgfont 19addon 21lgapp' ] ||
		{ err=27; echo "ERROR($err): TV partitions mismath"; }
fi
if [ -z "$update" ] && [ -z "$lginit" ]; then :; #[ -n "$install" ] &&
	if [ -z "$lginitmd5" ]; then
		f=/mnt/lg/lginit/lg-init; [ -f $f ] || f=/mnt/lg/lginit/lginit
		[ -f $f ] && lginitmd5=`md5sum $f`; lginitmd5="${lginitmd5%% *}"; fi
	if   [ "$lginitmd5" = "$lginitAmd5" ]; then lginit="$lginitA"
	elif [ "$lginitmd5" = "$lginitBmd5" ]; then lginit="$lginitB"
	elif [ "$lginitmd5" = "$lginitCmd5" ]; then lginit="$lginitC"
	elif [ "$lginitmd5" = "$lginitDmd5" ]; then lginit="$lginitD"
	else [ -n "$install" ] && err=28; echo "ERROR($err): md5 mismatch: $f"; fi
	if [ $err = 0 ]; then
		echo && echo "NOTE: LGINIT=$lginit !"
		[ -f "$lginit" ] || { err=28; echo "Error($err): File not found: $lginit"; }
	fi
fi
[ $err != 0 ] && exit $err
if [ -n "$install" ]; then
	[ -f "$rootfs.md5" ] && md5chk=$(cat "$rootfs.md5") && md5cur=$(md5sum "$rootfs") &&
		[ "${md5chk%% *}" = "${md5cur%% *}" ] ||
		{ err=29; echo "ERROR($err): md5 mismatch: $rootfs"; }
	[ -f "$lginit.md5" ] && md5chk=$(cat "$lginit.md5") && md5cur=$(md5sum "$lginit") &&
		[ "${md5chk%% *}" = "${md5cur%% *}" ] ||
		{ err=29; echo "ERROR($err): md5 mismatch: $lginit"; }
fi
[ $err != 0 ] && exit $err


# backup - prepare
I=''
if [ -n "$backup" ] || [ -n "$update_backup" ]; then
	[ -d "$bkpdir" ]   && { err=31; echo "Error($err): Directory exist: $bkpdir"; exit $err; }
	mkdir -p "$bkpdir" || { err=32; echo "Error($err): Can't create directory: $bkpdir"; exit $err; }
	I="${ROOTFS#/dev/}_rootfs ${LGINIT#/dev/}_lginit"
fi
if [ -n "$backup" ]; then
	I=$(cat /proc/mtd | sed -e 's/:.*"\(.*\)"/_\1/' | grep -v ' \|erasesize') ||
		{ err=33; echo "ERROR($err): /proc/mtd (backup)"; exit $err; }
fi
[ $err != 0 ] && exit $err

# backup - free mem
if [ -n "$I" ] && [ -n "$backup_kill" ]; then
	echo 'NOTE: Freeing memory (killing daemons) ...'
	for i in $KILL; do pkill $i && echo $i; killall $i 2> /dev/null && echo $i; done
	sleep 2
fi

# backup
if [ -n "$I" ]; then
	echo; echo 'NOTE: BACKUP ...'
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
	$busybox tar cvzf "backup-$date-user.tar.gz" /mnt/lg/user ||
		echo "WARNING: Create archive failed: /usr/lg/user"
	$busybox tar cvzf "backup-$date-cmn_data.tar.gz" /mnt/lg/cmn_data ||
		echo "WARNING: Create archive failed: /usr/lg/cmn_data"

	sync
	echo; echo 'BACKUP DONE! SUCCESS!'
	echo '	For backup and installation, start: install.sh install'
	echo '	Keep your backup safe! USB flash drive is NOT safe!'
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
	# Enable lginit menu, Force RELEASE LG default
	MNT=/mnt/lg/user; BOOTMOD=$MNT/lgmod/boot
	RELMOD=/mnt/lg/user/lgmod/release
	n=LGI_MENU; [ -f $BOOTMOD ] && grep -q "^$n=" $BOOTMOD && sed -ie "/^$n=/d" $BOOTMOD
	n=MODE; [ -f $RELMOD ] && grep -q "^$n=" $RELMOD && sed -ie "/^$n=\|^$/d" $RELMOD
	[ -f $RELMOD ] && [ ! -s $RELMOD ] && rm -f $RELMOD
	[ -f $RELMOD ] && echo "$n=LG" >> $RELMOD

	if [ -n "$kill" ]; then
		echo 'NOTE: Freeing memory (killing daemons) ...'
		for i in $KILL; do pkill $i && echo $i; killall $i 2> /dev/null && echo $i; done
		sleep 2
	fi
	sync; echo 3 > /proc/sys/vm/drop_caches; sleep 1
	free=$(free | sed -e '2!d' -e 's/ \+/+/g' | cut -d + -f 4,6) &&
		free=$(( $free )) && [ $free -ge $required_free_ram ] ||
		{ err=45; echo "ERROR($err): Low memory - very few bytes available ($free < $required_free_ram)??!"; }
	[ $err != 0 ] && exit $err
	echo

	if [ -z "$update" ]; then # lginit
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
			[ -n "$dryrun$dryerr" ] && break
			cat "$lginit" > "$LGINIT" && break; ERR=$?
			err=52; echo "$i: ERROR($err): $LGINIT - Critical($ERR)!?"
		done; sync
		if [ $err != 0 ]; then
			echo; echo 'WARNING: Erase/Flash LGINIT partition failed!!!'
			echo '	If you restart TV now, you will get into shell - TV will not work'
			echo '		TV is NOT dead/brick. Ask for assistance in forum/irc'
			echo '	Save above messages (copy from screen or find the log file'
			echo '		of your serial terminal program or get a screenshots)'
			echo 'ADVANCED: Wiki tells how to manually erase & write TV partition'
			exit $err
		else
			echo; echo 'Flash lginit partition - DONE!'
			[ -n "$lginitonly" ] && exit
		fi
	fi

	if [ -z "$lginitonly" ]; then # rootfs
		# run once just before erase rootfs
		echo | cat || { err=50; echo "Error($err): Cat failed!"; exit $err; }

		for i in 1 2; do
			[ $i != 1 ] && echo "$i: $ROOTFS - Trying again ..."
			for j in 1 2; do
				[ $j != 1 ] && echo "$j: Trying again ..."
				echo "$j: NOTE: Erase $ROOTFS ..."; ERR=0
				$TEST_ECHO flash_eraseall "$ROOTFS" && break; ERR=$?
				if [ $ERR = 138 ]; then echo "$j: ERROR($err): $ROOTFS - Bus error($ERR) OK!?"
				else err=101; echo "$j: ERROR($err): $ROOTFS - Critical($ERR)!!"; fi
				# TODO: try alternative erase (xeros)
			done
			echo "$i: NOTE: Write $ROOTFS ..."; ERR=0
			[ -n "$dryerr" ] && err=113; [ -n "$dryrun$dryerr" ] && break
			cat "$rootfs" > "$ROOTFS" && break; ERR=$?
			err=102; echo "$i: ERROR($err): $ROOTFS - Critical($ERR)!!!"
		done; $busybox sync
	fi

	if [ $err != 0 ]; then
		echo; echo 'CRITICAL: Erase/Flash ROOTFS partition failed!!!'
		echo '	Do NOT restart TV now. You may NOT be able to enter into shell!'
		echo '	Remove TV "auto off". Ask for assistance in forum/irc'
		echo '	Save above messages (copy from screen or find the log file'
		echo '		of your serial terminal program or get a screenshots)'
		echo 'ADVANCED: Wiki tells how to manually erase & write TV partition'
		echo '	You can try again the install command:'; echo "	cd $PWD; $0 $@"
		pty=/lib/modules/2.6.26/pty.ko
		if 	$busybox touch /dev/shm/chroot-test 2>/dev/null ||
			$busybox touch /lgsw/chroot-test 2>/dev/null ||
			$busybox touch /usr/local/etc/chroot-test 2>/dev/null; then
			echo "NOTE: If you are not in chroot, you can use: $busybox"
			if $busybox tty > /dev/null; then $busybox sh; else
				bb=$($busybox realpath $busybox); pty="${bb%/bin/busybox}$pty"
				echo '#!'"$bb sh"$'\n'"exec $busybox sh" > /tmp/auth.sh; chmod +x /tmp/auth.sh
				$busybox insmod "$pty" 2>/dev/null; $busybox telnetd -l /tmp/auth.sh -p 1023
				echo "INFO: telnetd started at port 1023: $busybox"
			fi
		elif ! tty > /dev/null; then
			insmod $pty; telnetd -p 1023
			echo 'INFO: telnetd started at port 1023: chroot'
		else sh; fi; exit $err
	else
		echo; echo 'FLASH DONE! SUCCESS! You can restart TV now.'
		echo '	You could copy and save all messages above.'
		echo '	Proper nvram backup is created after restart (remote control).'
		tty > /dev/null && $busybox sh || { echo 'reboot ...'; (sleep 3; reboot)& }
	fi
fi
