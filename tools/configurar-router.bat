@echo off
rem Doble clic: configura un router Cisco por el cable de consola (ver docs\guia-routers-fisicos.pdf).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0configurar-router.ps1" %*
pause
