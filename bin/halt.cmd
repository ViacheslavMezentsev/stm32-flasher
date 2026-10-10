@echo off
setlocal
call "%~dp0flash.cmd" -Command halt %*
exit /b %errorlevel%
