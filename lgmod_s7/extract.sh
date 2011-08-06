#!/bin/sh
# NOTE: This script is exactly 15 lines long
echo 'Extract ...'; base="${0%.sh.zip}"; tail -n +16 "$0" > "$base.zip"
mkdir -p "$base"; echo 3 > /proc/sys/vm/drop_caches; sleep 1
unzip -o "$base.zip" -d "$base"; sync

INFO="$base/changelog.txt"; ip=''; [ -f /mnt/lg/user/lgmod/ftp ] && ! tty > /dev/null &&
	ip=$(ifconfig eth0|grep addr|sed -e'2!d' -e's/^[^:]*://' -e's/ .*//'|grep -v 255 2>/dev/null)
[ -n "$ip" ] && INFO="<a href='ftp://$ip/${INFO#$(cat /mnt/lg/user/lgmod/ftp)}'>$INFO</a>"

echo "Info: $INFO"; echo -e "To install, run:\nsh $base/install.sh install \n"

[ -n "$1" ] && 	{ exec sh "$base/install.sh" "$@"; exit; }

exit; # NOTE: This is the last line #15
