@echo off
setlocal
call "%~dp0flash.cmd" -Info %*
exit /b %errorlevel%
