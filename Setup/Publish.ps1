# Publie une nouvelle version de Tune Manager sur le depot GitHub prive.
#   powershell -ExecutionPolicy Bypass -File Setup\Publish.ps1 2.1.1 "Ce qui change"
# 1. ecrit la version, 2. recompile l'installeur, 3. commit + push, 4. cree la Release avec "Tune Manager Setup.exe".
# Les Tune Manager installes proposent ensuite la mise a jour a leur lancement.
param([Parameter(Mandatory = $true)][string]$Version, [string]$Notes = '')
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot; $root = Split-Path $here
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "Version attendue au format 2.1.1" }
$repo = ([IO.File]::ReadAllText((Join-Path $here 'repo.txt'))).Trim()
$cur = ([IO.File]::ReadAllText((Join-Path $here 'version.txt'))).Trim()
if ([version]$Version -le [version]$cur -and (gh release view "v$cur" --repo $repo 2>$null)) { throw "La version $Version doit etre superieure a la derniere publiee ($cur)." }
[IO.File]::WriteAllText((Join-Path $here 'version.txt'), "$Version`r`n")

Write-Host "Compilation..." -ForegroundColor Cyan
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'Build.ps1') | Out-Host
if ($LASTEXITCODE) { throw "Echec de la compilation" }
$setup = Join-Path $root 'Tune Manager Setup.exe'

Write-Host "Envoi du code..." -ForegroundColor Cyan
Push-Location $root
try {
    git add -A
    git commit -m "Tune Manager $Version$(if ($Notes) { " - $Notes" })" | Out-Host
    git push | Out-Host
} finally { Pop-Location }

Write-Host "Creation de la Release v$Version..." -ForegroundColor Cyan
$body = if ($Notes) { $Notes } else { "Tune Manager $Version" }
gh release create "v$Version" $setup --repo $repo --title "Tune Manager $Version" --notes $body | Out-Host
if ($LASTEXITCODE) { throw "Echec de la creation de la Release" }
Write-Host "Publie : Tune Manager $Version. Les installations proposeront la mise a jour au prochain lancement." -ForegroundColor Green
