#!/bin/bash

# Define variables
LFS=/mnt/lfs
TARGET_DIR=$LFS
SRC_DIR=$LFS/sources
BUILD_DIR=$LFS/build
ISO_DIR=$LFS/iso
TARBALLS=(
    "https://ftp.gnu.org/gnu/binutils/binutils-2.36.1.tar.xz"
    "https://ftp.gnu.org/gnu/gcc/gcc-10.2.0/gcc-10.2.0.tar.xz"
    "https://www.kernel.org/pub/linux/kernel/v5.x/linux-5.10.17.tar.xz"
    "https://ftp.gnu.org/gnu/glibc/glibc-2.33.tar.xz"
    "https://ftp.gnu.org/gnu/ncurses/ncurses-6.2.tar.gz"
    "https://invisible-island.net/datafiles/release/dialog.tar.gz"
)

# Ensure required directories exist
mkdir -p $SRC_DIR $BUILD_DIR $ISO_DIR/boot/grub

# Download tarballs
for url in "${TARBALLS[@]}"; do
    wget -P $SRC_DIR $url
done

# Function to extract and enter source directories
extract_and_cd() {
    tarball=$1
    tar -xf $SRC_DIR/$(basename $tarball) -C $BUILD_DIR
    cd $BUILD_DIR/$(basename $tarball .tar.*)
}

# Build Binutils
extract_and_cd "https://ftp.gnu.org/gnu/binutils/binutils-2.36.1.tar.xz"
mkdir -v build
cd build
../configure --prefix=/tools --with-sysroot=$LFS --target=$(uname -m)-lfs-linux-gnu --disable-nls --disable-werror
make
make install
cd $BUILD_DIR

# Build GCC
extract_and_cd "https://ftp.gnu.org/gnu/gcc/gcc-10.2.0/gcc-10.2.0.tar.xz"
tar -xf $SRC_DIR/gmp-6.2.0.tar.xz
tar -xf $SRC_DIR/mpfr-4.1.0.tar.xz
tar -xf $SRC_DIR/mpc-1.2.1.tar.gz
mv -v gmp-6.2.0 gmp
mv -v mpfr-4.1.0 mpfr
mv -v mpc-1.2.1 mpc
mkdir -v build
cd build
../configure --target=$(uname -m)-lfs-linux-gnu --prefix=/tools --with-glibc-version=2.11 --with-sysroot=$LFS --with-newlib --without-headers --disable-nls --disable-shared --disable-decimal-float --disable-threads --disable-libatomic --disable-libgomp --disable-libquadmath --disable-libssp --disable-libvtv --disable-libstdcxx --enable-languages=c,c++
make all-gcc
make all-target-libgcc
make install-gcc
make install-target-libgcc
cd $BUILD_DIR

# Build Linux Kernel
extract_and_cd "https://www.kernel.org/pub/linux/kernel/v5.x/linux-5.10.17.tar.xz"
make mrproper
make headers
cp -rv usr/include/* /tools/include
cd $BUILD_DIR

# Build Glibc
extract_and_cd "https://ftp.gnu.org/gnu/glibc/glibc-2.33.tar.xz"
mkdir -v build
cd build
../configure --prefix=/tools --host=$(uname -m)-lfs-linux-gnu --build=$(../scripts/config.guess) --enable-kernel=3.2 --with-headers=/tools/include libc_cv_forced_unwind=yes libc_cv_ctors_header=yes libc_cv_c_cleanup=yes
make
make install
cd $BUILD_DIR

# Build Ncurses
extract_and_cd "https://ftp.gnu.org/gnu/ncurses/ncurses-6.2.tar.gz"
./configure --prefix=/tools --with-shared --without-debug --without-ada --enable-widec --enable-overwrite
make
make install
cd $BUILD_DIR

# Build Dialog
extract_and_cd "https://invisible-island.net/datafiles/release/dialog.tar.gz"
./configure --prefix=/tools --with-ncursesw
make
make install
cd $BUILD_DIR

# Create basic TUI script
cat << 'EOF' > $LFS/tools/bin/tui.sh
#!/bin/bash
while true; do
    CHOICE=$(dialog --title "TUI Menu" --menu "Choose an option:" 15 40 4 \
    1 "Option 1" \
    2 "Option 2" \
    3 "Exit" 3>&2 2>&1 1>&3)
    
    case $CHOICE in
        1)
            dialog --msgbox "You chose Option 1!" 10 30
            ;;
        2)
            dialog --msgbox "You chose Option 2!" 10 30
            ;;
        3)
            break
            ;;
    esac
done
EOF
chmod +x $LFS/tools/bin/tui.sh

# Create init script for TUI
cat << 'EOF' > $LFS/tools/bin/init.sh
#!/bin/bash
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
exec /tools/bin/tui.sh
EOF
chmod +x $LFS/tools/bin/init.sh

# Create grub config
cat << 'EOF' > $ISO_DIR/boot/grub/grub.cfg
set default=0
set timeout=5

menuentry "TUI Linux" {
    linux /boot/vmlinuz root=/dev/ram0 init=/tools/bin/init.sh
    initrd /boot/initrd.img
}
EOF

# Create initramfs
cd $LFS/tools
find . | cpio -o -H newc | gzip > $ISO_DIR/boot/initrd.img

# Copy kernel image
cp $BUILD_DIR/linux-5.10.17/arch/x86/boot/bzImage $ISO_DIR/boot/vmlinuz

# Create the ISO image
grub-mkrescue -o $LFS/tui_linux.iso $ISO_DIR

echo "ISO image created at $LFS/tui_linux.iso"
