# Compile TuneManager.exe et "Tune Manager Setup.exe" avec le compilateur C# fourni par Windows (.NET Framework 4).
# Usage : powershell -ExecutionPolicy Bypass -File Build.ps1
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot; $root = Split-Path $here
$fw = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319"; $csc = "$fw\csc.exe"; $wpf = "$fw\WPF"
$ico = Join-Path $root 'TuneManager.ico'
$out = Join-Path $here 'bin'; New-Item -ItemType Directory $out -Force | Out-Null
$launcher = Join-Path $out 'TuneManager.exe'
& $csc /nologo /target:winexe /optimize+ "/out:$launcher" "/win32icon:$ico" "/win32manifest:$here\admin.manifest" /r:System.Windows.Forms.dll "$here\Launcher.cs"
if ($LASTEXITCODE) { throw "Echec compilation TuneManager.exe" }
$setup = Join-Path $root 'Tune Manager Setup.exe'
$res = @("/resource:$root\TuneManager.ps1,TuneManager.ps1", "/resource:$launcher,TuneManager.exe", "/resource:$ico,TuneManager.ico")
if (Test-Path "$root\README.md") { $res += "/resource:$root\README.md,README.md" }
$res += "/resource:$here\version.txt,version.txt"
if (Test-Path "$here\repo.txt") { $res += "/resource:$here\repo.txt,repo.txt" }
$refs = @("/r:$wpf\PresentationFramework.dll", "/r:$wpf\PresentationCore.dll", "/r:$wpf\WindowsBase.dll", '/r:System.Xaml.dll', '/r:System.Management.dll')
[string[]]$manifest = if ($args -contains '-NoAdmin') { @() } else { @("/win32manifest:$here\admin.manifest") }
if ($args -contains '-NoAdmin') { $setup = Join-Path $out 'Setup-test.exe' }
& $csc /nologo /target:winexe /optimize+ "/out:$setup" "/win32icon:$ico" @manifest @refs @res "$here\Setup.cs"
if ($LASTEXITCODE) { throw "Echec compilation Setup" }
Get-Item $launcher, $setup | Select-Object Name, Length
