@echo off
setlocal
call "%~dp0flash.cmd" -Clean %*
exit /b %errorlevel%
