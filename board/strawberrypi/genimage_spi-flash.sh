#!/usr/bin/env bash
FLASH_SZ_MB=${2}

pushd ${BINARIES_DIR}
dd if=/dev/zero of=spi-flash.img bs=1M count=${FLASH_SZ_MB}
dd if=u-boot-sunxi-with-spl.bin of=spi-flash.img bs=1K conv=notrunc
dd if=sun8i-v3s-strawberrypi-zero-flash.dtb of=spi-flash.img bs=1K seek=1024 conv=notrunc
dd if=zImage of=spi-flash.img bs=1K seek=1088 conv=notrunc
dd if=rootfs.jffs2 of=spi-flash.img bs=1K seek=5184 conv=notrunc
popd
