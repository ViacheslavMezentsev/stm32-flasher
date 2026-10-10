@echo off
setlocal
call "%~dp0flash.cmd" -Command reset %*
exit /b %errorlevel%
