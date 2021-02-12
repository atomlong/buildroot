setenv bootargs console=ttyS2,115200 panic=5 console=tty2 rootwait root=/dev/mmcblk0p2 earlyprintk rw
load mmc 0:1 0x41000000 zImage
load mmc 0:1 0x41800000 sun8i-v3s-strawberrypi-zero.dtb
bootz 0x41000000 - 0x41800000
