#!/bin/bash

if [ -f  ./.sync/sourcemarker.txt ]; then
    echo "Source peer, deleting files"
	rm -rf *
else
	echo "Destination peer"
	# Place your code here to process the files which arrived here
fi