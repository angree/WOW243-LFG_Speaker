@echo off
REM Mirror LFGReader/ into the WoW 2.4.3 AddOns folder.
REM Cross-volume copy (I: -> C:) so mklink /J is not an option.
REM Adjust DEST if your WoW install lives elsewhere.

set SRC=%~dp0LFGSpeaker
set DEST=C:\Gry\World of WarcraftOLD\Interface\AddOns\LFGSpeaker

robocopy "%SRC%" "%DEST%" /MIR /NFL /NDL /NJH /NJS /NP /XF *.bak

echo.
echo Synced %SRC% -^> %DEST%
echo Type /reload in-game to pick up Lua changes.
echo Full client restart needed only if you added/removed files from LFGSpeaker.toc.
