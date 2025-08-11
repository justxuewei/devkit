#!/bin/bash

RUST_VERSION="${1:-1.85.1}"
ARCH="$(uname -m)"
if [ "$ARCH" = "x86_64" ]; then
    ARCH="amd64"
elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    ARCH="arm64"
elif [ "$ARCH" = "s390x" ]; then
    ARCH="s390x"
else
    echo "Unsupported architecture: $ARCH"
    exit 1
fi

export RUSTUP_DIST_SERVER="https://rsproxy.cn"
export RUSTUP_UPDATE_ROOT="https://rsproxy.cn/rustup"

curl --proto '=https' --tlsv1.2 -sSf https://rsproxy.cn/rustup-init.sh | sh
. "$HOME/.cargo/env"

rustup default $RUST_VERSION
if [ $ARCH = "amd64" ]; then
    rustup target add x86_64-unknown-linux-musl
    echo "ok... x86_64-unknown-linux-musl target added"
fi

cat > ~/.cargo/config.toml <<EOF
[source.crates-io]
replace-with = 'rsproxy-sparse'
[source.rsproxy]
registry = "https://rsproxy.cn/crates.io-index"
[source.rsproxy-sparse]
registry = "sparse+https://rsproxy.cn/index/"
[registries.rsproxy]
index = "https://rsproxy.cn/crates.io-index"
[net]
git-fetch-with-cli = true
EOF

echo "ok... rust $RUST_VERSION installed, run the following to update your PATH"
echo '. "$HOME/.cargo/env"'

sudo apt-get update >/dev/null
sudo apt-get install -y build-essential musl-dev musl-tools >/dev/null
echo "ok... musl-dev, musl-tools installed"
