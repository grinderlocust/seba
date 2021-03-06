#!/bin/bash

FILE=/usr/share/dict/words

# get line count for $FILE (simulate 'wc -l')
lc=0
while read -r line; do
((lc++))
done < $FILE

# get a random number between 1 and $lc
rnd=$RANDOM
let "rnd %= $lc"
((rnd++))

# traverse file and find line number $rnd
i=0
while read -r line; do
 ((i++))
 [ $i -eq $rnd ] && break
done < $FILE

# output random line
echo "$line"
