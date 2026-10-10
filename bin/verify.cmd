@echo off
setlocal
call "%~dp0flash.cmd" -Command verify %*
exit /b %errorlevel%
