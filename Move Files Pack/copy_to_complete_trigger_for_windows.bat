if exist .\.sync\sourcemarker.txt (
	echo "Source peer, deleting files"
	del /S /Q /F .\.sync\sourcemarker.txt
	rmdir /S /Q %cd%
) else (
	echo "Destination peer"
	rem Place your code here to process the files which arrived here
)