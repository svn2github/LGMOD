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
lginitmd5=1e6ee0f4d9d08f920c406c2173f855a3
info=1
kill=1
backup_kill=''
install=''
dryrun=''
ROOTFS=/dev/mtd3
LGINIT=/dev/mtd4
rootfs_size=7340032
lginit_size=393216
required_free_ram=10000
CRAMFS_MAGIC='0x73736572706D6F43'
RELEASE_MAGIC='0x464C457F'
KILL='addon_mgr stagecraft udhcpc ntpd tcpsvd djmount'
	# LG: addon_mgr stagecraft
	# LGMOD: udhcpc ntpd telnetd tcpsvd djmount httpd

# defaults
[ -f /mnt/lg/lginit/lginit ] && [ -f /mnt/lg/lginit/lg-init ] &&
	[ -f /etc/lgmod.sh ] && update=1 || update=''
[ -f /etc/lgmod.sh ] && backup='' || backup=1
update_backup=1


# command line
for i in "$@"; do
	[ "${i#infofile=}"  != "$i" ] && log="${i#infofile=}"
	[ "${i#backup=}"    != "$i" ] && bkpdir="${i#backup=}"
	[ "${i#rootfs=}"    != "$i" ] && rootfs="${i#rootfs=}"
	[ "${i#lginit=}"    != "$i" ] && lginit="${i#lginit=}"
	[ "${i#lginitmd5=}" != "$i" ] && lginitmd5="${i#lginitmd5=}"
	[ "$i" = info ]       && info=1
	[ "$i" = noinfo ]     && info=''
	[ "$i" = kill ]       && kill=1
	[ "$i" = kill ]       && backup_kill=1
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
	echo 'NOTE: Create info file (1 min) ...'
	echo 10009 > "$infofile" || err=10; dmesg="$(dmesg)" || err=15
	( echo -ne '\n\n#$# INFO: '; date
		echo -e '\n\n$#' cat /proc/mtd; cat /proc/mtd || err=11
		echo -e '\n\n$# dump mtdinfo (/dev/mtd2)'; ./busybox hexdump /dev/mtd2 -vs240 \
			-e'32 "%_p" " %08x ""%08x " 32 "%_p" " %8d"" %8x " /1 "Uu:%x" /1 " %x " /1 "CIMF:%x" /1 " %x" "\n"' |
			head -n$(cat /proc/mtd | wc -l) | grep '' -n || err=13
		echo -e '\n\n$#' cat /proc/mounts; cat /proc/mounts || err=11
		echo -e '\n\n$#' df -h; df -h | grep -v '^/dev/sd' || err=12
		echo -e '\n\n$# fdisk -l'; fdisk -l $(cat /proc/mtd | grep '^mtd' | sed -e 's/:.*//' -e 's/^mtd/\/dev\/mtdblock/') | grep : || err=14
	exit $err ) >> "$infofile" || err=$?; sync; echo 3 > /proc/sys/vm/drop_caches; sleep 1
	( echo -ne '\n\n#$# INFO: '; date
		echo -e '\n\n$#' free; free || err=12
		echo -e '\n\n$#' cat /proc/cpuinfo; cat /proc/cpuinfo || err=11
		echo -e '\n\n$#' lsmod; lsmod || err=12
		echo -e '\n\n$#' ps axl; ps axl || err=12
		echo -e '\n\n$#' ps axv; ps axv || err=12
	exit $err ) >> "$infofile" || err=$?; sync; echo 3 > /proc/sys/vm/drop_caches; sleep 1
	( echo -ne '\n\n#$# INFO: '; date
		echo -e '\n\n$#' cat /proc/version; cat /proc/version || err=11
		echo -e '\n\n$#' cat /etc/version_for_lg; cat /etc/version_for_lg || err=11
		echo -e '\n\n$#' cat /proc/cmdline; printf '%s\n' $(cat /proc/cmdline) || err=11
		echo -e '\n\n$#' export; export | sort || err=10
		echo -e '\n\n$#' printenv; printenv | sort || err=12
		echo -e '\n\n$# cramfs magic'
		# LG rc.local and BCM lginit sh script
		APP_XIP=`cat /proc/cmdline | awk -v RS='[ ]' -F= '/appxip_addr=/ { print $2 }'`
		FONT_XIP=`cat /proc/cmdline | awk -v RS='[ ]' -F= '/fontxip_addr=/ { print $2 }'`
		if [ "${APP_XIP}" != "" ] && [ "${APP_XIP}" != "0x0" ]; then
			cramfs_magic=`./busybox devmem $((APP_XIP+16)) 64` || { err=13; echo 'ERROR: devmem APP_XIP+16'; }
			release_magic=`./busybox devmem $((APP_XIP+1024*4)) 32` || { err=13; echo 'ERROR: devmem APP_XIP+1024*4'; }
			[ "$cramfs_magic" = "$CRAMFS_MAGIC" ] && echo -n 'OK: ' || echo -n 'ERROR: '; echo "$cramfs_magic ($CRAMFS_MAGIC)"
			[ "$release_magic" = "$RELEASE_MAGIC" ] && echo -n 'OK: ' || echo -n 'ERROR: '; echo "$release_magic ($RELEASE_MAGIC)"
		fi
		if [ "${FONT_XIP}" != "" ] && [ "${FONT_XIP}" != "0x0" ]; then
			cramfs_magic=`./busybox devmem $((FONT_XIP+16)) 64` || { err=13; echo 'ERROR: devmem FONT_XIP+16'; }
			[ "$cramfs_magic" = "$CRAMFS_MAGIC" ] && echo -n 'OK: ' || echo -n 'ERROR: '; echo "$cramfs_magic ($CRAMFS_MAGIC)"
		fi
		echo -e '\n\n$#' hostname; hostname || err=12
		echo -e '\n\n$#' cat /proc/filesystems; cat /proc/filesystems || err=11
		echo -e '\n\n$#' busybox; busybox || err=12
		echo -e '\n\n$#' help; help || err=10
	exit $err ) >> "$infofile" || err=$?; sync; echo 3 > /proc/sys/vm/drop_caches; sleep 1
	( echo -ne '\n\n#$# INFO: '; date
		echo -e '\n\n$#' dmesg; echo "$dmesg" || err=15
		for i in /lg/model/* /mnt/lg/cmn_data/*exc_log_[0-9]*.txt /lgsw/* /etc/init.d/* /etc/rc.d/* \
			/mnt/lg/user/lgmod/init/*; do [ ! -f "$i" ] && continue
			echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
			echo -e '\n\n$#' cat "$i"; cat "$i" || err=16
		done; echo '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>'
		echo -e '\n\n$# list some files'
		ls -lR /etc /mnt/lg/lginit /mnt/lg/user /mnt/lg/model /mnt/lg/lgapp /usr/local /mnt/lg/bt /mnt/lg/ciplus /mnt/lg/cmn_data /mnt/lg/res/lgres /mnt/lg/res/lgfont
		ls -l /home/lgmod /mnt/lg/res/estreamer /mnt/addon /mnt/addon/* /mnt/addon/*/* /mnt/addon/*/*/*
	exit $err ) >> "$infofile" || err=$?; sync; echo 3 > /proc/sys/vm/drop_caches; sleep 1
	( echo -ne '\n\n#$# INFO: '; date
		echo -e '\n\n$# dump boot version (/dev/mtd1)'
		s=7;w=5;m=3;cat /dev/mtd1 |tr [:space:] ' '|tr -c ' [:alnum:][:punct:]' '\n'|sed -e'/[a-zA-Z]\{'$m'\}\|[0-9]\{'$m'\}/!d' \
			-e'/[-_=/\.:0-9a-zA-Z]\{'$w'\}/!d' -e's/  \+/ /g' -e'/.\{'$s'\}/!d'| head -n5 || err=18
		echo -e '\n\n$# dump boot version (/dev/mtd5)'
		s=7;w=5;m=3;cat /dev/mtd5 |tr [:space:] ' '|tr -c ' [:alnum:][:punct:]' '\n'|sed -e'/[a-zA-Z]\{'$m'\}\|[0-9]\{'$m'\}/!d' \
			-e'/[-_=/\.:0-9a-zA-Z]\{'$w'\}/!d' -e's/  \+/ /g' -e'/.\{'$s'\}/!d'| head -n5 || err=18
	exit $err ) >> "$infofile" || err=$?; sync; echo 3 > /proc/sys/vm/drop_caches; sleep 1
	( echo -ne '\n\n#$# INFO: '; date
		echo -e '\n\n$# dump RELEASE version'
		f=/mnt/lg/lgapp/RELEASE; b=10000; s=$(stat -c%s $f); s=$((s/b*8/17)); flag=''
		dd bs=$b skip=$s count=300 if=$f|tr [:space:] ' '|tr -c ' [:alnum:][:punct:]' '\n'| \
			grep '....'|grep -m2 -B1 -A5 swfarm || { err=19; flag=1; }
		dd bs=$b skip=$((s+600)) count=300 if=$f|tr [:space:] ' '|tr -c ' [:alnum:][:punct:]' '\n'| \
			grep '....'|grep -m2 -B1 -A10 swfarm || { err=19; flag=1; }
		if [ -n "$flag" ]; then cat $f|tr [:space:] ' '|tr -c ' [:alnum:][:punct:]' '\n'| \
			grep '....'|grep -m2 -B1 -A10 swfarm || err=18; fi
	exit $err ) >> "$infofile" || err=$?; sync; echo 3 > /proc/sys/vm/drop_caches; sleep 1
	( echo -ne '\n\n#$# INFO: '; date
		echo -e '\n\n$# strings lginit (lg-init)'
		f=/mnt/lg/lginit/lg-init; [ ! -f $f ] && { f=/mnt/lg/lginit/lginit; [ -f $f ] && md5sum $f; }
		w=5;m=3;[ -f $f ] && cat $f |tr [:space:] ' '|tr -c ' [:alnum:][:punct:]' '\n'|sed -e'/[a-zA-Z]\{'$m'\}\|[0-9]\{'$m'\}/!d' \
			-e'/[-_=/\.:0-9a-zA-Z]\{'$w'\}/!d' -e's/  \+/ /g'| head -n70 || err=18
		echo -e '\n\n$# strings boot (/dev/mtd1)'
		s=7;w=5;m=3;cat /dev/mtd1 |tr [:space:] ' '|tr -c ' [:alnum:][:punct:]' '\n'|sed -e'/[a-zA-Z]\{'$m'\}\|[0-9]\{'$m'\}/!d' \
			-e'/[-_=/\.:0-9a-zA-Z]\{'$w'\}/!d' -e's/  \+/ /g' -e'/.\{'$s'\}/!d'| tail -n35 || err=18
		echo -e '\n\n$# strings boot (/dev/mtd5)'
		s=7;w=5;m=3;cat /dev/mtd5 |tr [:space:] ' '|tr -c ' [:alnum:][:punct:]' '\n'|sed -e'/[a-zA-Z]\{'$m'\}\|[0-9]\{'$m'\}/!d' \
			-e'/[-_=/\.:0-9a-zA-Z]\{'$w'\}/!d' -e's/  \+/ /g' -e'/.\{'$s'\}/!d'| tail -n35 || err=18
		echo -e '\n\n$#' diff /dev/mtd1 /dev/mtd5; diff /dev/mtd1 /dev/mtd5
	exit $err ) >> "$infofile" || err=$?; sync; echo 3 > /proc/sys/vm/drop_caches; sleep 1
	#( echo -ne '\n\n#$# INFO: '; date
	#	# backup partitions
	#	echo -e '\n\n$# diff backup /dev/mtd# '
	#	diff /dev/mtd15 /dev/mtd20 && diff /dev/mtd16 /dev/mtd21 && diff /dev/mtd17 /dev/mtd22
	#	# cramfs - no need, we check the same below
	#	appxip_addr=`cat /proc/cmdline | awk -v RS='[ ]' -F= '/appxip_addr=/ { print $2 }'`
	#	echo -e '\n\n$# dump lgapp (/dev/mem)'; ./busybox hexdump /dev/mem -vs$((appxip_addr)) -n160 -e'4 "%08x "" " 16 "%_p"" " 4 "%08x "" " 10 "%_p" 1/2 " %04x" "\n" 7 "%08x "" " 7 "%_p"" " 1/1 "%02x " 4 "%08x " "\n" 10 "%_p" 1/2 " %04x" 3 " %08x"" " 15 "%_p" 3 " %08x" "\n"' || err=13
	#	echo -e '\n\n$# dump RELEASE (/dev/mem)'; ./busybox hexdump /dev/mem -vs$((appxip_addr+1024*4)) -n512 -e'128 "%_p" "\n"' || err=13
	#exit $err ) >> "$infofile" || err=$?; sync; echo 3 > /proc/sys/vm/drop_caches; sleep 1
	( echo -ne '\n\n#$# INFO: '; date ) >> "$infofile" || err=10; sync
	[ $err != 0 ] && echo "Error($err): Info file failed: $infofile"
