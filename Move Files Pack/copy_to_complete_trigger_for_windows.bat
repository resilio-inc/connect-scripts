@echo off
if "%JOB_ROLE%"=="RW" (
    echo "Deleting files"
    rmdir /s/q *
    del /S *
)