#!/bin/sh

cd "${0%/*}"

# config
date=$(date '+%Y%m%d-%H%M%S')
infofile="backup-$date-info.txt"
bkpdir="backup-$date"; # TODO: long file names?
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
required_free_ram=10000


# defaults
[ -f /etc/lgmod.sh ] && update=1 || update=''
[ -n "$update" ]     && backup='' || backup=1
install_backup=1


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
	[ "$i" = nobackup ]   && install_backup=''
	[ "$i" = dryrun ]     && dryrun=1
done
[ -n "$dryrun" ] && TEST_ECHO=echo || TEST_ECHO=''


# info
if [ -n "$info" ]; then
	(
	for i in /proc/version /proc/cpuinfo /proc/mounts /proc/mtd /etc/version_for_lg \
		/lg/model/RELEASE.cfg /etc/init.d/rcS /etc/rc.d/rc.sysinit /etc/rc.d/rc.local; do
		echo; echo '#' cat "$i"; cat "$i"
	done
	echo; echo '#' free; free;
	echo; echo '#' lsmod; lsmod;   echo; echo '#' printenv; printenv
	echo; echo '#' export; export; echo; echo '#' dmesg; dmesg
	) > "$infofile" || { err=10; echo "Error($err): can't create '$infofile' file"; exit $err; }
fi


# prepare
err=0
type which > /dev/null      || { err=20; echo "Curse($err): The witch is not available!"; }
which sync > /dev/null      || { err=21; echo "Error($err): 'sync' is out of sync!"; }
which sed                     || err=22
which stat                    || err=23
which md5sum                  || err=24
which cat > /dev/null       || { err=25; echo "Error($err): Your cat is somehow missing!"; }
#if [ -n "$install" ] && [ -z "$update" ] && [ ! -f "$lginit" ]; then
#	which rm                  || err=26
#	which mv                  || err=26
#	if [ -d squashfs-root ]; then
#		rm -r squashfs-root || { err=26; echo "Error($err): can't remove 'squashfs-root'"; }
#		sync
#	fi
#fi
if [ -n "$install" ]; then
	[ -f "$rootfs" ]        || { err=27; echo "Error($err): file not found '$rootfs'"; }
	which flash_eraseall      || err=27
	flash_eraseall --version | sed -e '2,$d' ||
		{ err=29; echo "ERROR($err): 'flash_erasesall' something??!"; }
fi
[ $err != 0 ] && exit $err
if [ -n "$install" ]; then
	md5cur=$(md5sum "$rootfs") && md5chk=$(cat "$rootfs.md5") &&
		[ "${md5cur% *}" = "${md5chk% *}" ] ||
		{ err=28; echo "ERROR($err): '$rootfs' md5 mismatch"; }
fi
[ $err != 0 ] && exit $err


# backup
if [ -n "$backup" ] || [ -n "$install_backup" ]; then
	which mkdir             || err=31
	[ -d "$bkpdir" ]      && { err=32; echo "Error($err): '$bkpdir' directory exist"; }
	mkdir -p "$bkpdir"    || { err=33; echo "Error($err): can't create '$bkpdir' directory"; }
fi
I=''
if [ -n "$backup" ]; then
	echo 'Backup: cat /proc/mtd'
	I=$(cat /proc/mtd | sed -e 's/:.*"\(.*\)"/_\1/' | grep -v ' ') ||
		{ err=34; echo "ERROR: $err"; }
elif [ -n "$install_backup" ]; then
	#I="${ROOTFS#/dev/}_rootfs ${LGINIT#/dev/}_lginit"
	I="${ROOTFS#/dev/}_rootfs"
fi
if [ -n "$I" ]; then
	[ $err != 0 ] && exit $err
	for i in $I; do
		echo "Backup: $i ..."
		[ -e "/dev/${i%_*}" ] || { err=35; echo "ERROR: $err"; }
		cat "/dev/${i%_*}" > "$bkpdir/$i" || { err=36; echo "ERROR: $err"; }
		sync && echo 3 > /proc/sys/vm/drop_caches || { err=37; echo "ERROR: $err"; }
	done
	# TODO: tar from LG does not know 'z' ???
	#	Usage: tar -[cxtvO] [-X FILE] [-f TARFILE] [-C DIR] [FILE(s)]...
	#tar czpf "backup-$date-user.tar.gz" /mnt/lg/user ||
	#	{ err=37; echo 'ERROR($err): Backup /usr/lg/user failed'; }
	#tar czpf "backup-$date-cmn_data.tar.gz" /mnt/lg/cmn_data ||
	#	{ err=38; echo 'ERROR($err): Backup /usr/lg/cmn_data failed'; }
	#sync
	size=$(stat -c %s "$bkpdir/mtd3_rootfs") && [ $rootfs_size = "$size" ] ||
		{ err=39; echo 'ERROR($err): Invalid file size: mtd3_rootfs'; }
	#size=$(stat -c %s "$bkpdir/mtd4_lginit") && [ $lginit_size = "$size" ] ||
	#	{ err=40; echo 'ERROR($err): Invalid file size: mtd4_lginit'; }
	[ $err != 0 ] && exit $err
	echo 'BACKUP DONE! SUCCESS!'
