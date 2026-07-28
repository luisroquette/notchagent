#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

version=$(tr -d '[:space:]' < VERSION)
if [[ ! "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    echo "ERRO: VERSION inválido: use MAJOR.MINOR.PATCH."
    exit 1
fi

plist_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
if [[ "$plist_version" != "$version" ]]; then
    echo "ERRO: Resources/Info.plist=$plist_version, VERSION=$version."
    exit 1
fi

if ! grep -Eq "^## ${version} — " CHANGELOG.md; then
    echo "ERRO: CHANGELOG.md não contém a versão $version."
    exit 1
fi

if ! grep -Fq "**Versão atual: ${version}**" README.md; then
    echo "ERRO: README.md não declara a versão $version."
    exit 1
fi

echo "OK: versão $version sincronizada."
