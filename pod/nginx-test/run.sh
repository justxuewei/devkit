#!/bin/bash

set -x

errno=0

cleanup() {
    # if [ -n "$svrcnt" ]; then
    #     sudo crictl stop $svrcnt
    #     sudo crictl rm $svrcnt
    # fi
    # if [ -n "$svrpod" ]; then
    #     sudo crictl rmp -f $svrpod
    # fi
    # if [ -n "$cltcnt" ]; then
    #     sudo crictl stop $cltcnt
    #     sudo crictl rm $cltcnt
    # fi
    # if [ -n "$cltpod" ]; then
    #     sudo crictl rmp -f $cltpod
    # fi
    exit $errno
}

while getopts "r:" opt; do
    case $opt in
    r) runtime=$OPTARG ;;
    \?) echo "Invalid option -$OPTARG" >&2 ;;
    esac
done

sudo -E crictl pull \
    reg.docker.alibaba-inc.com/runsc_test/nano_server:ac767ab9_runsc ||
    exit 1

pushd server

svrpod=$(sudo -E crictl runp -r $runtime sandbox.json) || {
    errno=$?
    echo $svrpod
    svrpod=""
    cleanup
}

svrcnt=$(sudo -E crictl create $svrpod container.json sandbox.json) || {
    errno=$?
    echo $svrcnt
    svrcnt=""
    cleanup
}

sudo -E crictl start $svrcnt || {
    errno=$?
    cleanup
}

cmd="sed -i '/access_log/s/access_log.*/access_log off;/g' /etc/nginx/nginx.conf"
sudo -E crictl exec -i $svrcnt bash -c "$cmd" || {
    errno=$?
    cleanup
}

cmd="sed -i '/error_log/s/error_log.*/error_log \/dev\/null crit;/g' /etc/nginx/nginx.conf"
sudo -E crictl exec -i $svrcnt bash -c "$cmd" || {
    errno=$?
    cleanup
}

cmd="nginx -s reload"
sudo -E crictl exec -i $svrcnt bash -c "$cmd" || {
    errno=$?
    cleanup
}

svrpod_ip=$(sudo crictl inspectp $svrpod | jq -r '.status.network.ip')

popd

pushd client

# use runc as runtime for client
cltpod=$(sudo -E crictl runp sandbox.json) || {
    errno=$?
    echo $cltpod
    cltpod=""
    cleanup
}

cltcnt=$(sudo -E crictl create $cltpod container.json sandbox.json) || {
    errno=$?
    echo $cltcnt
    cltcnt=""
    cleanup
}

sudo -E crictl start $cltcnt || {
    errno=$?
    cleanup
}

cmd="cat > /singleworker.sh && chmod +x /singleworker.sh"
cat ../resources/singleworker.sh | sudo -E crictl exec -i $cltcnt bash -c "$cmd" || {
    errno=$?
    cleanup
}

cmd="export C_SERVER=$svrpod_ip && /singleworker.sh"
sudo -E crictl exec -i $cltcnt bash -c "$cmd" || {
    errno=$?
    cleanup
}

cmd="cat > /multiworker.sh && chmod +x /multiworker.sh"
cat ../resources/multiworker.sh | sudo -E crictl exec -i $cltcnt bash -c "$cmd" || {
    errno=$?
    cleanup
}

for worker in 2 4; do
    cmd="sed -i '/worker_processes/s/worker_processes.*/worker_processes $worker;/g' /etc/nginx/nginx.conf;\
    nginx -s reload"
    sudo -E crictl exec -i $svrcnt bash -c "$cmd" || {
        errno=$?
        cleanup
    }

    cmd="export C_SERVER=$svrpod_ip && /multiworker.sh $worker"
    sudo -E crictl exec -i $cltcnt bash -c "$cmd" || {
        errno=$?
        cleanup
    }
done
