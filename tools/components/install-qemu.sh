#!/bin/bash

set -e

QEMU_VERSION="${1:-9.1.3}"

# parse /etc/os-release's ID_LIKE, and save it to a variable
OS_ID_LIKE=$(grep -oP '(?<=^ID_LIKE=).*' /etc/os-release | tr -d '"')


if [[ "$OS_ID_LIKE" == "debian" ]]; then
    sudo apt-get update
    sudo apt-get install -y git libglib2.0-dev libfdt-dev \
        libpixman-1-dev zlib1g-dev ninja-build build-essential \
        python3 python3-venv python3-pip
elif [[ "$OS_ID_LIKE" == "fedora" ]]; then
    sudo yum install -y ninja-build glib2-devel \
        zlib-devel pixman-devel
else
    echo "unsupported os ($OS_ID_LIKE)"
    exit 1
fi

# if libslirp is not installed, install it
if ! pkg-config --exists slirp; then
    pushd /tmp
    git clone https://gitlab.com/qemu-project/libslirp.git
    pushd /tmp/libslirp
    meson build
    ninja -C build install
    popd

    pkg-config --exists slirp
    echo "ok... libslirp installed"
fi

wget https://download.qemu.org/qemu-${QEMU_VERSION}.tar.xz \
    -O /tmp/qemu-${QEMU_VERSION}.tar.xz
tar -xf /tmp/qemu-${QEMU_VERSION}.tar.xz

pushd /tmp/qemu-${QEMU_VERSION}
./configure --target-list=x86_64-softmmu --enable-kvm --enable-slirp
make -j$(nproc)
sudo make install
popd