fi


# install
if [ -n "$install" ]; then
	## create lginit sqfs file
	#if [ -z "$update" ]; then
	#	if [ ! -f "$lginit" ]; then
	#		./unsquashfs "$bkpdir/mtd4_lginit" &&
	#			mv squashfs-root/lginit squashfs-root/lg-init &&
	#			./mksquashfs squashfs-root "$lginit" -le -all-root -noappend ||
	#			{ err=41; echo "ERROR($err): lginit - unsquash/mksquash failed!"; }
	#		rm -r squashfs-root
	#		sync
	#	fi
	#	# check partition image size
	#	size=$(stat -c %s "$lginit") && size4096=$(( $size / 4096 * 4096 )) &&
	#		[ "$size" -le "$lginit_size" ] ||
	#		{ err=42; echo "ERROR($err): '$lginit' size is too big for flashing"; }
	#	[ "$size" != "$size4096" ] &&
	#		{ err=43; echo "ERROR($err): '$lginit' is not multiple of 4096"; }
	#	[ $err != 0 ] && exit $err
	#fi

	# TODO: first copy partition images to /tmp - just in case (xeros)

	# free ram
	if [ -n "$kill" ]; then
		# lgmod services: udhcpc ntpd telnetd tcpsvd djmount httpd
		echo 'NOTE: Freeing memory (killing daemons)...'
		for i in udhcpc ntpd tcpsvd djmount; do
			killall "$i"; pkill "$i";
		done
		sleep 2
	fi
	sync; echo 3 > /proc/sys/vm/drop_caches; sleep 2

	# check free ram
	free=$(free | sed -e '2!d' -e 's/ \+/+/g' | cut -d + -f 4,6) &&
		free=$(( $free )) && [ $free -gt $required_free_ram ] ||
		{ err=44; echo "ERROR($err): Low memory - very few free bytes available ($free < $required_free_ram)??!"; }


	# erase & write: lginit
	if [ $err = 0 ] && [ -z "$update" ]; then
		for i in 1 2; do
			for j in 1 2; do
				echo "$j: flash_eraseall $LGINIT"; ERR=0
				$TEST_ECHO flash_eraseall "$LGINIT" && break; ERR=$?
				if [ $ERR = 138 ]; then echo "ERROR: $err ($ERR OK?)"; # Bus error?
				else err=45; echo "ERROR: $err ($ERR Critical!)"; fi
				# TODO: try alternative erase (xeros)
				[ $j -lt 2 ] && echo "ERROR: Trying again..."
			done

			#echo "$i: cat $lginit > $LGINIT"; ERR=0
			#[ -n "$dryrun" ] && break
			#cat "$lginit" > "$LGINIT" && break; ERR=$?
			#err=46; echo "ERROR: $err ($ERR Critical!!!)"
			#[ $i -lt 2 ] && echo "ERROR: Trying again..."
			break
		done
	fi

	# run once and just before erase rootfs
	echo | cat || { err=47; echo "Error($err): Cat failed."; }

	# erase & write: rootfs
	for i in 1 2; do
		for j in 1 2; do
			echo "$j: flash_eraseall $ROOTFS"; ERR=0
			$TEST_ECHO flash_eraseall "$ROOTFS" && break; ERR=$?
			if [ $ERR = 138 ]; then echo "ERROR: $err ($ERR OK?)"; # Bus error?
			else err=48; echo "ERROR: $err ($ERR Critical!)"; fi
			# TODO: try alternative erase (xeros)
			[ $j -lt 2 ] && echo "ERROR: Trying again..."
		done

		echo "$i: cat $rootfs > $ROOTFS"; ERR=0
		[ -n "$dryrun" ] && break
		cat "$rootfs" > "$ROOTFS" && break; ERR=$?
		err=49; echo "ERROR: $err ($ERR Critical!!!)"
		[ $i -lt 2 ] && echo "ERROR: Trying again..."
	done

	sync
	if [ $err = 0 ]; then
		echo 'FLASH DONE! SUCCESS! You can "reboot" now.'
		echo '	(Also you could copy and save all messages above.)'
	else
		echo 'WARNING: Something is wrong!!!'
		echo '	1) do not touch TV and remote control'
		echo '	2) save and check messages above (copy messages from screen'
		echo '		or find the log file of your serial terminal program)'
		echo '	3) ask for assistance (forum/irc)'
		echo 'NOTE: Do it your self (advanced) - busybox binary is included in zip file'
		exit $err
	fi
fi


exit 0