fi

# prepare
type which && which printenv lsmod ps ls df fdisk hostname dmesg diff head tail tr dd &&
	which grep sort md5sum awk mkdir stat killall pkill sleep cut sed free &&
	which flash_eraseall cat sync || err=21; #rm mv
[ -f ./busybox ] || { err=22; echo "Error($err): File not found: busybox"; }; #hexdump devmem tar
if [ -n "$install" ]; then
	[ -f "$rootfs" ] || { err=23; echo "Error($err): File not found: $rootfs"; }
	flash_eraseall --version | sed -e '2,$d' ||
		{ err=24; echo "ERROR($err): 'flash_erasesall' something??!"; }
	I=$(cat /proc/mtd | sed -e 's/:.*"\(.*\)"/\1/' -e 's/^mtd//' | grep -v ' \|0bbminfo\|1boot\|2mtdinfo\|5boot\|6crc32info\|8logo\|10nvram\|15kernel\|16lgapp\|20kernel\|22lgres' | sort -n) ||
		{ err=25; echo "ERROR($err): /proc/mtd (install)"; }
	[ "$(echo ${I//mtd})" = '3rootfs 4lginit 7model 9cmndata 11user 12ezcal 13estream 14opsrclib 17lgres 18lgfont 19addon 21lgapp 23cert 24authcxt' ] ||
		{ err=26; echo "ERROR($err): TV partitions mismath"; }
