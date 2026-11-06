# Проверка кода без запуска игры.
# Запуск из папки проекта:  .\tools\check.ps1
# selene   — ищет типичные ошибки (опечатки, лишние переменные)
# luau-lsp — проверяет типы (число вместо текста и т.п.)
$ErrorActionPreference = "Stop"
$env:Path = "$env:USERPROFILE\bin;$env:Path"
Set-Location (Split-Path $PSScriptRoot -Parent)

$types = "tools\globalTypes.d.luau"
if (-not (Test-Path $types)) {
    Write-Host "Скачиваю описания Roblox API для luau-lsp..."
    Invoke-WebRequest -UseBasicParsing -OutFile $types `
        "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.None.d.luau"
}

rojo sourcemap default.project.json --output sourcemap.json
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "`n=== selene ==="
selene src
$seleneCode = $LASTEXITCODE

Write-Host "`n=== luau-lsp ==="
luau-lsp analyze --sourcemap=sourcemap.json --definitions=$types --platform=roblox src
$lspCode = $LASTEXITCODE

if ($seleneCode -eq 0 -and $lspCode -eq 0) { Write-Host "`nВсё чисто." -ForegroundColor Green; exit 0 }
Write-Host "`nЕсть замечания (см. выше)." -ForegroundColor Yellow
exit 1
