# Genere le logo Tune Manager (vectoriel WPF) : PNG 1024 + icone multi-tailles TuneManager.ico
# Usage : powershell -ExecutionPolicy Bypass -File Logo.ps1 [-Preview dossier]
param([string]$Preview)
Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase
$root = Split-Path $PSScriptRoot

function C([string]$h) { [Windows.Media.ColorConverter]::ConvertFromString($h) }
function New-Logo([int]$px) {
    $s = $px / 256.0                     # dessin concu sur une grille de 256
    $small = $px -le 32
    $dv = New-Object Windows.Media.DrawingVisual
    $dc = $dv.RenderOpen()
    $dc.PushTransform((New-Object Windows.Media.ScaleTransform $s, $s))
    # Fond : carre arrondi noir chaud + lueur rouge en bas
    $r = New-Object Windows.Rect 8, 8, 240, 240
    $bg = New-Object Windows.Media.LinearGradientBrush((C '#22110F'), (C '#0B0606'), 90)
    $dc.DrawRoundedRectangle($bg, $null, $r, 58, 58)
    $glow = New-Object Windows.Media.RadialGradientBrush
    $glow.Center = '0.5,1.0'; $glow.GradientOrigin = '0.5,1.0'; $glow.RadiusX = 0.75; $glow.RadiusY = 0.7
    $glow.GradientStops.Add((New-Object Windows.Media.GradientStop((C '#B0FF4A2E'), 0)))
    $glow.GradientStops.Add((New-Object Windows.Media.GradientStop((C '#00FF4A2E'), 1)))
    $dc.DrawRoundedRectangle($glow, $null, $r, 58, 58)
    $edge = New-Object Windows.Media.Pen((New-Object Windows.Media.SolidColorBrush (C '#55FF6A45')), 2)
    if (-not $small) { $dc.DrawRoundedRectangle($null, $edge, (New-Object Windows.Rect 9, 9, 238, 238), 57, 57) }
    $acc = New-Object Windows.Media.LinearGradientBrush((C '#FF8A5C'), (C '#E23A22'), 90)
    # Arceau de casque
    $arcW = if ($small) { 22 } else { 15 }
    $pen = New-Object Windows.Media.Pen($acc, $arcW); $pen.StartLineCap = 'Round'; $pen.EndLineCap = 'Round'
    $arc = [Windows.Media.Geometry]::Parse('M 58,150 A 70,70 0 0 1 198,150')
    $dc.DrawGeometry($null, $pen, $arc)
    # Ecouteurs (bouts de l'arceau)
    $dc.DrawRoundedRectangle($acc, $null, (New-Object Windows.Rect 42, 138, 32, 62), 14, 14)
    $dc.DrawRoundedRectangle($acc, $null, (New-Object Windows.Rect 182, 138, 32, 62), 14, 14)
    # Barres d'egaliseur (onde) au centre
    $bars = if ($small) { @(@(98, 40), @(122, 66), @(146, 40)) } else { @(@(90, 34), @(108, 58), @(126, 80), @(144, 54), @(162, 30)) }
    $bw = if ($small) { 16 } else { 12 }
    $white = New-Object Windows.Media.LinearGradientBrush((C '#FFFFFF'), (C '#FFD9CC'), 90)
    foreach ($b in $bars) { $h = $b[1]; $dc.DrawRoundedRectangle($white, $null, (New-Object Windows.Rect ($b[0] - $bw / 2 + ($bw / 2)), (172 - $h / 2), $bw, $h), $bw / 2, $bw / 2) }
    $dc.Pop(); $dc.Close()
    $bmp = New-Object Windows.Media.Imaging.RenderTargetBitmap $px, $px, 96, 96, ([Windows.Media.PixelFormats]::Pbgra32)
    $bmp.Render($dv)
    $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder; $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bmp))
    $ms = New-Object IO.MemoryStream; $enc.Save($ms); , $ms.ToArray()
}

if ($Preview) {
    foreach ($p in 1024, 256, 48, 32, 16) { [IO.File]::WriteAllBytes((Join-Path $Preview "logo-$p.png"), (New-Logo $p)) }
    return
}
# PNG haute definition (README, site...)
[IO.File]::WriteAllBytes((Join-Path $root 'TuneManager-logo.png'), (New-Logo 1024))
# Icone : entrees PNG (format accepte par Windows Vista et suivants)
$sizes = 256, 128, 64, 48, 40, 32, 24, 20, 16
# PNG -> DIB 32 bits (BITMAPINFOHEADER + pixels BGRA de bas en haut + masque AND), pour les petites tailles
function To-Dib([byte[]]$png, [int]$p) {
    $dec = New-Object Windows.Media.Imaging.PngBitmapDecoder((New-Object IO.MemoryStream(, $png)), 'PreservePixelFormat', 'OnLoad')
    $f = New-Object Windows.Media.Imaging.FormatConvertedBitmap($dec.Frames[0], [Windows.Media.PixelFormats]::Bgra32, $null, 0)
    $px = New-Object byte[] ($p * $p * 4); $f.CopyPixels($px, $p * 4, 0)
    $ms = New-Object IO.MemoryStream; $w = New-Object IO.BinaryWriter $ms
    $w.Write([uint32]40); $w.Write([int32]$p); $w.Write([int32]($p * 2)); $w.Write([uint16]1); $w.Write([uint16]32)
    $w.Write([uint32]0); $w.Write([uint32]($p * $p * 4)); $w.Write([int32]0); $w.Write([int32]0); $w.Write([uint32]0); $w.Write([uint32]0)
    for ($y = $p - 1; $y -ge 0; $y--) { $w.Write($px, $y * $p * 4, $p * 4) }
    $maskRow = [int]([Math]::Ceiling($p / 32.0) * 4); $w.Write((New-Object byte[] ($maskRow * $p)))
    $w.Flush(); , $ms.ToArray()
}
$imgs = foreach ($p in $sizes) { $png = New-Logo $p; if ($p -le 64) { , (To-Dib $png $p) } else { , $png } }
$ms = New-Object IO.MemoryStream; $w = New-Object IO.BinaryWriter $ms
$w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$sizes.Count)
$off = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $p = $sizes[$i]; $d = [byte[]]$imgs[$i]
    $w.Write([byte]$(if ($p -ge 256) { 0 } else { $p })); $w.Write([byte]$(if ($p -ge 256) { 0 } else { $p }))
    $w.Write([byte]0); $w.Write([byte]0); $w.Write([uint16]1); $w.Write([uint16]32)
    $w.Write([uint32]$d.Length); $w.Write([uint32]$off); $off += $d.Length
}
foreach ($d in $imgs) { $w.Write([byte[]]$d) }
$w.Flush(); [IO.File]::WriteAllBytes((Join-Path $root 'TuneManager.ico'), $ms.ToArray())
"Icone ecrite : $(Join-Path $root 'TuneManager.ico')"
