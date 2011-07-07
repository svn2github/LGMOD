TOPINC  = -I$(KERNEL_SRC)/include

CC	= $(CROSS_COMPILE)gcc
LD	= $(CROSS_COMPILE)ld

obj-m := pty.o
pty-objs := char-pty.o

all:
	make -C ${KERNEL_SRC} SUBDIRS=$(PWD) modules

${obj-m}: ${pty-objs}
	$(LD) -o ${obj-m} -r ${pty-objs}

clean:
	make -C ${KERNEL_SRC} SUBDIRS=$(PWD) clean
