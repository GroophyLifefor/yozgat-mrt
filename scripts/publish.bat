@echo off
setlocal enabledelayedexpansion

rem ── Publish a new release ────────────────────────────────────
rem Usage: scripts\publish.bat patch            (default, always allowed)
rem         scripts\publish.bat minor --allow-nonpatch   (human-only override)
rem
rem Policy: minor/major publishes are NOT allowed by default. AI agents
rem (and any automated flow) may only publish a patch bump. A human can
rem explicitly opt into minor/major by passing --allow-nonpatch.
rem
rem 1. Requires committed-but-unpushed changes on the branch
rem    ("ERR: no commit found" otherwise).
rem 2. Bumps the version in shard.yml (patch: X.Y.Z -> X.Y.(Z+1),
rem    minor: X.Y.Z -> X.(Y+1).0, major: X.Y.Z -> (X+1).0.0), commits it.
rem 3. Prints the commit list being published.
rem 4. Pushes the branch, creates the vX.Y.Z tag and pushes it
rem    (which triggers .github/workflows/release.yml).

set "BUMP=%~1"
set "FLAG=%~2"

if "%BUMP%"=="" goto usage
if "%BUMP%"=="patch" goto bumpok

rem Non-patch bumps require the explicit human override.
if not "%FLAG%"=="--allow-nonpatch" (
  echo ERR: %BUMP% publish is not allowed. Only patch is permitted.
  echo       To publish %BUMP% you must run:
  echo         scripts\publish.bat %BUMP% --allow-nonpatch
  exit /b 1
)
goto bumpok

:bumpok
rem 1. Committed-but-unpushed changes required
git rev-parse --verify -q origin/main >nul 2>&1
if errorlevel 1 goto nocommit

set "HAS_COMMIT="
for /f "delims=" %%L in ('git log origin/main..HEAD --oneline') do set "HAS_COMMIT=1"
if not defined HAS_COMMIT goto nocommit

rem 2. Read current version from shard.yml
set "CURRENT="
for /f "tokens=2 delims= " %%V in ('findstr "^version:" shard.yml') do set "CURRENT=%%V"
if not defined CURRENT goto noversion

rem 3. Split into major.minor.patch
set "MAJOR="
set "MINOR="
set "PATCH="
for /f "tokens=1,2,3 delims=." %%a in ("!CURRENT!") do (
  set "MAJOR=%%a"
  set "MINOR=%%b"
  set "PATCH=%%c"
)
if not defined MAJOR goto noversion
if not defined MINOR goto noversion
if not defined PATCH goto noversion

rem 4. Bump
if "%BUMP%"=="patch" (
  set /a "PATCH+=1"
) else if "%BUMP%"=="minor" (
  set /a "MINOR+=1"
  set "PATCH=0"
) else (
  set /a "MAJOR+=1"
  set "MINOR=0"
  set "PATCH=0"
)
set "NEW_VERSION=!MAJOR!.!MINOR!.!PATCH!"

echo Bumping version: !CURRENT! -^> !NEW_VERSION!

rem 5. Rewrite the top-level version line in shard.yml and commit it.
rem    Only the line starting with "version:" (no leading spaces) is replaced —
rem    dependency versions (indented) are never touched.
powershell -NoProfile -Command "$l = Get-Content 'shard.yml'; for ($i = 0; $i -lt $l.Length; $i++) { if ($l[$i] -match '^version:') { $l[$i] = 'version: !NEW_VERSION!'; break } }; $l | Set-Content 'shard.yml'"
powershell -NoProfile -Command "(Get-Content 'src/version.cr') -replace 'VERSION = \".*\"', 'VERSION = \"!NEW_VERSION!\"' | Set-Content 'src/version.cr'"
if errorlevel 1 (
  echo error: failed to update shard.yml
  exit /b 1
)

git add shard.yml src/version.cr
git commit -m "chore: bump version to !NEW_VERSION!"
if errorlevel 1 (
  echo error: git commit failed
  exit /b 1
)

rem 6. Commit list
echo.
echo Commit list:
for /f "delims=" %%L in ('git log origin/main..HEAD --oneline') do echo - %%L

rem 7. Push branch, create tag, push tag
echo.
git push
if errorlevel 1 (
  echo error: git push failed
  exit /b 1
)

git tag "v!NEW_VERSION!"
git push origin "v!NEW_VERSION!"
if errorlevel 1 (
  echo error: failed to push tag
  exit /b 1
)

echo.
echo Published v!NEW_VERSION!
exit /b 0

:nocommit
echo ERR: no commit found
exit /b 1

:noversion
echo error: could not parse version from shard.yml
exit /b 1

:usage
echo usage: scripts\publish.bat patch
echo        scripts\publish.bat minor^|major --allow-nonpatch   (human-only)
exit /b 1
