[unix]
set shell := ["sh", "-cu"]

[windows]
set shell := ["cmd.exe", "/c"]

[windows]
dev:
  watchexec --restart -e cr -- crystal run src/main.cr --link-flags "/LIBPATH:%CD%\libata /LIBPATH:%CD%\libsqlite"

[unix]
dev:
  watchexec --restart -e cr -- crystal run src/main.cr --link-flags "-Llibata -Llibsqlite"

[windows]
build:
  crystal build src/main.cr -o bin/yozgat.exe --link-flags "/LIBPATH:%CD%\libata /LIBPATH:%CD%\libsqlite"

[unix]
build:
  crystal build src/main.cr -o bin/yozgat --link-flags "-Llibata -Llibsqlite"
