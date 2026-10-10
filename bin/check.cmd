@echo off
setlocal
call "%~dp0flash.cmd" -Command check %*
exit /b %errorlevel%
