[unix]
set shell := ["sh", "-cu"]

[windows]
set shell := ["cmd.exe", "/c"]

libata_win := "vendor/libata/win-x64"
libata_linux := "vendor/libata/linux-x64"

[windows]
dev:
  watchexec --restart -e cr -- crystal run src/main.cr --link-flags "/LIBPATH:%CD%\{{libata_win}} /LIBPATH:%CD%\libsqlite"

[unix]
dev:
  watchexec --restart -e cr -- crystal run src/main.cr --link-flags "-L{{libata_linux}} -Llibsqlite"

[windows]
build:
  crystal build src/main.cr -o bin/yozgat.exe --link-flags "/LIBPATH:%CD%\{{libata_win}} /LIBPATH:%CD%\libsqlite"

[unix]
build:
  crystal build src/main.cr -o bin/yozgat --link-flags "-L{{libata_linux}} -Llibsqlite"

# Publish a new release. Usage: just publish patch|minor
[windows]
publish bump:
  scripts\publish.bat "{{bump}}"
