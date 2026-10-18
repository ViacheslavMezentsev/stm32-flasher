@echo off
setlocal
call "%~dp0flash.cmd" -Doctor %*
exit /b %errorlevel%
