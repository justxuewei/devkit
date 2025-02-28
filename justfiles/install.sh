#!/bin/bash

set -x

location=""
type=""

usage() {
    echo "Usage: $0 -l location -t type"
    echo "  -l: specify location"
    echo "  -t: specify type"
    exit 1
}

while getopts "l:t:" opt; do
    case $opt in
        l)
            location="$OPTARG"
            ;;
        t)
            type="$OPTARG"
            ;;
        ?)
            usage
            ;;
    esac
done

if [ -z "$location" ] || [ -z "$type" ]; then
    usage
fi

if [ ! -f "justfile.$type" ]; then
    echo "template for $type not exists"
    exit 1
fi

curdir=$(dirname "$(realpath "$BASH_SOURCE")")
cp $curdir/justfile.$type justfile
escaped_location=$(echo "$location" | sed 's/\//\\\//g')
sed -i "s/{{CURRENT_DIR}}/$escaped_location/g" justfile

cat justfile

cp justfile $location/justfile

rm -rf justfile
