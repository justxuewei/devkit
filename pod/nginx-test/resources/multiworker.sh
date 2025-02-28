#!/bin/bash
if [ -z $C_PORT ]; then
	C_PORT="85"
fi

worker_num=$1
filename=wrk-test-${worker_num}.log
resultname=nginx-result-${worker_num}.log

if [ -f "$filename" ]; then
	rm -rf "$filename"
fi

if [ -f "$resultname" ]; then
	rm -rf "$resultname"
fi
version="default"
if [ $# -eq 2 ]; then
	version=$2
fi

concurrency=100
threads=4
duration="60s" #20s is not stable

#wrk默认为长连接
Requests_Long=$(wrk -c $concurrency -t $threads -d $duration http://${C_SERVER}:${C_PORT}/not-exist.html | grep Requests | awk "{print \$2}")
echo ${Requests_Long}
time=$(date "+%Y-%m-%d %H:%M:%S")
echo "count:$i time:${time} long result: ${Requests_Long} \n" >${filename}

#wrk短连接
Requests_Short=$(wrk -H "Connection: Close" -c $concurrency -t $threads -d $duration http://${C_SERVER}:${C_PORT}/not-exist.html | grep Requests | awk "{print \$2}")
echo ${Requests_Short}
time=$(date "+%Y-%m-%d %H:%M:%S")
echo "count:$i time:${time} short result: ${Requests_Short} \n" >>${filename}

echo "nginx{label=\"Long_QPS_$worker_num\",version=\"$version\"} ${Requests_Long}" >>nginx-result.log
echo "nginx{label=\"Short_QPS_$worker_num\",version=\"$version\"} ${Requests_Short}" >>nginx-result.log

#push to pushgateway
cat nginx-result.log