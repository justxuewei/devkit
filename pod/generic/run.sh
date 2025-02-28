#!/bin/bash

usage() {
    echo "USAGE:"
    echo "	-r runtime	(optional) runtime, default value is kata"
    echo "	-i image	(optional) image, default value is \"busybox\""
    echo "	-c command	(optional) command, default value is \"top\""
    echo "	-v		verbose"
    exit 1
}

cleanup() {
    rm -rf __sandbox.json
    rm -rf __container.json
}

runtime=""
image=""
command=""
verbose=false

while getopts ":r:i:c:v" opt; do
    case ${opt} in
    r)
        runtime=$OPTARG
        ;;
    i)
        image=$OPTARG
        ;;
    c)
        command=$OPTARG
        ;;
    v)
        verbose=true
	;;
    \?)
        usage
        ;;
    esac
done

if [ -z "$runtime" ]; then
    usage
fi

trap cleanup EXIT

cp sandbox.json __sandbox.json
cp container.json __container.json

if [ ! -z "image" ]; then
    sed -i "s|busybox|$image|g" __container.json
else
    image="busybox"
fi

if [ ! -z "command" ]; then
    _command=`echo $command | awk '{for(i=1;i<=NF;i++) $i="\""$i"\""; gsub(" ",",")}1'` 
    sed -i "s|\"top\"|$_command|g" __container.json
fi

echo "Pod Summary:"
echo "	runtime: $runtime"
echo "	image: $image"
echo "	entrypoint: $command"
echo ""

if $verbose; then
    echo "==== sandbox.json ===="
    cat __sandbox.json
    echo ""
    echo "==== container.json ===="
    cat __container.json
fi

sudo crictl pull "$image" > /dev/null || {
    cleanup
    exit 1
}

pod=$(sudo crictl runp -r $runtime __sandbox.json) || {
    echo "$pod"
    cleanup
    exit 1
}
echo "pod=$pod"
cnt=$(sudo crictl create $pod __container.json __sandbox.json) || {
    echo "$cnt"
    cleanup
    exit 1
}
cnt_start=$(sudo crictl start $cnt) || {
    echo "$cnt_start"
    cleanup
    exit 1
}
echo "cnt=$cnt"

