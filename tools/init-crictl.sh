#!/bin/bash

set -e

CURDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash $CURDIR/components/install-go.sh
source ~/.bashrc

bash $CURDIR/components/install-rust.sh
. "$HOME/.cargo/env"

bash $CURDIR/components/install-containerd.sh

bash $CURDIR/components/install-cni.sh

bash $CURDIR/components/install-crictl.sh

bash $CURDIR/components/install-kata.sh

echo "please run the following commands to complete the setup"
echo 'source ~/.bashrc'
echo '. "$HOME/.cargo/env"'
