#! /bin/bash

#set -x

SCRIPTPATH=$(dirname "$0")
echo $SCRIPTPATH

devices=(p n x x x x)
map=(power netdev disk1 disk2 disk3 disk4)

# Check network status
gw=$(ip route | awk '/default/ { print $3 }')
if ping -q -c 1 -W 1 $gw >/dev/null; then
    devices[1]=u
fi

# Map sdX1 to hardware device
declare -A hwmap
echo "Mapping devices..."
while read line; do
    MAP=($line)
    device=${MAP[0]}
    hctl=${MAP[1]}
    partitions=$(lsblk -l -o NAME | grep "^${device}[0-9]\+$")
    for part in $partitions; do
        hwmap[$part]=${hctl:0:1}
        echo "Mapped $part to ${hctl:0:1}"
    done
done <<< "$(lsblk -S -o NAME,HCTL | tail -n +2)"

# Print the hwmap for verification
echo "Hardware mapping (hwmap):"
for key in "${!hwmap[@]}"; do
    echo "$key: ${hwmap[$key]}"
done

while true; do

    # Check status of zpool disks
    echo "Checking zpool status..."
    while read line; do
        DEV=($line)
        partition=${DEV[0]}
        echo "Processing $partition with status ${DEV[1]}"
        if [[ -n "${hwmap[$partition]}" ]]; then
            index=$((${hwmap[$partition]} + 2))
            echo "Device $partition maps to index $index"
            if [ ${DEV[1]} = "ONLINE" ]; then
                devices[$index]=o
            else
                devices[$index]=f
            fi
        else
            echo "Warning: No mapping found for $partition"
        fi
    done <<< "$(zpool status -L | grep -E '^\s+sd[a-h][0-9]')"

    # Check status of zpool io
    echo "Checking zpool io..."
    while read line; do
        DEV=($line)
        partition=${DEV[0]}
        write=${DEV[3]}
        read=${DEV[4]}
        echo "Processing $partition with w/r: $write/$read"
        if [[ -n "${hwmap[$partition]}" ]]; then
            index=$((${hwmap[$partition]} + 2))
            echo "Device $partition maps to index $index"
            if [ $write != "0" ]; then
                devices[$index]=w
            fi
        else
            echo "Warning: No mapping found for $partition"
        fi
    done <<< "$(zpool iostat -L -v | grep -E '^\s+sd[a-h][0-9]')"

    # Output the final device statuses
    echo "Final device statuses:"


    for i in "${!devices[@]}"; do
        echo "$i: ${devices[$i]}"
        case "${devices[$i]}" in
            p)
                "$SCRIPTPATH/ugreen_leds_cli" ${map[$i]} -color 255 255 255 -on -brightness 64
                ;;
            u)
                "$SCRIPTPATH/ugreen_leds_cli" ${map[$i]} -color 255 255 255 -on -brightness 64
                ;;
            o)
                "$SCRIPTPATH/ugreen_leds_cli" ${map[$i]} -color 0 255 0 -on -brightness 64
                ;;
            f)
                "$SCRIPTPATH/ugreen_leds_cli" ${map[$i]} -color 255 0 0 -blink 400 600 -brightness 64
                ;;
            w)
                "$SCRIPTPATH/ugreen_leds_cli" ${map[$i]} -color 0 0 255 -blink 50 50 -brightness 50
                ;;
            *)
                "$SCRIPTPATH/ugreen_leds_cli" ${map[$i]} -off
                ;;
        esac
    done

    sleep 0.2
done
