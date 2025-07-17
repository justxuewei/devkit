#!/bin/bash
if [ -z $C_PORT ]; then
  C_PORT="85"
fi

if [ -f "wrk-test.log" ]; then
  rm -rf wrk-test.log
fi

if [ -f "nginx-result.log" ]; then
  rm -rf nginx-result.log
fi

version="default"
if [ $# -ne 0 ]; then
  version=$1
fi

sum=0
shortSum=0

concurrency=100
threads=4
duration="60s"                #20s is not stable
repeat=1                      #重复次数，一次运行约10min，先不重复
sizeArr=("100byte" "10kbyte") #只测试大小包两种情况即可
declare -A map
declare -A averagePkg
declare -A shortMap
declare -A averageShortPkg

#map init
for pkgsize in "${sizeArr[@]}"; do
  map[${pkgsize}]=0
  averagePkg[$pkgsize]=0

  shortMap[${pkgsize}]=0
  averageShortPkg[$pkgsize]=0
done

for ((i = 0; i < repeat; i++)); do
  #wrk默认为长连接
  Requests=$(wrk -c $concurrency -t $threads -d $duration http://${C_SERVER}:${C_PORT}/not-exist.html | grep Requests | awk "{print \$2}")
  echo ${Requests}
  time=$(date "+%Y-%m-%d %H:%M:%S")
  echo "count:$i time:${time} long result: ${Requests} \n" >>wrk-test.log
  sum=$(echo "$sum+$Requests" | bc)

  #wrk短连接
  Requests=$(wrk -H "Connection: Close" -c $concurrency -t $threads -d $duration http://${C_SERVER}:${C_PORT}/not-exist.html | grep Requests | awk "{print \$2}")
  echo ${Requests}
  time=$(date "+%Y-%m-%d %H:%M:%S")
  echo "count:$i time:${time} short result: ${Requests} \n" >>wrk-test.log
  shortSum=$(echo "$shortSum+$Requests" | bc)

  #wrk长连接大小包
  for pkgsize in "${sizeArr[@]}"; do
    Requests=$(wrk -c $concurrency -t $threads -d $duration http://"${C_SERVER}":${C_PORT}/"${pkgsize}".html | grep Requests | awk "{print \$2}")
    echo "${Requests}"
    time=$(date "+%Y-%m-%d %H:%M:%S")
    echo "count:$i time:${time} long+pkg $pkgsize result: ${Requests} \n" >>wrk-test.log
    map[${pkgsize}]=$(echo "${map[$pkgsize]}+$Requests" | bc)
  done

  #wrk短连接大小包
  for pkgsize in "${sizeArr[@]}"; do
    Requests=$(wrk -H "Connection: Close" -c $concurrency -t $threads -d $duration http://"${C_SERVER}":${C_PORT}/"${pkgsize}".html | grep Requests | awk "{print \$2}")
    echo "${Requests}"
    time=$(date "+%Y-%m-%d %H:%M:%S")
    echo "count:$i time:${time} short+pkg $pkgsize result: ${Requests} \n" >>wrk-test.log
    shortMap[${pkgsize}]=$(echo "${shortMap[$pkgsize]}+$Requests" | bc)
  done

done

averageLong=$(echo "$sum/$i" | bc)
averageShort=$(echo "$shortSum/$i" | bc)
#pushgateway格式调整
echo "# TYPE nginx gauge" > nginx-result.log
echo "nginx{label=\"Long_QPS\",version=\"$version\"} ${averageLong}" >>nginx-result.log
echo "nginx{label=\"Short_QPS\",version=\"$version\"} ${averageShort}" >>nginx-result.log
for pkgsize in "${sizeArr[@]}"; do
  averagePkg[$pkgsize]=$(echo "${map[$pkgsize]}/$i" | bc)
  echo "nginx{label=\"Long_${pkgsize}_QPS\",version=\"$version\"} ${averagePkg[$pkgsize]}" >>nginx-result.log

  averageShortPkg[$pkgsize]=$(echo "${shortMap[$pkgsize]}/$i" | bc)
  echo "nginx{label=\"Short_${pkgsize}_QPS\",version=\"$version\"} ${averageShortPkg[$pkgsize]}" >>nginx-result.log
done

#push to pushgateway
#与nginx_multiworker合并，本次不push
#cat nginx-result.log | curl --data-binary @- http://${PUSHGATEWAY}:80/metrics/job/pushgateway/instance/${JOBNAME}
