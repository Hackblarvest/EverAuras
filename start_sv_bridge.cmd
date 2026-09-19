@echo off
title Forever SavedVariables Bridge - keep this window open while playing
cd /d "%~dp0"
echo.
echo  WoW: Forever beta writes addon settings to disk but never reads them back.
echo  This watcher copies them into the !ForeverSVBridge addon so they survive
echo  /reload and restarts. Keep this window open while you play.
echo.
python tools\sv_bridge.py --watch
pause
