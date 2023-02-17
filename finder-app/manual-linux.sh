#!/bin/bash
# Script outline to install and build kernel.
# Author: Siddhant Jajoo.

set -e
set -u

this_script_dir=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
OUTDIR=$(readlink -f "${1:-/tmp/aeld}")
KERNEL_REPO=git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git
KERNEL_VERSION=v5.1.10
BUSYBOX_VERSION=1_33_1
FINDER_APP_DIR=$(realpath $(dirname $0))
ARCH=arm64
CROSS_COMPILE=aarch64-none-linux-gnu-

cc_path=$(command -v "$CROSS_COMPILE"gcc) || { echo Error: "$CROSS_COMPILE"gcc not in PATH; exit 1; }
sysroot="$($cc_path -print-sysroot)"
echo "Using sysroot ${sysroot}"

echo "Using directory ${OUTDIR} for output"

mkdir -p ${OUTDIR}

cd "$OUTDIR"
if [ ! -d "${OUTDIR}/linux-stable" ]; then
    #Clone only if the repository does not exist.
	echo "CLONING GIT LINUX STABLE VERSION ${KERNEL_VERSION} IN ${OUTDIR}"
	git clone ${KERNEL_REPO} --depth 1 --single-branch --branch ${KERNEL_VERSION}
fi
if [ ! -e ${OUTDIR}/linux-stable/arch/${ARCH}/boot/Image ]; then
    cd linux-stable
    echo "Checking out version ${KERNEL_VERSION}"
    git checkout ${KERNEL_VERSION}

    # This will select for the default qemu virtual target
    make ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" defconfig
    make ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" -j$(nproc) all
    make ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" -j$(nproc) modules
    make ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" -j$(nproc) dtbs
fi

echo "Adding the Image in outdir"
cp "$OUTDIR/linux-stable/arch/$ARCH/boot/Image" "$OUTDIR"

echo "Creating the staging directory for the root filesystem"
cd "$OUTDIR"
if [ -d "${OUTDIR}/rootfs" ]
then
	echo "Deleting rootfs directory at ${OUTDIR}/rootfs and starting over"
    sudo rm  -rf ${OUTDIR}/rootfs
fi

# Create necessary base directories
mkdir "$OUTDIR"/rootfs
for dir in bin dev etc home lib lib64 proc sbin sys tmp usr/bin usr/lib usr/sbin var/log; do
mkdir -p "$OUTDIR/rootfs/$dir"
done

cd "$OUTDIR"
if [ ! -d "${OUTDIR}/busybox" ]
then
git clone git://busybox.net/busybox.git
    cd busybox
    git checkout ${BUSYBOX_VERSION}
    make ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" distclean
    make ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" defconfig
else
    cd busybox
fi

# https://git.busybox.net/busybox/tree/INSTALL
# Make and install busybox
make ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" -j$(nproc)
make CONFIG_PREFIX="$OUTDIR/rootfs" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" install

add_lib_deps()
{
  echo "Adding lib deps to list for ${1:?bin required}"

  lib_dir=/lib
  if file "$1" | grep "64-bit">/dev/null; then
    lib_dir=/lib64
  fi

  if file "$1" | grep "dynamically linked">/dev/null; then
    # The interpreter listing includes the "/lib" prefix already
    libdeps+=( "$(${CROSS_COMPILE}readelf -a "$1" | grep "program interpreter" | awk '{print $4}' | tr -d ']')" )
  fi

  # These ones do not include the "/lib" or "/lib64" prefix so we have to add one
  for dep in $(${CROSS_COMPILE}readelf -a "$1" | grep  "Shared library" | awk '{print $5}' | tr -d '[]'); do
    libdeps+=( "$lib_dir/$dep" )
  done
}
add_lib_deps "$OUTDIR/rootfs/bin/busybox"

# Add library dependencies to rootfs
for dep in "${libdeps[@]}"; do
  candidates=$(find "$sysroot" -path "*$dep")
  if [ -z "$candidates" ]; then
    echo "ERROR: No file found for dependency $dep"
    continue
  fi
  # There should be only one candidate, but just in case iterate through.
  # This will cause only the final candidate to exist, but the copy operations
  # will at least be in the logs.
  for candidate in $candidates; do
    cp -a -v "$candidate" "$OUTDIR/rootfs/$dep"
    # Look for a symlink and also copy the pointed to library alongisde
    pointee_filename=$(readlink $candidate) || continue
    pointee_path="$(readlink -e $candidate)" || continue
    final_path="$OUTDIR/rootfs/$(dirname $dep)/$pointee_filename"
    cp -a -v "$pointee_path" "$final_path"
  done
  for candidate in $candidates; do
    "$CROSS_COMPILE"strip --strip-unneeded "$OUTDIR/rootfs/$dep"
  done
done

# Make device nodes
# See Mastering Embedded Linux Programming 2nd Edition pg 140
# The major and minor numbers are in kernel source devices.txt
sudo mknod -m 666 "$OUTDIR/rootfs/dev/null" c 1 3
sudo mknod -m 600 "$OUTDIR/rootfs/dev/console" c 5 1

# Clean and build the writer utility
cd $this_script_dir
make clean
make CROSS_COMPILE="$CROSS_COMPILE"

# Copy the finder related scripts and executables to the /home directory
# on the target rootfs
cp -a -v ./writer "$OUTDIR/rootfs/home"
# TODO: finish assignment, copying scripts into rootfs to test in qemu. See assignment instructions

# Chown the root directory
sudo chown -R $(whoami) "$OUTDIR/rootfs"

# Create initramfs.cpio.gz
cd "$OUTDIR/rootfs"
find . | cpio -H newc -ov --owner root:root | gzip -f > "$OUTDIR"/initramfs.cpio.gz
