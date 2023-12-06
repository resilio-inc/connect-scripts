@echo off
if "%JOB_ROLE%"=="RW" (
    echo Deleting folders
    for /R /D %%F in (*) do rmdir "%%F" /S /Q
    echo Deleting files
    del /Q *
)