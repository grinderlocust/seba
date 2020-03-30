#!/bin/bash
#A simple copy script
cp $1 "backup.$(date +%F_%R)"
#Let`s verify the copy worked
echo Details for $2
ls -lh $2

#Line 3 - run the command cp with the first command line argument as the source and the second command line argument as the destination.
#Line 5 - run the command echo to print a message.
#Line 6 - After the copy has completed, run the command ls for the destination just to verify it worked. Included the options l (human readable)
