#!/bin/bash

if [ ! -e "jobs.txt" ]; then
    printf "The jobs file is empty\n"
    exit 1
fi


# ===== MAIN LOOP =====
comment_counter=0
while read -r line; do

    # Skip blank lines
    if [ -z "$line" ]; then
        continue
    fi

    #Skip comment lines
    if [ "${line:0:1}" == "#" ]; then
        comment_counter=$((comment_counter + 1))
        echo "found a comment line"
        continue
    fi

done < jobs.txt

printf "there are %d comments\n" "$comment_counter"

