#!/bin/sh

# root device
ROOTDEV="mmcblk0p7"
# mount options
MOUNTOPTS="ro"
# the init program
INIT="/sbin/init"
# compression
COMPRESSION="gz"
# firmware archive
FW_ARCHIVE="./firmware_all.tar.gz"

# output file name
OUTFILE="initramfs.cpio"

help() {
    echo "Usage: " $0 " [arguments]"
    echo "Available options:"
    echo "  -h           print this message"
    echo "  -o FILENAME  write into FILENAME (uncompressed, default: $OUTFILE)"
    echo "  -d DEVICE    the partition containing rootfs (default: $ROOTDEV)"
    echo "  -i INIT      the init program to launch (default: $INIT)"
    echo "  -c COMP      the compression format (default: $COMPRESSION)"
    echo "  -f FIRMWARE  the path to a firmware archive (default: $FW_ARCHIVE)"
    echo "  -m MOUNTOPTS the mount opts (default: $MOUNTOPTS)"
    echo ""
    echo "By default, rootfs is on /data (mmcblk0p7), not in any subdir."
    echo "Keep in mind that using a subdirectory might not always work right"
    echo "and is considered EXPERIMENTAL, so use at your own risk. It exists"
    echo "only to cover the case when you want to dual boot your system with"
    echo "Android."
    echo "The -d option allows you to choose the partition on which your root"
    echo "filesystem is present. You might want to use this if you repartition"
    echo "your device or if you installed the OS into /system (mmdcblk0p4)."
    echo "Overriding -i is only for if your rootfs doesn't use /sbin/init."
    echo "The choice of compression algorithmss is 'gz', 'none'."
}

while getopts o:d:i:c:f:m:h OPT; do
    case $OPT in
        o) OUTFILE=$OPTARG ;;
        d) ROOTDEV=$OPTARG ;;
        i) INIT=$OPTARG ;;
        c) COMPRESSION=$OPTARG ;;
        f) FW_ARCHIVE=$OPTARG ;;
        m) MOUNTOPTS=$OPTARG ;;
        h) help; exit 0 ;;
        \?)
            echo "Unrecognized option: $OPTARG"
            help
            exit 1
        ;;
    esac
done

if [ ! -f "$FW_ARCHIVE" ]; then
    echo "firmware archive does not exist, exitting..."
    exit 1
fi

case $COMPRESSION in
    none)
        CMPCMD=""
        OUTFILE_COMP="$OUTFILE"
    ;;
    lz4)
        CMPCMD="lz4c"
        OUTFILE_COMP="$OUTFILE.lz4"
    ;;
    gz)
        CMPCMD="gzip"
        OUTFILE_COMP="$OUTFILE.gz"
    ;;
    xz)
        CMPCMD="xz"
        OUTFILE_COMP="$OUTFILE.xz"
    ;;
    *)
        echo "Unknown compression algorithm: $COMPRESSION"
        help
        exit 1
esac

compress() {
    case $COMPRESSION in
        gz)  gzip -9 -c "$1" > "$2" ;;
        *) true ;;
    esac
    if [ $? -ne 0 ]; then
        echo "Compression failed, exitting..."
        rm -f "$1" "$2"
        rm -rf output
        exit 1
    fi
}

if [ -n "$CMPCMD" ] && [ ! -x "$(command -v $CMPCMD)" ]; then
    echo "Compression tool '$CMPCMD' not found, exitting..."
    exit 1
fi

echo "Generating initramfs for rootfs on partition $ROOTDEV with init $INIT..."
echo ""

# fetch busybox
./get_busybox.sh
if [ $? -ne 0 ]; then
    echo "Failed getting busybox, exitting..."
    exit 1
fi

# cleanup
echo ""
echo "Cleanup..."
rm -f "$OUTFILE" "$OUTFILE_COMP"
rm -rf output

# pre-populate ramdisk structure
echo "Creating directory structure..."
mkdir output
mkdir output/dev
mkdir output/lib
mkdir output/sys
mkdir -p output/mnt/root

# config file
echo "Generating config file..."
cat << EOF >> output/conf
export ROOTDEV="${ROOTDEV}"
export MOUNTOPTS="${MOUNTOPTS}"
export INIT="${INIT}"
EOF

echo "Copying binaries..."
cp skel/init downloaded/busybox output

echo "Extracting firmware..."
cd output
tar xvf "../$FW_ARCHIVE"
if [ $? -ne 0 ]; then
    echo "Extracting firmware failed, exitting..."
    cd ..
    rm -rf output
    exit 1
fi
cd ..

# list contents first
echo ""
echo "initramfs contents:"
cd output
find .

# create the ramdisk
echo ""
echo "Creating initramfs..."
find . | cpio -o -H newc > ../$OUTFILE
cd ..

# compress
if [ -n "$CMPCMD" ]; then
    echo "Compressing initramfs..."
fi
compress "$OUTFILE" "$OUTFILE_COMP"

# cleanup
echo ""
echo "Final cleanup..."
rm -rf output
if [ "$OUTFILE" != "$OUTFILE_COMP" ]; then
    rm -f "$OUTFILE"
fi

echo "Initramfs created: $OUTFILE_COMP"
