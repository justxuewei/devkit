#!/bin/bash

HYPERVISOR="${1:-qemu}"

# test /etc/kata-containers/runtime-rs existence
if [ ! -d /etc/kata-containers/runtime-rs ]; then
    echo "kata-containers config directory does not exist"
    exit 1
fi

if [ "$HYPERVISOR" == "qemu" ]; then
    CONFIG="configuration-qemu-runtime-rs.toml"
elif [ "$HYPERVISOR" == "dragonball" ]; then
    CONFIG="configuration-dragonball.toml"
else
    echo "unknown hypervisor: $HYPERVISOR"
    echo "supported hypervisors: qemu, dragonball"
    exit 1
fi

if [ ! -f /etc/kata-containers/runtime-rs/$CONFIG ]; then
    echo "configuration file for $HYPERVISOR does not exist"
    exit 1
fi

sudo ln -fs /etc/kata-containers/runtime-rs/$CONFIG \
    /etc/kata-containers/runtime-rs/configuration.toml
echo "ok... $HYPERVISOR configuration applied"
