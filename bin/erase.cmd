@echo off
setlocal
call "%~dp0flash.cmd" -Erase %*
exit /b %errorlevel%
