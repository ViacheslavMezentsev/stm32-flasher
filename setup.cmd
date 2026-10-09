@echo off
setlocal
call "%~dp0flash.cmd" -Setup %*
exit /b %errorlevel%
