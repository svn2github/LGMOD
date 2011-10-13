TOPINC  = -I$(KERNEL_SRC)/include

CC	= $(CROSS_COMPILE)gcc
LD	= $(CROSS_COMPILE)ld

obj-m := asix.o dm9601.o pegasus.o

all:
	make -C ${KERNEL_SRC} SUBDIRS=$(PWD) modules


clean:
	make -C ${KERNEL_SRC} SUBDIRS=$(PWD) clean
