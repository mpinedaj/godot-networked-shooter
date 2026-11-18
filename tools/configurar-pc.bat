@echo off
rem Doble clic: prepara el Ethernet de este PC para la prueba con los routers reales.
echo.
echo   1 = Este PC es el HOST    (crea la partida, va al Router A)
echo   2 = Este PC es el CLIENTE (se une, va al Router B)
echo   3 = Restaurar (dejar el Ethernet como estaba al terminar)
echo.
set /p op="Elige 1, 2 o 3: "
if "%op%"=="1" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0configurar-pc.ps1" -Rol host
if "%op%"=="2" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0configurar-pc.ps1" -Rol cliente
if "%op%"=="3" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0configurar-pc.ps1" -Restaurar
pause
