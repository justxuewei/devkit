#!/bin/bash

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

curdir=$(dirname "$(realpath "$BASH_SOURCE")")
if [ ! -f "$curdir/justfile.$type" ]; then
    echo "template for $type not exists"
    exit 1
fi

cp $curdir/justfile.$type justfile
escaped_location=$(echo "$location" | sed 's/\//\\\//g')
sed -i "s/{{CURRENT_DIR}}/$escaped_location/g" justfile

cp justfile $location/justfile

rm -rf justfile

echo "ok... saved at \"$location/justfile\""

# Add justfile to exclude list
if [ -f "$location/.git/info/exclude" ]; then
    # if exitcode is not 0
    if ! grep -q "justfile" "$location/.git/info/exclude"; then
        echo "/justfile" >> "$location/.git/info/exclude"
        echo "ok... added justfile to git exclude list"
    fi
fi
