@echo off
setlocal
set "PERF_NODE="
where node.exe >nul 2>nul && set "PERF_NODE=node.exe"
if not defined PERF_NODE if exist "%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe" set "PERF_NODE=%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe"
if not defined PERF_NODE (
  echo Node.js was not found. Install Node.js or run this probe from Codex.
  exit /b 127
)
"%PERF_NODE%" "%~dp0run_commute_performance_probe.cjs" %*
exit /b %ERRORLEVEL%
