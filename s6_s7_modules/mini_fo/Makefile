#
# Makefile for mini_fo 2.4 and 2.6 Linux kernels
#
# Copyright (C) 2004, 2005 Markus Klotzbuecher <mk@creamnet.de>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version
# 2 of the License, or (at your option) any later version.
#

TOPINC  = -I$(KERNEL_SRC)/include

CC	= $(CROSS_COMPILE)gcc
LD	= $(CROSS_COMPILE)ld

obj-m := mini_fo.o
mini_fo-objs := meta.o dentry.o file.o inode.o main.o super.o state.o aux.o

all:
	make -C ${KERNEL_SRC} SUBDIRS=$(PWD) modules

${obj-m}: ${mini_fo-objs}
	$(LD) -o ${obj-m} -r ${mini_fo-objs}

clean:
	make -C ${KERNEL_SRC} SUBDIRS=$(PWD) clean
