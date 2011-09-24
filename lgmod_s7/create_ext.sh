#!/bin/bash
dir=trunk/rootfs
cd ${0%/*}
if [ ! -d "$dir" ]; then
    echo "ERROR: $dir not found."
    exit 1
fi

if [ -d extroot ]; then
	cd extroot
	rm -f ../lgmod_S7_extroot.tar.gz
	tar czvf ../lgmod_S7_extroot.tar.gz */ *.deb
fi
