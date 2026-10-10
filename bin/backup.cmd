@echo off
setlocal
call "%~dp0flash.cmd" -Backup %*
exit /b %errorlevel%
