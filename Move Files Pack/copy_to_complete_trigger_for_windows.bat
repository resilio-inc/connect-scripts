if exist .\.sync\sourcemarker.txt (
	echo "Source peer, deleting files"
	del /S /Q /F *.*
	FOR /D %%p IN ("%~dp0\*.*") DO rmdir "%%p" /s /q
) else (
	echo "Destination peer"
	rem Place your code here to process the files which arrived here
)