fi
if [ -n "$install" ] && [ -z "$update" ] && [ -n "$lginitmd5" ]; then
	if [ -f /mnt/lg/lginit/lginit ] && [ ! -f /mnt/lg/lginit/lg-init ]; then
		md5cur=$(md5sum /mnt/lg/lginit/lginit) && [ "$lginitmd5" = "${md5cur%% *}" ] ||
			{ err=27; echo "ERROR($err): md5 mismatch: /mnt/lg/lginit/lginit"; }
	fi
fi
[ $err != 0 ] && exit $err
if [ -n "$install" ]; then
	md5chk=$(cat "$rootfs.md5") && md5cur=$(md5sum "$rootfs") &&
		[ "${md5chk%% *}" = "${md5cur%% *}" ] ||
		{ err=28; echo "ERROR($err): md5 mismatch: $rootfs"; }
	md5chk=$(cat "$lginit.md5") && md5cur=$(md5sum "$lginit") &&
		[ "${md5chk%% *}" = "${md5cur%% *}" ] ||
		{ err=29; echo "ERROR($err): md5 mismatch: $lginit"; }
	# LG rc.local and BCM lginit sh script
	APP_XIP=`cat /proc/cmdline | awk -v RS='[ ]' -F= '/appxip_addr=/ { print $2 }'`
	FONT_XIP=`cat /proc/cmdline | awk -v RS='[ ]' -F= '/fontxip_addr=/ { print $2 }'`
	if [ "${APP_XIP}" != "" ] && [ "${APP_XIP}" != "0x0" ]; then
		cramfs_magic=`./busybox devmem $((APP_XIP+16)) 64`
		release_magic=`./busybox devmem $((APP_XIP+1024*4)) 32`
		[ "$cramfs_magic" != "$CRAMFS_MAGIC" ] &&
			{ err=101; echo "ERROR($err): lgapp_xip - WRONG MAGIC"; }
		[ "$release_magic" != "$RELEASE_MAGIC" ] &&
			{ err=102; echo "ERROR($err): RELEASE - WRONG MAGIC"; }
	fi
	if [ "${FONT_XIP}" != "" ] && [ "${FONT_XIP}" != "0x0" ]; then
		cramfs_magic=`./busybox devmem $((FONT_XIP+16)) 64`
		[ "$cramfs_magic" != "$CRAMFS_MAGIC" ] &&
			{ err=103; echo "ERROR($err): lgfont_xip - WRONG MAGIC"; }
	fi
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
	I=$(cat /proc/mtd | sed -e 's/:.*"\(.*\)"/_\1/' | grep -v ' ') ||
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
	./busybox tar cvzpf "backup-$date-user.tar.gz" /mnt/lg/user ||
		echo "WARNING: Create archive failed: /usr/lg/user"
	./busybox tar cvzpf "backup-$date-cmn_data.tar.gz" /mnt/lg/cmn_data ||
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


# install - free mem
if [ -n "$install" ] && [ -n "$kill" ]; then
	echo 'NOTE: Freeing memory (killing daemons) ...'
	for i in $KILL; do pkill $i && echo $i; killall $i 2> /dev/null && echo $i; done
	sleep 2
fi
if [ -n "$install" ]; then
	sync; echo 3 > /proc/sys/vm/drop_caches; sleep 1
	free=$(free | sed -e '2!d' -e 's/ \+/+/g' | cut -d + -f 4,6) &&
		free=$(( $free )) && [ $free -ge $required_free_ram ] ||
		{ err=45; echo "ERROR($err): Low memory - very few bytes available ($free < $required_free_ram)??!"; }
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
		echo '	You could copy and save all messages above.'
		echo '	Proper nvram backup is created after restart (remote control).'
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
