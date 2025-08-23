#!/bin/bash

CUR_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CUR_DIR="$(basename $CUR_PATH)"

source $CUR_PATH/../common.sh

show_proxy_info

sudo -E http_proxy=$http_proxy \
	https_proxy=$https_proxy \
	docker build -t $CUR_DIR $CUR_PATH
