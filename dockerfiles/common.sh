#!/bin/bash

function show_proxy_info {
	if [ -n "$http_proxy" ]; then
		echo "http proxy is set to $http_proxy"
	else
		echo "no http proxy"
	fi

	if [ -n "$https_proxy" ]; then
        	echo "http proxy is set to $https_proxy"
	else
        	echo "no https proxy"
	fi
}
