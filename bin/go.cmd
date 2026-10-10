@echo off
setlocal
call "%~dp0flash.cmd" -Command go %*
exit /b %errorlevel%
