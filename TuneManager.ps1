# ============================================================================
# Tune Manager v2 - installation, configuration et mises a jour de la
# bibliotheque gratuite ArtTuneDB (GPL-3.0) pour Equalizer APO.
# Usage personnel. N'utilise que les composants gratuits publies par ArtIsWar.
#
#   TuneManager.ps1            -> interface graphique
#   TuneManager.ps1 -Check     -> diagnostic texte (lecture seule)
#   TuneManager.ps1 -AutoCheck -> verifie les mises a jour et notifie (tache planifiee)
# ============================================================================
param([switch]$Check, [switch]$AutoCheck, [switch]$VmTest, [switch]$RunInstall, [switch]$RunUninstall, [switch]$RunRepair,
      [switch]$Tray, [switch]$InstallApp, [switch]$RemoveApp, [switch]$AfterChain)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Root    = "C:\Program Files\EqualizerAPO\config"
$DB      = Join-Path $Root "ArtTuneDB"
$Lib     = Join-Path $DB "library"
# EQ personnels (squig.link...) gardes hors d'Equalizer APO : survivent a la desinstallation et aux mises a jour
$EqStore = Join-Path $env:PUBLIC "TuneManager\EQ"
function Sync-PersonalEq {
    try {
        # Bibliotheque -> reserve (tout EQ autre que Flat_EQ fourni)
        Get-ChildItem $Lib -Recurse -File -Filter *.txt -ErrorAction SilentlyContinue | Where-Object { $_.Directory.Name -eq 'eq' -and $_.Name -ne 'Flat_EQ.txt' } | ForEach-Object {
            $gv = $_.Directory.Parent; $dst = Join-Path $EqStore "$($gv.Parent.Name)\$($gv.Name)"
            if (-not (Test-Path (Join-Path $dst $_.Name))) { New-Item -ItemType Directory $dst -Force | Out-Null; Copy-Item $_.FullName $dst }
        }
        # Reserve -> bibliotheque
        Get-ChildItem $EqStore -Recurse -File -Filter *.txt -ErrorAction SilentlyContinue | ForEach-Object {
            $v = $_.Directory; $g = $v.Parent
            $eqd = Join-Path $Lib "$($g.Name)\$($v.Name)\eq"
            if ((Test-Path (Split-Path $eqd)) -and -not (Test-Path (Join-Path $eqd $_.Name))) { New-Item -ItemType Directory $eqd -Force | Out-Null; Copy-Item $_.FullName $eqd }
        }
    } catch {}
}
# Extras du dossier ArtTuneDB, comme l'installeur officiel : raccourci vers l'editeur E-APO + README
function Ensure-DbExtras {
    try {
        if (-not (Test-Path $DB)) { return }
        $ed = 'C:\Program Files\EqualizerAPO\Editor.exe'
        $lnk = Join-Path $DB 'E-APO Configuration Editor.lnk'
        if ((Test-Path $ed) -and -not (Test-Path $lnk)) {
            $s = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk); $s.TargetPath = $ed; $s.WorkingDirectory = Split-Path $ed
            $s.Description = 'Equalizer APO Configuration Editor'; $s.Save()
        }
        $rd = Join-Path $DB 'README.txt'
        if (-not (Test-Path $rd)) {
            $t = @('ArtTuneDB (gere par Tune Manager)', '=================================', '',
                'ArtIsWar.url                    - artiswar.io', 'ArtTuneDB.url                   - page du projet ArtTuneDB (GitHub)',
                'E-APO Configuration Editor.lnk  - editeur de configuration Equalizer APO', 'boost.txt                       - boost de sortie (une ligne Preamp, 0 dB = off)',
                'tune_active.txt                 - preset 16ch actif (ecrit par Tune Manager)', 'headphone_eq.txt                - EQ du casque actif (ecrit par Tune Manager)',
                'library\                        - presets, targets et EQ de la bibliotheque ArtTuneDB', '',
                'Les profils se choisissent dans Tune Manager : un clic applique le preset en direct.',
                'Tes EQ personnels sont aussi gardes dans C:\Users\Public\TuneManager\EQ (ils survivent aux mises a jour).', '',
                'Aide ArtIsWar : https://discord.gg/artiswar')
            [IO.File]::WriteAllLines($rd, $t)
        }
    } catch {}
}
$Config  = Join-Path $Root "config.txt"
$TuneF   = Join-Path $DB "tune_active.txt"
$EqF     = Join-Path $DB "headphone_eq.txt"
$BoostF  = Join-Path $DB "boost.txt"
$StateF  = Join-Path $DB "tunemanager_state.txt"
$VstDir  = Join-Path $env:ProgramFiles "VSTPlugins\ArtTuneKit"
$JsfxDir = Join-Path $env:ProgramFiles "VSTPlugins\ReaPlugs\JS\Effects\ArtTuneKit"
$VmDir   = "C:\Program Files (x86)\VB\Voicemeeter"

$GitHubApi   = "https://api.github.com/repos/ArtIsWar/ArtTuneDB/releases/latest"
$CdnVersion  = "https://cdn.artiswar.io/ArtTuneDB/latest-version.txt"
$OfficialCmd = "irm artiswar.io/tools/ArtTuneGuided | iex"

# CLSID des APO Equalizer APO (pre-mix / post-mix)
$EapoClsids = @('{EACD2258-FCAC-4FF4-B36D-419E924A6D79}', '{EC1CC9CE-FAED-4822-828A-82A81A6F018F}')
$MMDev = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio"
$PK_Name   = '{a45c254e-df1c-4efd-8020-67d146a850e0},2'
$PK_Iface  = '{b3f8fa53-0004-438e-9003-51a46e139bfc},6'
$PK_Format = '{f19f064d-082c-4e27-bc73-6882a1bb8e4c},0'

# Peripheriques a garder actifs (guide officiel, chapitre "Virtual Devices")
$KeepRender  = @('Art Tune', 'Art Tune +', 'Normal Audio')
$KeepCapture = @('Art Tune Unified Output', 'Virtual Mix')

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$guiMode = -not ($Check -or $AutoCheck -or $VmTest -or $RunInstall -or $RunUninstall -or $RunRepair -or $InstallApp -or $RemoveApp)
if (-not $isAdmin -and ($guiMode -or $InstallApp -or $RemoveApp) -and -not $env:TM_NOELEVATE) {
    $extra = if ($Tray) { ' -Tray' } elseif ($InstallApp) { ' -InstallApp' } elseif ($RemoveApp) { ' -RemoveApp' } else { '' }
    Start-Process powershell "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`"$extra" -Verb RunAs
    exit
}
# Une seule fenetre : si Tune Manager tourne deja (meme cache dans la zone de notification), on l'affiche
if ($guiMode -and -not $env:TM_SNAP) {
    $script:appMutex = New-Object Threading.Mutex($false, 'Local\TuneManagerApp')
    $owned = $false; try { $owned = $script:appMutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $owned = $true }
    if (-not $owned) {
        try { $ev = [Threading.EventWaitHandle]::OpenExisting('Local\TuneManagerShow'); [void]$ev.Set() } catch {}
        exit
    }
}

# ============================================================================
# Bibliotheque / presets
# ============================================================================
# Ex. MW4_V1_16ch_TheaterClear-UltraLoGun_HRIR-KU100.txt ou BO7_V5_16ch_Balanced-HiGun.txt
$rx = '^(?<game>[^_]+)_(?<ver>V\d+)_16ch_(?<fam>[^-]+)-(?<gun>.+?)Gun(?:_HRIR-(?<hrir>[^.]+))?\.txt$'
function Get-Tunes {
    if (-not (Test-Path $Lib)) { return @() }
    @(Get-ChildItem $Lib -Recurse -Filter *_16ch_*.txt | ForEach-Object {
        if ($_.Name -match $rx) {
            [pscustomobject]@{
                Game = $Matches.game; Ver = $Matches.ver; Family = $Matches.fam; Gun = $Matches.gun
                Hrir = $(if ($Matches.hrir) { $Matches.hrir } else { '(integre)' }); Path = $_.FullName
            }
        }
    })
}
$FamNames = @{ 'TheaterClear'='Theater Clear'; 'TheaterClearPlus'='Theater Clear+'; 'ClassicLE'='Classic LE'; 'ClassicLEPlus'='Classic LE+'; 'ClassicLERaw'='Classic LE Raw'; 'ClassicLERawPlus'='Classic LE Raw+' }
$FamDesc = @{
    'TheaterClear'='Son ouvert et naturel, pas renforcés. Point de départ conseillé.'
    'TheaterClearPlus'='Comme Theater Clear, en plus poussé.'
    'ClassicLE'='Proche de l''ancien EQ "loudness".'
    'ClassicLEPlus'='Classic LE, en plus poussé.'
    'ClassicLERaw'='Classic LE avec le monde laissé tel que le jeu le mixe.'
    'ClassicLERawPlus'='Raw avec plus de contrôle sur ta propre arme.'
}
$FamOrder = @('TheaterClear','TheaterClearPlus','ClassicLE','ClassicLEPlus','ClassicLERaw','ClassicLERawPlus')
$GunOrder = @('UltraLo','Lo','Med','Hi','ExtraHi')
$GunNames = @{ 'UltraLo'='Ultra Low'; 'Lo'='Low'; 'Med'='Medium'; 'Hi'='High'; 'ExtraHi'='Extra High (ancien Stock)' }

function Rel([string]$p) { $p.Substring($DB.Length + 1) }
function Get-State {
    $s = @{}
    if (Test-Path $StateF) { Get-Content $StateF -Encoding UTF8 | ForEach-Object { if ($_ -match '^(\w+)=(.*)$') { $s[$Matches[1]] = $Matches[2] } } }
    $s
}
function Save-State($h) { [IO.File]::WriteAllLines($StateF, @($h.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" })) }
function Get-Boost {
    if (Test-Path $BoostF) { $m = Select-String -Path $BoostF -Pattern '^Preamp:\s*(-?[\d.]+)' | Select-Object -First 1; if ($m) { return [double]$m.Matches[0].Groups[1].Value } }
    0
}
function Get-LocalVersion { $f = Join-Path $Lib 'version.txt'; if (Test-Path $f) { (Get-Content $f -First 1).Trim() } else { $null } }

# Branche la section 16ch de config.txt sur les fichiers geres par Tune Manager
function Ensure-ConfigHooks {
    if (-not (Test-Path $Config)) { return $false }
    $c = Get-Content $Config -Raw; $orig = $c
    $c = [regex]::Replace($c, '(# 16ch TUNE\r?\n)#?\s*Include: [^\r\n]*', '${1}Include: ArtTuneDB\tune_active.txt')
    $c = [regex]::Replace($c, '(# 16ch TUNE\r?\n.*?# EQ[^\r\n]*\r?\n)#?\s*Include: [^\r\n]*', '${1}Include: ArtTuneDB\headphone_eq.txt', 'Singleline')
    # Le script officiel ecrit parfois la ligne Device du 16ch en commentaire
    $c = [regex]::Replace($c, '#\s*(Device: Art Tune \+ [^\r\n]*)', '$1')
    if ($c -ne $orig) { Copy-Item $Config "$Config.bak-tunemanager" -Force; [IO.File]::WriteAllText($Config, $c) }
    ($c -match 'Include: ArtTuneDB\\tune_active\.txt') -and ($c -match 'Include: ArtTuneDB\\headphone_eq\.txt')
}

# Applique un choix (et le retrouve au plus proche si le fichier n'existe plus)
function Apply-Selection($game, $ver, $family, $gun, $hrir, $eqPath, [int]$boost) {
    $tunes = Get-Tunes
    $set = @($tunes | Where-Object { $_.Game -eq $game -and $_.Ver -eq $ver })
    if (-not $set.Count) {
        $g = @($tunes | Where-Object Game -eq $game | Sort-Object { [int]($_.Ver -replace '\D') } -Descending)
        if ($g.Count) { $ver = $g[0].Ver; $set = @($g | Where-Object Ver -eq $ver) } else { $set = $tunes }
    }
    $t = $set | Where-Object { $_.Family -eq $family -and $_.Gun -eq $gun -and $_.Hrir -eq $hrir } | Select-Object -First 1
    if (-not $t) { $t = $set | Where-Object { $_.Family -eq $family -and $_.Gun -eq $gun } | Select-Object -First 1 }
    if (-not $t) { $t = $set | Where-Object { $_.Family -eq 'TheaterClear' -and $_.Gun -eq 'UltraLo' } | Select-Object -First 1 }
    if (-not $t) { $t = $set | Select-Object -First 1 }
    if (-not $t) { throw "Aucun preset 16ch trouve dans la bibliotheque." }
    $eqDir = Join-Path (Split-Path $t.Path) 'eq'
    if (-not $eqPath -or -not (Test-Path $eqPath)) {
        $name = if ($eqPath) { (Split-Path $eqPath -Leaf) -replace ' - \w+V\d+\.txt$', '' } else { '' }
        $cand = if ($name) { Get-ChildItem $eqDir -Filter "$name*.txt" -ErrorAction SilentlyContinue | Select-Object -First 1 }
        $eqPath = if ($cand) { $cand.FullName } else { Join-Path $eqDir 'Flat_EQ.txt' }
    }
    [IO.File]::WriteAllText($TuneF, "# Ecrit par Tune Manager`r`nInclude: $(Rel $t.Path)`r`n")
    [IO.File]::WriteAllText($EqF,   "# Ecrit par Tune Manager`r`nInclude: $(Rel $eqPath)`r`n")
    [IO.File]::WriteAllText($BoostF, "# ArtTuneDB Output Boost -- set your dB below and save. 0 dB = off.`r`n# config.txt includes this last on every chain; E-APO reloads it live.`r`nPreamp: $boost dB`r`n")
    $st = Get-State; $st.Game = "$($t.Game)|$($t.Ver)"; $st.Family = $t.Family; $st.Gun = $t.Gun; $st.Hrir = $t.Hrir; $st.Eq = $eqPath
    Save-State $st
    $t
}

$squigCs = @'
using System; using System.Collections.Generic; using System.Linq; using System.Globalization;
// Portage fidele de l'AutoEQ de squig.link (equalizer.js / graphtool.js, CrinGraph)
public class EqFilter { public string Type = "PK"; public double Freq, Q, Gain; }
public static class SquigEq {
  public static double[] FValues() { var f = new List<double> { 20 }; double s = Math.Pow(2, 1.0 / 48); while (f[f.Count - 1] < 20000) f.Add(f[f.Count - 1] * s); return f.ToArray(); }
  public static double MinF = 20, MaxF = 7500;
  static readonly double[][] Deltas = { new double[] { 10, 10, 10, 5, 0.1, 0.5 }, new double[] { 10, 10, 10, 2, 0.1, 0.2 }, new double[] { 10, 10, 10, 1, 0.1, 0.1 } };

  public static double[][] Parse(string txt) {
    var r = new List<double[]>();
    foreach (var raw in txt.Split(new[] { '\r', '\n' })) {
      var l = raw.Trim(); if (l.Length == 0 || l[0] == '*') continue;
      var p = l.Split(new[] { ' ', '\t', ',' }, StringSplitOptions.RemoveEmptyEntries); if (p.Length < 2) continue;
      double a, b; if (double.TryParse(p[0], NumberStyles.Float, CultureInfo.InvariantCulture, out a) && double.TryParse(p[1], NumberStyles.Float, CultureInfo.InvariantCulture, out b)) r.Add(new[] { a, b });
    }
    return r.ToArray();
  }
  public static double[][] Interp(double[] fv, double[][] fr) {
    int i = 0; var res = new double[fv.Length][];
    for (int k = 0; k < fv.Length; k++) {
      double f = fv[k]; double[] o = null;
      for (; i < fr.Length - 1; ++i) {
        double f0 = fr[i][0], v0 = fr[i][1], f1 = fr[i + 1][0], v1 = fr[i + 1][1];
        if (i == 0 && f < f0) { o = new[] { f, v0 }; break; }
        else if (f >= f0 && f < f1) { o = new[] { f, v0 + (v1 - v0) * (f - f0) / (f1 - f0) }; break; }
      }
      res[k] = o ?? new[] { f, fr[fr.Length - 1][1] };
    }
    return res;
  }
  public static double[][] Avg(List<double[][]> cs) {
    int n = cs[0].Length; var r = new double[n][];
    for (int i = 0; i < n; i++) { double s = 0; foreach (var c in cs) s += Math.Pow(10, c[i][1] / 20); r[i] = new[] { cs[0][i][0], 20 * Math.Log10(s / cs.Count) }; }
    return r;
  }
  // ---- normalisation ISO 226 (60 phon)
  static readonly double[] If = { 20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630, 800, 1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500 };
  static readonly double[] Ia = { 0.532, 0.506, 0.48, 0.455, 0.432, 0.409, 0.387, 0.367, 0.349, 0.33, 0.315, 0.301, 0.288, 0.276, 0.267, 0.259, 0.253, 0.25, 0.246, 0.244, 0.243, 0.243, 0.243, 0.242, 0.242, 0.245, 0.254, 0.271, 0.301 };
  static readonly double[] Il = { -31.6, -27.2, -23, -19.1, -15.9, -13, -10.3, -8.1, -6.2, -4.5, -3.1, -2, -1.1, -0.4, 0, 0.3, 0.5, 0, -2.7, -4.1, -1, 1.7, 2.5, 1.2, -2.1, -7.1, -11.2, -10.7, -3.1 };
  static readonly double[] It = { 78.5, 68.7, 59.5, 51.1, 44, 37.5, 31.5, 26.5, 22.1, 17.9, 14.4, 11.4, 8.6, 6.2, 4.4, 3, 2.2, 2.4, 3.5, 1.7, -1.3, -4.2, -6, -5.4, -1.5, 6, 12.6, 13.9, 12.3 };
  public static double[] FreeField = { -7,-7,-7,-7,-7,-7,-7,-7,-7,-7,-7,-7,-7,-7,-7,-7,-7,-7,-7,-7,-7,-6.9275,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9104,-7,-7,-7,-7,-7,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9033,-7,-7,-7,-7,-7,-7,-7,-6.9114,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9344,-7,-7,-7,-7,-7,-6.976,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.955,-7,-7,-7,-7,-7,-7,-6.971,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.9,-6.8476,-6.8,-6.8,-6.7614,-6.6605,-6.6,-6.563,-6.5,-6.4713,-6.3774999999999995,-6.3,-6.2937,-6.2038,-6.2,-6.1059,-6.1,-6.0137,-6,-5.9271,-5.9,-5.8456,-5.8,-5.7496,-5.7,-5.7,-5.7,-5.7,-5.6837,-5.6,-5.6,-5.6,-5.6,-5.5983,-5.5154,-5.5,-5.5,-5.4252,-5.4,-5.4,-5.3469999999999995,-5.3,-5.3,-5.2513000000000005,-5.2,-5.1659,-5.1,-5.1,-5.0771,-5,-5,-5,-4.9,-4.9,-4.8103,-4.8,-4.8,-4.7326,-4.7,-4.7,-4.6433,-4.6,-4.6,-4.5554000000000006,-4.5,-4.4738000000000007,-4.4,-4.3766,-4.2851,-4.2,-4.1962,-4.0989,-4.0031,-3.9087,-3.8155,-3.7238,-3.6243,-3.5351,-3.4383,-3.343,-3.249,-3.2,-3.1568,-3.0668,-3,-3,-3,-2.9879,-2.9000000000000004,-2.9000000000000004,-2.9000000000000004,-2.9920999999999998,-3,-3,-3,-3,-3.0666,-3.1,-3.1,-3.1,-3.1459,-3.2,-3.2,-3.232,-3.3,-3.3239,-3.4,-3.4,-3.4073,-3.5,-3.5,-3.5,-3.5,-3.5,-3.4239,-3.4,-3.4,-3.3396,-3.3,-3.2486,-3.2,-3.2,-3.1651,-3.1,-3.0782,-2.9801,-2.8876999999999997,-2.7923999999999998,-2.6984000000000004,-2.6014999999999997,-2.3183999999999996,-1.9485000000000001,-1.5777999999999999,-1.1963999999999997,-0.89029999999999987,-0.53439999999999976,-0.15390000000000015,0.33159999999999989,0.90829999999999966,1.4305000000000003,1.9368999999999996,2.5105000000000004,3.0759000000000007,3.6023999999999994,4.0027000000000008,4.4847,5.0482,5.5152,5.8994,6.2776,6.7380999999999993,7.1303,7.5168,7.8858,8.273,8.6547,8.9731,9.2595999999999989,9.5420000000000016,9.7856999999999985,10.011099999999999,10.232500000000002,10.353200000000001,10.521999999999998,10.600000000000001,10.600000000000001,10.600000000000001,10.600000000000001,10.5044,10.41,10.314499999999999,10.220500000000001,10.125499999999999,10.0318,9.9373,9.7839999999999989,9.645900000000001,9.4536000000000016,9.2578,9.1234,8.967,8.8736,8.7552,8.566,8.3879,8.2881,8.0958,7.9064,7.8099000000000007,7.6287,7.5200999999999993,7.3477,7.2307000000000006,7.0709,6.9399,6.7916000000000007,6.6514000000000006,6.5551999999999992,6.4604,6.3670000000000009,6.2718000000000007,6.1766000000000005,6.0812000000000008,5.9742999999999995,5.7916000000000007,5.6975,5.602,5.5078,5.3247,5.0547,4.7685999999999993,4.4154,4.1008999999999993,3.9384999999999994,3.7344000000000008,3.3998000000000008,3.0162999999999993,2.6381999999999994,2.2957,1.9799000000000007,1.6248000000000005,1.3404000000000007,1.0424000000000007,0.67400000000000038,0.38510000000000044,0.0060999999999999943,-0.46929999999999961,-0.85160000000000036,-1.2304000000000004,-1.5338000000000003,-1.8916000000000004,-2.2698,-2.6502,-3.029,-3.3545,-3.5925,-3.8657,-4.2082999999999995,-4.4624000000000006,-4.6516,-4.8415,-5.0151,-5.0893,-5,-5,-5,-4.9106000000000005,-4.8156,-4.7212999999999994,-4.6259999999999994,-4.3942999999999994,-4.1735000000000007,-3.9839,-3.7943,-3.6046,-3.4149,-3.1878,-2.9032999999999998,-2.646,-2.4349,-2.1491,-1.8540999999999999,-1.4741,-1.0959000000000003,-0.81189999999999962,-0.43569999999999975,-0.14390000000000036,0.14179999999999993,0.42509999999999959,0.70929999999999982,1.0593000000000004,1.3192000000000004,1.4541000000000004,1.5493000000000006,1.6437000000000008,1.6999999999999993,1.7335999999999991,1.8000000000000007,1.8000000000000007,1.8000000000000007,1.8000000000000007,1.7926000000000002,1.6999999999999993,1.6999999999999993,1.6079000000000008,1.5132999999999992,1.5,1.4237000000000002,1.1862999999999992,0.968,0.7786,0.42189999999999994,-0.0519999999999996,-0.5701,-1.1787999999999998,-1.8437000000000001,-2.5366,-3.2958,-4.1103000000000005,-5.0995,-5.7632,-6.4349,-7.2856,-7.8593,-9.9 };
  public static double FindOffset(double[][] c, double target) {
    int n = c.Length; var A = new double[n]; var K = new double[n]; var C = new double[n]; var FF = new double[n]; int i = 0;
    for (int j = 0; j < n; j++) {
      double f = c[j][0]; if (i < If.Length && f >= If[i]) i++;
      int i0 = Math.Max(0, i - 1), i1 = Math.Min(i, If.Length - 1); double a, lu, tf;
      if (i0 == i1) { a = Ia[i0]; lu = Il[i0]; tf = It[i0]; }
      else { double l0 = Math.Log(If[i0]), l1 = Math.Log(If[i1]), l2 = Math.Log(f), l = (l2 - l0) / (l1 - l0);
        a = Ia[i0] + l * (Ia[i1] - Ia[i0]); lu = Il[i0] + l * (Il[i1] - Il[i0]); tf = It[i0] + l * (It[i1] - It[i0]); }
      double m = a * (Math.Log10(4) - 10 + lu / 10);
      K[j] = (0.005076 / Math.Pow(10, m)) - Math.Pow(10, a * tf / 10); C[j] = Math.Pow(10, 9.4 + 4 * m) / n; A[j] = a;
      int ffi = (int)Math.Floor(0.5 + 48 * Math.Log(f / 19.4806, 2)); FF[j] = FreeField[Math.Max(0, Math.Min(479, ffi))];
    }
    double x = 0, dx; double l10 = Math.Log(10) / 10;
    do {
      double v = 0, d = 0;
      for (int j = 0; j < n; j++) {
        double v0 = Math.Exp(l10 * (c[j][1] + x - FF[j])); double ds = l10 * v0; double v1 = K[j] + Math.Pow(v0, A[j]);
        ds *= A[j] * Math.Pow(v0, A[j] - 1); v += C[j] * Math.Pow(v1, 4); ds *= C[j] * 4 * Math.Pow(v1, 3); d += ds;
      }
      dx = (Math.Log(v) - target * l10) * (v / d); x -= dx;
    } while (Math.Abs(dx) > 0.01);
    return x;
  }
  // ---- biquads
  static double[] Peaking(double freq, double q, double gain) {
    freq = freq / 48000; freq = Math.Max(1e-6, Math.Min(freq, 1)); q = Math.Max(1e-4, Math.Min(q, 1000)); gain = Math.Max(-40, Math.Min(gain, 40));
    double w0 = 2 * Math.PI * freq, sin = Math.Sin(w0), cos = Math.Cos(w0), a = Math.Pow(10, gain / 40), alpha = sin / (2 * q);
    double a0 = 1 + alpha / a, a1 = -2 * cos, a2 = 1 - alpha / a, b0 = 1 + alpha * a, b1 = -2 * cos, b2 = 1 - alpha * a;
    return new[] { 1.0, a1 / a0, a2 / a0, b0 / a0, b1 / a0, b2 / a0 };
  }
  static double[][] Apply(double[][] fr, List<EqFilter> filters) {
    var co = filters.Where(f => f.Freq != 0 && f.Gain != 0 && f.Q != 0).Select(f => Peaking(f.Freq, f.Q, f.Gain)).ToList();
    var r = new double[fr.Length][];
    for (int j = 0; j < fr.Length; j++) {
      double g = 0;
      foreach (var c in co) {
        double a0 = c[0], a1 = c[1], a2 = c[2], b0 = c[3], b1 = c[4], b2 = c[5];
        double w = 2 * Math.PI * fr[j][0] / 48000, phi = 4 * Math.Pow(Math.Sin(w / 2), 2);
        g += 10 * Math.Log10(Math.Pow(b0 + b1 + b2, 2) + (b0 * b2 * phi - (b1 * (b0 + b2) + 4 * b0 * b2)) * phi)
           - 10 * Math.Log10(Math.Pow(a0 + a1 + a2, 2) + (a0 * a2 * phi - (a1 * (a0 + a2) + 4 * a0 * a2)) * phi);
      }
      r[j] = new[] { fr[j][0], fr[j][1] + g };
    }
    return r;
  }
  static double Dist(double[][] a, double[][] b) { double s = 0; for (int i = 0; i < a.Length; i++) { double d = Math.Abs(a[i][1] - b[i][1]); s += d >= 0.1 ? d : 0; } return s / a.Length; }
  public static double Preamp(double[][] fr, List<EqFilter> filters) { var e = Apply(fr, filters); double m = double.NegativeInfinity; for (int i = 0; i < fr.Length; i++) m = Math.Max(m, e[i][1] - fr[i][1]); return -m; }
  static List<EqFilter> Candidates(double[][] fr, double[][] tg, double th) {
    int state = 0, start = -1; var res = new List<EqFilter>();
    for (int i = 0; i < fr.Length; i++) {
      double f = fr[i][0], delta = fr[i][1] - tg[i][1], da = Math.Abs(delta); int next = da < th ? 0 : (int)(delta / da);
      if (next == state) continue;
      if (start >= 0) {
        if (state != 0) {
          double s = fr[start][0], e = f, center = Math.Sqrt(s * e);
          double gain = Interp(new[] { center }, tg.Skip(start).Take(i - start).ToArray())[0][1] - Interp(new[] { center }, fr.Skip(start).Take(i - start).ToArray())[0][1];
          double q = center / (e - s);
          if (center >= MinF && center <= MaxF) res.Add(new EqFilter { Freq = center, Q = q, Gain = gain });
        }
        start = -1;
      } else start = i;
      state = next;
    }
    return res;
  }
  static double Unit(double f) { return f < 100 ? 1 : f < 1000 ? 10 : f < 10000 ? 100 : 1000; }
  static List<EqFilter> Strip(List<EqFilter> fs) {
    return fs.Select(f => new EqFilter { Type = f.Type, Freq = Math.Floor(f.Freq - JsMod(f.Freq, Unit(f.Freq))),
      Q = Math.Min(Math.Max(Math.Floor(f.Q * 10) / 10, 0.5), 10), Gain = Math.Min(Math.Max(Math.Floor(f.Gain * 10) / 10, -12), 12) }).ToList();
  }
  static double JsMod(double a, double b) { return a - b * Math.Truncate(a / b); }
  static List<EqFilter> Optimize(double[][] fr, double[][] tg, List<EqFilter> filters, int it, bool dir) {
    filters = Strip(filters);
    var dl = Deltas[it]; int maxDF = (int)dl[0], maxDQ = (int)dl[1], maxDG = (int)dl[2]; double sDF = dl[3], sDQ = dl[4], sDG = dl[5];
    int begin = dir ? filters.Count - 1 : 0, end = dir ? -1 : filters.Count, step = dir ? -1 : 1;
    for (int i = begin; i != end; i += step) {
      var f = filters[i]; int ii = i;
      var fr1 = Apply(fr, filters.Where((x, fi) => fi != ii).ToList());
      var fr2 = Apply(fr1, new List<EqFilter> { f });
      var best = f; double bestD = Dist(fr2, tg);
      Func<int, int, int, bool> test = (df, dq, dg) => {
        double freq = f.Freq + df * Unit(f.Freq) * sDF, q = f.Q + dq * sDQ, gain = f.Gain + dg * sDG;
        if (freq < MinF || freq > MaxF || q < 0.5 || q > 10 || gain < -12 || gain > 12) return false;
        var nf = new EqFilter { Type = f.Type, Freq = freq, Q = q, Gain = gain };
        double nd = Dist(Apply(fr1, new List<EqFilter> { nf }), tg);
        if (nd < bestD) { best = nf; bestD = nd; return true; }
        return false;
      };
      for (int df = -maxDF; df < maxDF; ++df)
        for (int dq = maxDQ - 1; dq >= -maxDQ; --dq) {
          for (int dg = 1; dg < maxDG; ++dg) if (!test(df, dq, dg)) break;
          for (int dg = -1; dg >= -maxDG; --dg) if (!test(df, dq, dg)) break;
        }
      filters[i] = best;
    }
    if (!dir) return Optimize(fr, tg, filters, it, true);
    filters = filters.OrderBy(x => x.Freq).ToList();
    for (int i = 0; i < filters.Count - 1;) {
      var f1 = filters[i]; var f2 = filters[i + 1];
      if (Math.Abs(f1.Freq - f2.Freq) <= Unit(f1.Freq) && Math.Abs(f1.Q - f2.Q) <= 0.1) { f1.Gain += f2.Gain; filters.RemoveAt(i + 1); } else ++i;
    }
    double bd = Dist(Apply(fr, filters), tg);
    for (int i = 0; i < filters.Count;) {
      if (Math.Abs(filters[i].Gain) <= 0.1) { filters.RemoveAt(i); continue; }
      int ii = i; double nd = Dist(Apply(fr, filters.Where((x, fi) => fi != ii).ToList()), tg);
      if (nd < bd) { filters.RemoveAt(i); bd = nd; } else ++i;
    }
    return filters;
  }
  public static List<EqFilter> AutoEq(double[][] fr, double[][] tg, int maxFilters) {
    int first = Math.Max(maxFilters / 2 - 1, 1);
    var ff = Candidates(fr, tg, 1).Where(c => c.Freq <= 7000).OrderBy(c => c.Q).Take(first).OrderBy(c => c.Freq).ToList();
    for (int i = 0; i < 3; i++) ff = Optimize(fr, tg, ff, i, false);
    var fr2 = Apply(fr, ff);
    var sf = Candidates(fr2, tg, 0.5).OrderBy(c => c.Q).Take(maxFilters - ff.Count).OrderBy(c => c.Freq).ToList();
    for (int i = 0; i < 3; i++) sf = Optimize(fr2, tg, sf, i, false);
    var all = ff.Concat(sf).ToList();
    for (int i = 0; i < 3; i++) all = Optimize(fr, tg, all, i, false);
    return Strip(all);
  }
  // Entree complete : textes des mesures (L, R...) + texte de la target -> fichier E-APO
  // Ecart moyen (dB) entre le casque egalise par un fichier E-APO et la target, sur 20 Hz - 7.5 kHz
  public static double Score(string[] phoneTxt, string targetTxt, string eqTxt) {
    var fv = FValues();
    var chs = phoneTxt.Select(t => Interp(fv, Parse(t))).ToList();
    double pn = FindOffset(Avg(chs), 60);
    var phone = Avg(chs.Select(c => c.Select(d => new[] { d[0], d[1] + pn }).ToArray()).ToList());
    var t0 = Interp(fv, Parse(targetTxt)); double tn = FindOffset(t0, 60);
    var tg = t0.Select(d => new[] { d[0], d[1] + tn }).ToArray();
    var fl = new List<EqFilter>();
    foreach (System.Text.RegularExpressions.Match m in System.Text.RegularExpressions.Regex.Matches(eqTxt, @"ON PK Fc ([\d.]+) Hz Gain (-?[\d.]+) dB Q ([\d.]+)"))
      fl.Add(new EqFilter { Freq = double.Parse(m.Groups[1].Value, CultureInfo.InvariantCulture), Gain = double.Parse(m.Groups[2].Value, CultureInfo.InvariantCulture), Q = double.Parse(m.Groups[3].Value, CultureInfo.InvariantCulture) });
    var e = Apply(phone, fl); double s = 0; int n = 0;
    for (int i = 0; i < e.Length; i++) if (e[i][0] >= 20 && e[i][0] <= 7500) { s += Math.Abs(e[i][1] - tg[i][1]); n++; }
    return s / n;
  }
  public static double NormHz = 0; // 0 = normalisation dB (60 phon, defaut du site), sinon frequence en Hz
  static double HzNorm(List<double[][]> chs, double[] fv) {
    int i = 0; while (i < fv.Length - 1 && fv[i] <= NormHz) i++;
    double s = 0; foreach (var c in chs) s += Math.Pow(10, c[i][1] / 20); return 60 - 20 * Math.Log10(s / chs.Count);
  }
  public static string Build(string[] phoneTxt, string targetTxt, int bands) {
    var fv = FValues();
    var chs = phoneTxt.Where(t => !string.IsNullOrEmpty(t)).Select(t => Interp(fv, Parse(t))).ToList();
    double pn = NormHz > 0 ? HzNorm(chs, fv) : FindOffset(chs.Count == 1 ? chs[0] : Avg(chs), 60);
    var shifted = chs.Select(c => c.Select(d => new[] { d[0], d[1] + pn }).ToArray()).ToList();
    var phone = shifted.Count > 1 ? Avg(shifted) : shifted[0];
    var t0 = Interp(fv, Parse(targetTxt)); double tn = NormHz > 0 ? HzNorm(new List<double[][]> { t0 }, fv) : FindOffset(t0, 60);
    var tg = t0.Select(d => new[] { d[0], d[1] + tn }).ToArray();
    var filters = AutoEq(phone, tg, bands);
    var raw0 = chs[0];
    var sb = new System.Text.StringBuilder();
    sb.Append("Preamp: " + Preamp(raw0, filters).ToString("0.0", CultureInfo.InvariantCulture) + " dB\r\n");
    for (int i = 0; i < bands; i++) {
      if (i < filters.Count) { var f = filters[i];
        sb.Append(string.Format(CultureInfo.InvariantCulture, "Filter {0}: ON PK Fc {1:0} Hz Gain {2:0.0} dB Q {3:0.000}\r\n", i + 1, f.Freq, f.Gain, f.Q)); }
      else sb.Append(string.Format("Filter {0}: OFF PK Fc 0 Hz Gain 0.0 dB Q 0.000\r\n", i + 1));
    }
    return sb.ToString();
  }
}
'@
# ============================================================================
# EQ automatique (squig.link GadgetryTech + target ArtIsWar de la version)
# Portage fidele de l'AutoEQ de squig.link : meme resultat que le bouton AutoEQ du site.
# ============================================================================
$SquigBase = 'https://gadgetrytech.squig.link'
$SquigCache = Join-Path $env:PUBLIC 'TuneManager\squig'
function Init-Squig { if (-not ('SquigEq' -as [type])) { Add-Type -TypeDefinition $squigCs -ReferencedAssemblies System.Core } }
# Liste des casques/IEM mesures (cache local 7 jours)
function Get-SquigPhones {
    New-Item -ItemType Directory $SquigCache -Force | Out-Null
    $pbf = Join-Path $SquigCache 'phone_book.json'
    if (-not (Test-Path $pbf) -or ((Get-Date) - (Get-Item $pbf).LastWriteTime).TotalDays -gt 7) {
        try { Invoke-WebRequest "$SquigBase/data/phone_book.json" -OutFile $pbf -UseBasicParsing -TimeoutSec 30 } catch { if (-not (Test-Path $pbf)) { throw "squig.link injoignable : $($_.Exception.Message)" } }
    }
    $pb = [IO.File]::ReadAllText($pbf) | ConvertFrom-Json
    foreach ($b in $pb) { foreach ($ph in $b.phones) {
        $files = @($ph.file); $names = @($ph.name)
        for ($i = 0; $i -lt $files.Count; $i++) {
            $n = if ($names.Count -gt $i -and $files.Count -eq $names.Count) { $names[$i] } elseif ($files.Count -gt 1) { "$($names[0]) ($($files[$i] -replace [regex]::Escape("$($b.name) "), ''))" } else { $names[0] }
            [pscustomobject]@{ Label = "$($b.name) $n"; File = $files[$i] }
        }
    } } 
}
function Get-VersionTarget([string]$game, [string]$ver) { Get-ChildItem (Join-Path $Lib "$game\$ver") -Filter '*_Target_*.txt' -ErrorAction SilentlyContinue | Select-Object -First 1 }
# Cree l'EQ du casque pour un jeu/version et le range dans la reserve + la bibliotheque. Renvoie le chemin dans la bibliotheque.
function New-HeadphoneEq([string]$label, [string]$file, [string]$game, [string]$ver) {
    Init-Squig
    $tgt = Get-VersionTarget $game $ver; if (-not $tgt) { throw "Pas de target ArtIsWar pour $game $ver." }
    $txt = @(); foreach ($c in 'L', 'R') {
        try { $txt += (Invoke-WebRequest "$SquigBase/data/$([uri]::EscapeDataString("$file $c")).txt" -UseBasicParsing -TimeoutSec 30).Content } catch {}
    }
    if (-not $txt.Count) { throw "Mesure introuvable sur squig.link pour $label." }
    $eq = [SquigEq]::Build([string[]]$txt, [IO.File]::ReadAllText($tgt.FullName), 10)
    $name = "$(($label -replace '[\\/:*?""<>|]', '-').Trim()) - $game$ver.txt"
    $store = Join-Path $EqStore "$game\$ver"; New-Item -ItemType Directory $store -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $store $name), $eq)
    $eqd = Join-Path $Lib "$game\$ver\eq"; New-Item -ItemType Directory $eqd -Force | Out-Null
    $out = Join-Path $eqd $name; [IO.File]::WriteAllText($out, $eq)
    $out
}

# ============================================================================
# Mises a jour (GitHub, avec le site ArtIsWar en secours)
# ============================================================================
function Get-RemoteRelease {
    try {
        $r = Invoke-RestMethod $GitHubApi -Headers @{ 'User-Agent' = 'TuneManager' } -TimeoutSec 15
        $a = $r.assets | Where-Object name -like '*.zip' | Select-Object -First 1
        return [pscustomobject]@{ Version = $r.tag_name; Url = $a.browser_download_url; Notes = $r.body; Source = 'GitHub' }
    } catch {
        try {
            $v = (Invoke-RestMethod $CdnVersion -TimeoutSec 15).ToString().Trim()
            return [pscustomobject]@{ Version = $v; Url = "https://cdn.artiswar.io/ArtTuneDB/ArtTuneDB-$v.zip"; Notes = ''; Source = 'artiswar.io' }
        } catch { return $null }
    }
}

function Update-Library($release, [scriptblock]$log) {
    $tmp = Join-Path $env:TEMP "TuneManager-update"
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    New-Item -ItemType Directory $tmp | Out-Null
    $zip = Join-Path $tmp 'library.zip'; $stage = Join-Path $tmp 'stage'
    & $log "Telechargement de $($release.Version) depuis $($release.Source)..."
    Invoke-WebRequest $release.Url -OutFile $zip -UseBasicParsing -Headers @{ 'User-Agent' = 'TuneManager' }
    & $log "Extraction..."
    Expand-Archive -LiteralPath $zip -DestinationPath $stage -Force
    # Racine de la bibliotheque = dossier contenant version.txt
    $vf = Get-ChildItem $stage -Recurse -Filter version.txt | Sort-Object { $_.FullName.Length } | Select-Object -First 1
    if (-not $vf) { throw "Archive inattendue : version.txt introuvable." }
    $newLib = $vf.DirectoryName
    if (-not (Get-ChildItem $newLib -Recurse -Filter *_16ch_*.txt | Select-Object -First 1)) { throw "Archive inattendue : aucun preset 16ch." }

    $state = Get-State; $boost = [int](Get-Boost)
    $stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    $old = Join-Path $DB "library-previous-$stamp"
    if (Test-Path $Lib) {
        & $log "Sauvegarde de l'ancienne bibliotheque -> $(Split-Path $old -Leaf)"
        Move-Item $Lib $old
        # Conserver les EQ personnels (fichiers absents de la nouvelle version)
        Get-ChildItem $old -Recurse -File -Filter *.txt | Where-Object { $_.Directory.Name -eq 'eq' } | ForEach-Object {
            $relp = $_.FullName.Substring($old.Length + 1)
            $dest = Join-Path $newLib $relp
            if (-not (Test-Path $dest) -and (Test-Path (Split-Path (Split-Path $dest)))) {
                New-Item -ItemType Directory (Split-Path $dest) -Force | Out-Null
                Copy-Item $_.FullName $dest; & $log "EQ personnel conserve : $($_.Name)"
            }
        }
    }
    Move-Item $newLib $Lib
    # Move-Item garde les droits du dossier %TEMP% (compte utilisateur seul) : le service audio
    # (audiodg) ne pourrait plus lire les presets. On reprend les droits herites de config\.
    & icacls.exe $Lib /reset /T /C /Q | Out-Null
    Sync-PersonalEq

    # Plugins : comme le script officiel (VST manquants, JSFX manquants ou modifies)
    $srcVst = Join-Path $Lib 'vst'
    if (Test-Path $srcVst) {
        New-Item -ItemType Directory $VstDir -Force | Out-Null
        Get-ChildItem $srcVst -Filter *.dll | ForEach-Object {
            $d = Join-Path $VstDir $_.Name
            if (-not (Test-Path $d)) { Copy-Item $_.FullName $d; & $log "Plugin VST installe : $($_.Name)" }
        }
    }
    $srcJs = Join-Path $Lib 'jsfx'
    if ((Test-Path $srcJs) -and (Test-Path (Join-Path $env:ProgramFiles 'VSTPlugins\ReaPlugs'))) {
        New-Item -ItemType Directory $JsfxDir -Force | Out-Null
        Get-ChildItem $srcJs -Filter *.jsfx | ForEach-Object {
            $d = Join-Path $JsfxDir $_.Name
            if (-not (Test-Path $d) -or (Get-FileHash $d).Hash -ne (Get-FileHash $_.FullName).Hash) { Copy-Item $_.FullName $d -Force; & $log "Plugin JSFX mis a jour : $($_.Name)" }
        }
    }

    # Reappliquer le choix de l'utilisateur
    if ($state.Game) {
        $g, $v = $state.Game -split '\|'
        $eq = if ($state.Eq) { $state.Eq } else { $null }
        $t = Apply-Selection $g $v $state.Family $state.Gun $state.Hrir $eq $boost
        & $log "Preset reapplique : $(Split-Path $t.Path -Leaf)"
    }
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    & $log "Bibliotheque a jour : $(Get-LocalVersion)"
}

function Register-UpdateTask([bool]$enable) {
    $name = 'TuneManager - verification des mises a jour'
    Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
    if ($enable) {
        $a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`" -AutoCheck"
        $t = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
        $t.Delay = 'PT2M'
        Register-ScheduledTask -TaskName $name -Action $a -Trigger $t -Description 'Verifie si ArtIsWar a publie une nouvelle bibliotheque ArtTuneDB.' | Out-Null
    }
}
function Test-UpdateTask { [bool](Get-ScheduledTask -TaskName 'TuneManager - verification des mises a jour' -ErrorAction SilentlyContinue) }

# ============================================================================
# Diagnostic Windows / Equalizer APO
# ============================================================================
function Get-Endpoints {
    foreach ($flow in 'Render', 'Capture') {
        Get-ChildItem "$MMDev\$flow" | ForEach-Object {
            $p = Get-ItemProperty "$($_.PSPath)\Properties" -ErrorAction SilentlyContinue
            $st = (Get-ItemProperty $_.PSPath).DeviceState
            $fmt = $p.$PK_Format; $ch = $null; $sr = $null; $bits = $null
            if ($fmt -and $fmt.Length -ge 24) { $ch = [BitConverter]::ToUInt16($fmt, 10); $sr = [BitConverter]::ToUInt32($fmt, 12); $bits = [BitConverter]::ToUInt16($fmt, 22) }
            $fx = Get-ItemProperty "$($_.PSPath)\FxProperties" -ErrorAction SilentlyContinue
            $fxv = if ($fx) { @($fx.PSObject.Properties | Where-Object { $_.Name -match '^\{d04e05a6' } | ForEach-Object { "$($_.Value)" }) } else { @() }
            [pscustomobject]@{
                Flow = $flow; Name = $p.$PK_Name; Iface = $p.$PK_Iface; Id = $_.PSChildName
                Present = (($st -band 0xF) -eq 1); Disabled = [bool]($st -band 0x10000000) -or (($st -band 0xF) -eq 2)
                Channels = $ch; Rate = $sr; Bits = $bits
                Eapo = [bool]($fxv | Where-Object { $EapoClsids -contains $_.ToUpper() })
            }
        }
    }
}

function Get-Diagnostic {
    $r = New-Object System.Collections.Generic.List[object]
    function Add($ok, $txt, $fix = '') { $r.Add([pscustomobject]@{ Ok = $ok; Text = $txt; Fix = $fix }) }
    $eapo = Test-Path "C:\Program Files\EqualizerAPO\EqualizerAPO.dll"
    Add $eapo "Equalizer APO installé" "Étape 1 : lance l'installation officielle."
    Add (Test-Path (Join-Path $env:ProgramFiles 'VSTPlugins\ReaPlugs')) "ReaPlugs installé" "Étape 1 : lance l'installation officielle."
    Add ([bool](Get-ChildItem $VstDir -Filter *.dll -ErrorAction SilentlyContinue)) "Plugins ArtTuneKit (VST) présents" "Etape 1, ou Mise a jour de la bibliotheque."
    $v = Get-LocalVersion
    Add ([bool]$v) "Bibliothèque ArtTuneDB $(if ($v) { "($v)" })" "Onglet Mises a jour."
    $eps = @(Get-Endpoints)
    $plus = $eps | Where-Object { $_.Flow -eq 'Render' -and $_.Name -eq 'Art Tune +' } | Select-Object -First 1
    $at   = $eps | Where-Object { $_.Flow -eq 'Render' -and $_.Name -eq 'Art Tune' } | Select-Object -First 1
    $uni  = $eps | Where-Object { $_.Flow -eq 'Capture' -and $_.Name -eq 'Art Tune Unified Output' } | Select-Object -First 1
    Add ($plus -and $plus.Present -and -not $plus.Disabled) "Périphérique Art Tune + actif" "Etape 1, puis active-le dans Son > Lecture."
    if ($plus) {
        Add ($plus.Channels -eq 16 -and $plus.Rate -eq 48000 -and $plus.Bits -eq 24) "Art Tune + en 16 canaux, 24 bits, 48 kHz (actuel : $($plus.Channels) ch, $($plus.Bits) bits, $($plus.Rate) Hz)" "Son > Lecture > Art Tune + > Proprietes > Avance : 16 canaux, 24 bits, 48000 Hz. Laisse 'Activer les ameliorations audio' coche."
        Add $plus.Eapo "Equalizer APO actif sur Art Tune +" "Bouton 'Device Selector' : coche Art Tune +, Troubleshooting, choisis LFX/GFX."
    }
    if ($uni) { Add ($uni.Channels -eq 2 -and $uni.Rate -eq 48000 -and $uni.Bits -eq 24) "Art Tune Unified Output en 2 canaux, 24 bits, 48 kHz" "Son > Enregistrement > Art Tune Unified Output > Avance : 2 canaux, 24 bits, 48000 Hz." }
    else { Add $false "Art Tune Unified Output présent" "Étape 1 : lance l'installation officielle." }
    if ($at) { Add (-not $at.Present -or $at.Disabled) "Ancien périphérique Art Tune (7.1) désactivé" "Bouton « Désactiver les périphériques inutiles »." }
    $extra = @($eps | Where-Object { $_.Iface -match 'Voicemeeter|Virtual Cable' -and $_.Present -and -not $_.Disabled -and
        -not (($_.Flow -eq 'Render' -and $KeepRender -contains $_.Name) -or ($_.Flow -eq 'Capture' -and $KeepCapture -contains $_.Name)) })
    Add ($extra.Count -eq 0) "Sorties virtuelles inutiles désactivées$(if ($extra.Count) { " ($($extra.Count) encore actives)" })" "Bouton « Désactiver les périphériques inutiles »."
    Add (Ensure-ConfigHooks) "config.txt branché sur Tune Manager" "Etape 1 : l'installation officielle ecrit config.txt."
    if (Test-Path $Lib) {
        # Le service audio lit les presets via le groupe Utilisateurs (S-1-5-32-545)
        $users = New-Object Security.Principal.SecurityIdentifier 'S-1-5-32-545'
        $libOk = [bool]((Get-Acl -LiteralPath $Lib).Access | Where-Object { $_.AccessControlType -eq 'Allow' -and
            $(try { $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]) -eq $users } catch { $false }) })
        Add $libOk "Bibliothèque lisible par le service audio" "En administrateur : icacls `"$Lib`" /reset /T /C /Q"
    }
    $vm = Get-Process voicemeeter* -ErrorAction SilentlyContinue
    Add ([bool]$vm) "Voicemeeter lancé" "Étape 3 : configurer Voicemeeter."
    $r
}

# Desactivation des peripheriques virtuels inutiles via l'API Windows (IPolicyConfig)
$policyCs = @'
using System; using System.Runtime.InteropServices;
[ComImport, Guid("f8679f50-850a-41cf-9c72-430f290290c8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IPolicyConfig {
  int GetMixFormat(); int GetDeviceFormat(); int ResetDeviceFormat(); int SetDeviceFormat(); int GetProcessingPeriod();
  int SetProcessingPeriod(); int GetShareMode(); int SetShareMode(); int GetPropertyValue(); int SetPropertyValue();
  int SetDefaultEndpoint([MarshalAs(UnmanagedType.LPWStr)] string id, int role);
  int SetEndpointVisibility([MarshalAs(UnmanagedType.LPWStr)] string id, int visible);
}
[ComImport, Guid("870af99c-171d-4f9e-af0d-e63df40c2bc9")] class PolicyConfigClient {}
public static class AudioPolicy {
  public static int SetVisible(string id, bool v) { return ((IPolicyConfig)new PolicyConfigClient()).SetEndpointVisibility(id, v ? 1 : 0); }
}
'@
function Disable-ExtraDevices([scriptblock]$log) {
    if (-not ('AudioPolicy' -as [type])) { Add-Type $policyCs }
    $eps = @(Get-Endpoints); $cab = Find-CableEndpoints
    $keepIds = @($cab.Render16, $cab.Capture, $cab.VmRender, $cab.VmCapture) | Where-Object { $_ }
    foreach ($e in $eps) {
        if (-not $e.Present -or $e.Disabled) { continue }
        $keep = ($keepIds -contains $e.Id) -or ($e.Flow -eq 'Render' -and $KeepRender -contains $e.Name) -or ($e.Flow -eq 'Capture' -and $KeepCapture -contains $e.Name)
        if ($e.Name -eq 'Art Tune +') { $keep = $true }
        $old = ($e.Flow -eq 'Render' -and ($e.Name -eq 'Art Tune' -or ($cab.Render8 -and $e.Id -eq $cab.Render8)))
        if (($e.Iface -match 'Voicemeeter|Virtual Cable' -and -not $keep) -or $old) {
            $full = if ($e.Flow -eq 'Render') { "{0.0.0.00000000}.$($e.Id)" } else { "{0.0.1.00000000}.$($e.Id)" }
            $hr = [AudioPolicy]::SetVisible($full, $false)
            & $log $(if ($hr -eq 0) { "Desactive : $($e.Name)" } else { "Echec ($hr) : $($e.Name)" })
        }
    }
}

# ============================================================================
# Voicemeeter (API officielle VoicemeeterRemote64.dll)
# ============================================================================
$vmCs = @'
using System; using System.Runtime.InteropServices; using System.Text;
public static class VM {
  [DllImport("VoicemeeterRemote64.dll")] public static extern int VBVMR_Login();
  [DllImport("VoicemeeterRemote64.dll")] public static extern int VBVMR_Logout();
  [DllImport("VoicemeeterRemote64.dll")] public static extern int VBVMR_RunVoicemeeter(int type);
  [DllImport("VoicemeeterRemote64.dll")] public static extern int VBVMR_IsParametersDirty();
  [DllImport("VoicemeeterRemote64.dll")] public static extern int VBVMR_SetParameterFloat(string name, float v);
  [DllImport("VoicemeeterRemote64.dll")] public static extern int VBVMR_SetParameterStringA(string name, string v);
  [DllImport("VoicemeeterRemote64.dll")] public static extern int VBVMR_GetParameterStringA(string name, StringBuilder v);
  [DllImport("VoicemeeterRemote64.dll")] public static extern int VBVMR_GetVoicemeeterType(ref int t);
  [DllImport("VoicemeeterRemote64.dll")] public static extern int VBVMR_Output_GetDeviceNumber();
  [DllImport("VoicemeeterRemote64.dll")] public static extern int VBVMR_Output_GetDeviceDescA(int i, ref int type, StringBuilder name, StringBuilder hw);
  [DllImport("VoicemeeterRemote64.dll")] public static extern int VBVMR_Input_GetDeviceNumber();
  [DllImport("VoicemeeterRemote64.dll")] public static extern int VBVMR_Input_GetDeviceDescA(int i, ref int type, StringBuilder name, StringBuilder hw);
  [DllImport("kernel32.dll")] public static extern IntPtr LoadLibrary(string p);
}
'@
function Init-VM {
    if (-not (Test-Path "$VmDir\VoicemeeterRemote64.dll")) { throw "Voicemeeter n'est pas installe (etape 1)." }
    if (-not ('VM' -as [type])) { Add-Type $vmCs; [void][VM]::LoadLibrary("$VmDir\VoicemeeterRemote64.dll") }
    $rc = [VM]::VBVMR_Login()
    if (-not (Get-Process voicemeeter, voicemeeter_x64 -ErrorAction SilentlyContinue)) {
        $exe = Join-Path $VmDir 'voicemeeter_x64.exe'; if (-not (Test-Path $exe)) { $exe = Join-Path $VmDir 'voicemeeter.exe' }
        # -r : lancement "comme au demarrage de Windows", seul cas ou Voicemeeter respecte "fenetre cachee" (SysTrayShowOnRun=0)
        Start-Process $exe '-r' -WorkingDirectory $VmDir -WindowStyle Hidden
        for ($w = 0; $w -lt 30 -and -not (Get-Process voicemeeter, voicemeeter_x64 -ErrorAction SilentlyContinue); $w++) { Start-Sleep -Milliseconds 500 }
        Start-Sleep 2; [void][VM]::VBVMR_Logout(); [void][VM]::VBVMR_Login()
    }
    # Attendre que Voicemeeter soit pret (jusqu'a ~20 s), en se reconnectant si besoin
    for ($i = 0; $i -lt 40; $i++) {
        [void][VM]::VBVMR_IsParametersDirty(); $t = 0
        if ([VM]::VBVMR_GetVoicemeeterType([ref]$t) -eq 0 -and $t -gt 0) { Start-Sleep -Milliseconds 300; [void][VM]::VBVMR_IsParametersDirty(); return $t }
        if ($i % 6 -eq 5) { [void][VM]::VBVMR_Logout(); [void][VM]::VBVMR_Login() }
        Start-Sleep -Milliseconds 500
    }
    throw "Impossible de se connecter a Voicemeeter."
}
function Get-VMOutputs {
    [void](Init-VM)
    $n = [VM]::VBVMR_Output_GetDeviceNumber(); $list = @()
    for ($i = 0; $i -lt $n; $i++) {
        $t = 0; $nm = New-Object Text.StringBuilder 512; $hw = New-Object Text.StringBuilder 512
        [void][VM]::VBVMR_Output_GetDeviceDescA($i, [ref]$t, $nm, $hw)
        if ($t -eq 3 -and $nm.ToString() -notmatch 'Voicemeeter|Art Tune \+|^Art Tune$|CABLE') { $list += $nm.ToString() }  # 3 = WDM
    }
    $list | Sort-Object -Unique
}
function Get-VMCurrent {
    try {
        [void](Init-VM)
        $a = New-Object Text.StringBuilder 512; $b = New-Object Text.StringBuilder 512
        [void][VM]::VBVMR_IsParametersDirty()
        [void][VM]::VBVMR_GetParameterStringA('Strip[0].device.name', $a); [void][VM]::VBVMR_GetParameterStringA('Bus[0].device.name', $b)
        [pscustomobject]@{ Input = $a.ToString(); A1 = $b.ToString() }
    } catch { $null }
}
$defCs = @'
using System; using System.Runtime.InteropServices;
[ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDevEnumD { int EnumAudioEndpoints(int f, int m, out IntPtr c); int GetDefaultAudioEndpoint(int f, int r, out IMMDevD d); }
[ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDevD { int Activate(IntPtr a, int b, IntPtr c, out IntPtr d); int OpenPropertyStore(int a, out IntPtr p); int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id); }
[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDevEnumD {}
public static class DefOut {
  public static string Id() { IMMDevD d; if (((IMMDevEnumD)new MMDevEnumD()).GetDefaultAudioEndpoint(0, 1, out d) != 0 || d == null) return null; string s; d.GetId(out s); return s; }
}
'@
# Sortie Windows par defaut (nom complet, ex. "Casque (Sound Blaster GC7)"), sauf si c'est un peripherique virtuel
function Get-DefaultOutputName {
    try {
        if (-not ('DefOut' -as [type])) { Add-Type $defCs }
        $id = [DefOut]::Id(); if (-not $id) { return $null }
        $guid = ($id -split '\}\.')[-1]
        $p = Get-ItemProperty "$MMDev\Render\$guid\Properties" -ErrorAction SilentlyContinue
        $n = "$($p.$PK_Friendly)"; $hw = "$($p.'{b3f8fa53-0004-438e-9003-51a46e139bfc},6')"
        if ($n -and $hw -and $n -notmatch '\(') { $n = "$n ($hw)" }
        if (-not $n -or $p.$PK_Desc -eq 'VB-Audio Virtual Cable' -or $n -match 'Voicemeeter|VB-Audio|Art Tune|CABLE') { return $null }
        $n
    } catch { $null }
}
# Sortie integree a la carte mere ou ecran (Realtek, HDMI/DisplayPort de la carte graphique) : rarement celle du casque
function Test-OnboardOutput([string]$n) { $n -match 'Realtek|High Definition Audio|HDMI|DisplayPort|NVIDIA|AMD|Intel\(R\) Display|Moniteur|Monitor' }
# Choisit dans Voicemeeter la sortie qui correspond au nom memorise.
# Si ce nom designe une sortie integree (ex. haut-parleurs Realtek mis par defaut le temps d'une video) alors
# qu'une carte son dediee est branchee (Sound Blaster, DAC USB...), la carte dediee est preferee.
function Select-VMOutput([string]$pref) {
    $outs = @(Get-VMOutputs); if (-not $outs.Count) { return $null }
    $pick = Select-VMOutputRaw $pref $outs
    if (-not $pref -or ($pick -and (Test-OnboardOutput $pick))) {
        $ext = @($outs | Where-Object { -not (Test-OnboardOutput $_) })
        if ($ext.Count) {
            $sb = $ext | Where-Object { $_ -match 'Sound Blaster|Creative' } | Sort-Object { $_ -notmatch '^(Haut-parleurs|Speakers)\b' } | Select-Object -First 1
            if ($sb) { return $sb }
            $hp = $ext | Where-Object { $_ -match 'Casque|Headphone|Headset' } | Select-Object -First 1
            if ($hp) { return $hp }
            return $ext[0]
        }
    }
    $pick
}
function Select-VMOutputRaw([string]$pref, $outs) {
    # Sound Blaster (ex. GC7) : Creative indique "Haut-parleurs" comme peripherique de lecture principal
    # (jeu, musique) et "Casque/Headset" comme peripherique de communication (chat). Le choix prise casque /
    # sortie ligne se fait dans l'application Creative ou par le bouton du boitier, pas par le peripherique Windows.
    if ($pref -match '\(([^)]*Sound Blaster[^)]*)\)\s*$') {
        $hw0 = $Matches[1]
        $m = $outs | Where-Object { $_ -match '^(Haut-parleurs|Speakers)\b' -and $_ -like "*($hw0)*" } | Select-Object -First 1; if ($m) { return $m }
    }
    if ($pref) {
        $m = $outs | Where-Object { $_ -eq $pref } | Select-Object -First 1; if ($m) { return $m }
        $m = $outs | Where-Object { $_.StartsWith($pref) -or $pref.StartsWith($_) } | Select-Object -First 1; if ($m) { return $m }
        if ($pref -match '\(([^)]+)\)') { $hw = $Matches[1]; $kind = ($pref -split ' \(')[0]
            $m = $outs | Where-Object { $_ -like "*$hw*" -and $_ -like "$kind*" } | Select-Object -First 1; if ($m) { return $m }
            $m = $outs | Where-Object { $_ -like "*$hw*" } | Select-Object -First 1; if ($m) { return $m } }
    }
    $m = $outs | Where-Object { $_ -match 'Casque|Headphone|Headset' } | Select-Object -First 1; if ($m) { return $m }
    $outs[0]
}
# Options du menu Voicemeeter (stockees par Voicemeeter dans HKCU\VB-Audio\VoiceMeeter) :
# System Tray, ne pas afficher la fenetre au lancement, Auto Restart Audio Engine, WDM buffering 256.
# Voicemeeter reecrit ces valeurs en quittant : on le ferme d'abord, puis il redemarre cache dans la zone de notification.
function Set-VMOptions([scriptblock]$log) {
    $k = 'HKCU:\VB-Audio\VoiceMeeter'
    $want = [ordered]@{ SysTray = 1; SysTrayShowOnRun = 0; AutoRestart = 1; AutoRestartAll = 1; BufferingWDM = 256 }
    $cur = Get-ItemProperty $k -ErrorAction SilentlyContinue
    $todo = @($want.Keys | Where-Object { -not $cur -or $cur.$_ -ne $want[$_] })
    if (-not $todo.Count) { return }
    $running = Get-Process voicemeeter, voicemeeter_x64 -ErrorAction SilentlyContinue
    if ($running) {
        try { if ('VM' -as [type]) { [void][VM]::VBVMR_SetParameterFloat('Command.Shutdown', 1) } } catch {}
        for ($i = 0; $i -lt 20 -and (Get-Process voicemeeter, voicemeeter_x64 -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Milliseconds 250 }
        Get-Process voicemeeter, voicemeeter_x64 -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
        try { if ('VM' -as [type]) { [void][VM]::VBVMR_Logout() } } catch {}
    }
    New-Item $k -Force -ErrorAction SilentlyContinue | Out-Null
    foreach ($n in $want.Keys) { Set-ItemProperty $k -Name $n -Value $want[$n] -Type DWord }
    if ($log) { & $log "Options Voicemeeter : zone de notification, fenetre cachee, redemarrage auto du moteur audio, WDM 256" }
}
function Hide-VMWindow {
    try { [void][VM]::VBVMR_SetParameterFloat('Command.Show', 0) } catch {}
}
function Configure-VM([string]$headphones, [scriptblock]$log) {
    Set-VMOptions $log
    [void](Init-VM)
    Hide-VMWindow
    # Nom exact de l'entree tel que Voicemeeter le liste ("Art Tune Unified Output (VB-Audio Virtual Cable)") :
    # avec le nom court, Voicemeeter ne trouve pas le peripherique et le fait clignoter en rouge (aucun son)
    $inName = 'Art Tune Unified Output'
    for ($i = 0; $i -lt [VM]::VBVMR_Input_GetDeviceNumber(); $i++) {
        $t = 0; $nm = New-Object Text.StringBuilder 512; $hw = New-Object Text.StringBuilder 512
        [void][VM]::VBVMR_Input_GetDeviceDescA($i, [ref]$t, $nm, $hw)
        if ($t -eq 3 -and $nm.ToString().StartsWith('Art Tune Unified Output')) { $inName = $nm.ToString(); break }  # 3 = WDM
    }
    $rc1 = [VM]::VBVMR_SetParameterStringA('Strip[0].device.wdm', $inName)
    $rc2 = [VM]::VBVMR_SetParameterStringA('Bus[0].device.wdm', $headphones)
    [void][VM]::VBVMR_SetParameterFloat('Strip[0].A1', 1)
    & $log "Entree 1 = $inName ($(if ($rc1 -eq 0) {'OK'} else {"erreur $rc1"}))"
    & $log "Sortie A1 = $headphones ($(if ($rc2 -eq 0) {'OK'} else {"erreur $rc2"}))"
    if ($rc2 -eq 0) { try { $st = Get-State; $st.VmA1 = $headphones; Save-State $st } catch {} }
    # Demarrage avec Windows (equivalent de 'Run on Windows Startup')
    $run = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    $exe = Join-Path $VmDir 'voicemeeter_x64.exe'
    if (Test-Path $exe) { Set-ItemProperty $run -Name 'Voicemeeter' -Value "`"$exe`" -r"; & $log "Voicemeeter se lancera au demarrage de Windows." }
    Hide-VMWindow
}

# ============================================================================
# Installation / desinstallation silencieuses
# Reprend les sources et options du script officiel ArtIsWar (GPL-3.0) :
# memes installateurs, meme bibliotheque, memes plugins, memes HRIR.
# ============================================================================
$InstTemp = Join-Path $env:TEMP "TuneManager-install"
$PK_Friendly = '{a45c254e-df1c-4efd-8020-67d146a850e0},2'
$PK_Desc     = '{b3f8fa53-0004-438e-9003-51a46e139bfc},6'
$PK_FormF    = '{1da5d803-d492-4edd-8c23-e0c0ffee7f0e},0'
$PK_Icon     = '{259abffc-50a7-47ce-af08-68c9a7d73366},12'
# Format 16 canaux / 24 bits / 48 kHz (WAVEFORMATEXTENSIBLE, identique a une installation fonctionnelle)
$Fmt16Hex = '41,00,00,00,01,00,00,00,fe,ff,10,00,80,bb,00,00,00,28,23,00,30,00,18,00,16,00,18,00,00,00,00,00,01,00,00,00,00,00,10,00,80,00,00,aa,00,38,9b,71'

function Wait-Network([scriptblock]$log) {
    for ($i = 0; $i -lt 30; $i++) {
        try { $null = [Net.Dns]::GetHostAddresses('download.vb-audio.com'); return } catch {}
        if ($i -eq 0) { & $log "  En attente de la connexion Internet..." }
        Start-Sleep 2
    }
}
function Get-File([string]$url, [string]$out, [string]$fallback, [scriptblock]$log, [string]$label) {
    & $log "  Telechargement : $label"
    foreach ($try in 1..3) {
        foreach ($u in @($url, $fallback) | Where-Object { $_ }) {
            try {
                Invoke-WebRequest $u -OutFile $out -UseBasicParsing -UserAgent 'Mozilla/5.0' -TimeoutSec 180
                if ((Test-Path $out) -and (Get-Item $out).Length -gt 10KB) { Unblock-File $out -ErrorAction SilentlyContinue; return $true }
            } catch {}
            try {
                & curl.exe -sSL --retry 2 -A 'Mozilla/5.0' -o $out $u 2>$null
                if ((Test-Path $out) -and (Get-Item $out).Length -gt 10KB) { Unblock-File $out -ErrorAction SilentlyContinue; return $true }
            } catch {}
        }
        & $log "  (nouvel essai $try/3...)"; Start-Sleep (3 * $try)
    }
    throw "Telechargement impossible : $label (verifie ta connexion Internet)"
}function Get-VoicemeeterUrl {
    try {
        $page = (Invoke-WebRequest "https://vb-audio.com/Voicemeeter/index.htm" -UseBasicParsing -TimeoutSec 30).Content
        $m = [regex]::Match($page, 'download\.vb-audio\.com/Download_CABLE/VoicemeeterSetup[^"'']*\.zip', 'IgnoreCase')
        if ($m.Success) { return "https://$($m.Value)" }
    } catch {}
    "https://download.vb-audio.com/Download_CABLE/VoicemeeterSetup_v1122.zip"
}
function Wait-Proc($p, [int]$sec) { if (-not $p.WaitForExit($sec * 1000)) { try { $p.Kill() } catch {} }; $p.ExitCode }
# Attend la fin d'un installateur/desinstalleur en repondant tout seul a ses fenetres de confirmation
function Wait-ProcAuto($p, [int]$sec, [scriptblock]$log) {
    Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
    $A = [Windows.Automation.AutomationElement]; $CT = [Windows.Automation.ControlType]
    $deadline = (Get-Date).AddSeconds($sec); $clicked = @{}
    while (-not $p.HasExited -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 400
        $pids = @($p.Id) + @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$($p.Id)" -ErrorAction SilentlyContinue | ForEach-Object { $_.ProcessId })
        foreach ($id in $pids) {
            foreach ($win in $A::RootElement.FindAll('Children', (New-Object Windows.Automation.PropertyCondition($A::ProcessIdProperty, [int]$id)))) {
                try {
                    $txt = ($win.FindAll('Descendants', (New-Object Windows.Automation.PropertyCondition($A::ControlTypeProperty, $CT::Text))) | ForEach-Object { $_.Current.Name }) -join ' '
                    foreach ($cb in $win.FindAll('Descendants', (New-Object Windows.Automation.PropertyCondition($A::ControlTypeProperty, $CT::CheckBox)))) {
                        try { $t = $cb.GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern); if ($t.Current.ToggleState -ne 'On') { $t.Toggle() } } catch {}
                    }
                    $btns = @($win.FindAll('Descendants', (New-Object Windows.Automation.PropertyCondition($A::ControlTypeProperty, $CT::Button))) | ForEach-Object { $_ })
                    $re = if ($txt -match 'red.marr|restart|reboot') { '^(&?Non|&?No|Plus tard|Later)$' } else { '^(&?OK|&?Oui|&?Yes|&?D.sinstaller|&?Uninstall|&?Remove|&?Supprimer|&?Suivant|&?Next|&?Terminer|&?Finish|&?Fermer|&?Close)$' }
                    $b = $btns | Where-Object { $_.Current.Name -match $re -and $_.Current.IsEnabled } | Select-Object -First 1
                    if ($b) {
                        $key = "$($win.Current.NativeWindowHandle)|$($b.Current.Name)|$txt"
                        if (-not $clicked.ContainsKey($key)) { $clicked[$key] = 1; if ($log) { & $log "  (fenetre confirmee automatiquement : $($b.Current.Name))" } }
                        $b.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke()
                    }
                } catch {}
            }
        }
    }
    if (-not $p.HasExited) { try { $p.Kill() } catch {} }
    $p.ExitCode
}

function Find-CableEndpoints {
    $r8 = $null; $r16 = $null; $cap = $null; $vmR = $null; $vmC = $null
    foreach ($flow in 'Render', 'Capture') {
        foreach ($k in Get-ChildItem "$MMDev\$flow" -ErrorAction SilentlyContinue) {
            if (((Get-ItemProperty $k.PSPath).DeviceState -band 0xF) -ne 1) { continue }
            $p = Get-ItemProperty "$($k.PSPath)\Properties" -ErrorAction SilentlyContinue
            if (-not $p) { continue }
            $name = "$($p.$PK_Friendly)"
            if ($p.$PK_Desc -eq 'VB-Audio Virtual Cable') {
                if ($flow -eq 'Capture') { if (-not $cap) { $cap = $k.PSChildName } }
                elseif ([int]$p.$PK_FormF -eq 2) { if (-not $r16) { $r16 = $k.PSChildName } }
                elseif (-not $r8) { $r8 = $k.PSChildName }
            } elseif ($flow -eq 'Render' -and ($name -eq 'Voicemeeter Input' -or $name -eq 'Normal Audio')) { if (-not $vmR) { $vmR = $k.PSChildName } }
            elseif ($flow -eq 'Capture' -and ($name -eq 'Voicemeeter Out B1' -or $name -eq 'Virtual Mix' -or $name -like '*Voicemeeter Output*')) { if (-not $vmC) { $vmC = $k.PSChildName } }
        }
    }
    [pscustomobject]@{ Render8 = $r8; Render16 = $r16; Capture = $cap; VmRender = $vmR; VmCapture = $vmC }
}

function Set-CableEndpoints([scriptblock]$log) {
    $e = Find-CableEndpoints
    if (-not $e.Render16) { throw "Cable 16 canaux introuvable (VB-CABLE mal installe ?)." }
    if (-not ('AudioPolicy' -as [type])) { Add-Type $policyCs }
    foreach ($id in @($e.Render16, $e.VmRender) | Where-Object { $_ }) { [void][AudioPolicy]::SetVisible("{0.0.0.00000000}.$id", $true) }
    foreach ($id in @($e.Capture, $e.VmCapture) | Where-Object { $_ }) { [void][AudioPolicy]::SetVisible("{0.0.1.00000000}.$id", $true) }
    $icoDir = 'C:\ProgramData\ArtTune\icons'; New-Item -ItemType Directory $icoDir -Force | Out-Null
    $ico = @{}
    foreach ($n in 'ArtTuneCable.ico', 'ArtTunePlusCable.ico', 'ArtTuneUnifiedOutput.ico') {
        try { Invoke-WebRequest "https://cdn.artiswar.io/$n" -OutFile "$icoDir\$n" -UseBasicParsing -TimeoutSec 30; $ico[$n] = ("$icoDir\$n,0" -replace '\\', '\\') } catch {}
    }
    $R = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render'
    $C = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Capture'
    function Sec($key, $name, $icon) { $s = "`r`n[$key\Properties]`r`n`"$PK_Friendly`"=`"$name`"`r`n"; if ($icon) { $s += "`"$PK_Icon`"=`"$icon`"`r`n" }; $s }
    $reg = "Windows Registry Editor Version 5.00`r`n"
    if ($e.Render8)   { $reg += Sec "$R\$($e.Render8)" 'Art Tune' $ico['ArtTuneCable.ico'] }
    $reg += Sec "$R\$($e.Render16)" 'Art Tune +' $ico['ArtTunePlusCable.ico']
    if ($e.Capture)   { $reg += Sec "$C\$($e.Capture)" 'Art Tune Unified Output' $ico['ArtTuneUnifiedOutput.ico'] }
    if ($e.VmRender)  { $reg += Sec "$R\$($e.VmRender)" 'Normal Audio' $null }
    if ($e.VmCapture) { $reg += Sec "$C\$($e.VmCapture)" 'Virtual Mix' $null }
    $f = Join-Path $InstTemp 'endpoints.reg'; $reg | Out-File $f -Encoding ASCII -Force
    [void](Start-Process regedit.exe "/s `"$f`"" -Wait -PassThru -WindowStyle Hidden)
    $okName = "$((Get-ItemProperty "$MMDev\Render\$($e.Render16)\Properties" -ErrorAction SilentlyContinue).$PK_Friendly)" -eq 'Art Tune +'
    & $log $(if ($okName) { "  Peripheriques renommes (Art Tune, Art Tune +, Unified Output, Normal Audio, Virtual Mix)" } else { "  Renommage des peripheriques non applique" })
    # Format 16 canaux, 24 bits, 48 kHz pour Art Tune +
    $fr = "Windows Registry Editor Version 5.00`r`n`r`n[$R\$($e.Render16)\Properties]`r`n`"{f19f064d-082c-4e27-bc73-6882a1bb8e4c},0`"=hex:$Fmt16Hex`r`n"
    $ff = Join-Path $InstTemp 'format16.reg'; $fr | Out-File $ff -Encoding ASCII -Force
    # (format applique plus tard via l'API Windows, apres le Device Selector)
    try { Restart-Service Audiosrv -Force -ErrorAction Stop } catch { Start-Sleep 2; Restart-Service Audiosrv -Force -ErrorAction SilentlyContinue }
    for ($i = 0; $i -lt 30 -and (Get-Service Audiosrv).Status -ne 'Running'; $i++) { Start-Sleep -Milliseconds 500 }
    $e
}

function Write-StarterConfig($e) {
    $g8  = if ($e.Render8)  { $e.Render8.ToLower() }  else { $null }
    $g16 = $e.Render16.ToLower()
    $L = @("# ArtTuneDB config.txt", "# Complete each ""ArtTuneDB\library\"" path below, e.g. ...\BO7\V4\BO7_V4_pre.txt",
        "# Both sections are live -- switch device in game, do not comment either out.", "",
        "# ---- 8ch profile (Art Tune) - uses HeSuVi ----")
    if ($g8) { $L += "Device: Art Tune VB-Audio Virtual Cable $g8" }
    $L += @("# PRE HESUVI", "Include: ArtTuneDB\library\", "# DO NOT REMOVE HESUVI - LOAD HESUVI PRESET FOR VERSION #", "Include: HeSuVi\hesuvi.txt",
        "# EQ -- swap for your squig.link EQ (target file is in your version folder)", "Include: ArtTuneDB\library\", "# POST HESUVI", "Include: ArtTuneDB\library\",
        "# OUTPUT BOOST -- set your dB in ArtTuneDB\boost.txt (0 dB = off)", "Include: ArtTuneDB\boost.txt", "",
        "# ---- 16ch profile (Art Tune +) - no HeSuVi, needs the bundled VST ----", "# ONLY use files with _16ch_ in the name (see ""Choose a 16ch Tune.txt"").",
        "Device: Art Tune + VB-Audio Virtual Cable $g16", "# 16ch TUNE", "Include: ArtTuneDB\tune_active.txt", "# EQ -- swap for your squig.link EQ",
        "Include: ArtTuneDB\headphone_eq.txt", "# OUTPUT BOOST", "Include: ArtTuneDB\boost.txt")
    if (Test-Path $Config) { Copy-Item $Config "$Config.bak-tunemanager" -Force }
    [IO.File]::WriteAllText($Config, ($L -join "`r`n") + "`r`n")
}

$fmtCs = @'
using System; using System.Runtime.InteropServices;
[ComImport, Guid("f8679f50-850a-41cf-9c72-430f290290c8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IPolicyConfigF {
  int GetMixFormat([MarshalAs(UnmanagedType.LPWStr)] string id, out IntPtr fmt);
  int GetDeviceFormat([MarshalAs(UnmanagedType.LPWStr)] string id, int def, out IntPtr fmt);
  int ResetDeviceFormat([MarshalAs(UnmanagedType.LPWStr)] string id);
  int SetDeviceFormat([MarshalAs(UnmanagedType.LPWStr)] string id, IntPtr endpointFmt, IntPtr mixFmt);
}
[ComImport, Guid("870af99c-171d-4f9e-af0d-e63df40c2bc9")] class PolicyConfigClientF {}
public static class AudioFormat {
  public static int Set(string id, byte[] wfx) {
    IntPtr p = Marshal.AllocHGlobal(wfx.Length); Marshal.Copy(wfx, 0, p, wfx.Length);
    try { return ((IPolicyConfigF)new PolicyConfigClientF()).SetDeviceFormat(id, p, p); } finally { Marshal.FreeHGlobal(p); }
  }
}
public static class Mouse {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint x, uint y, uint d, IntPtr e);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  public static void Click(int x, int y) { SetCursorPos(x, y); mouse_event(2, 0, 0, 0, IntPtr.Zero); mouse_event(4, 0, 0, 0, IntPtr.Zero); }
}
'@
function Set-Format16([scriptblock]$log) {
    if (-not ('AudioFormat' -as [type])) { Add-Type $fmtCs }
    $e = Find-CableEndpoints
    $bytes = [byte[]]($Fmt16Hex -split ',' | ForEach-Object { [Convert]::ToByte($_, 16) } | Select-Object -Skip 8)
    $hr = [AudioFormat]::Set("{0.0.0.00000000}.$($e.Render16)", $bytes)
    Start-Sleep 1
    $ch = (Get-Endpoints | Where-Object { $_.Id -eq $e.Render16 }).Channels
    & $log $(if ($ch -eq 16) { "  Art Tune + regle en 16 canaux, 24 bits, 48 kHz" } else { "  Format 16 canaux non applique (code $hr, actuel $ch canaux)" })
}

# Pilote la fenetre officielle du Device Selector : coche Art Tune +, options de depannage, LFX/GFX, OK.
# Les clics sont envoyes directement a la fenetre (messages Windows) : pas besoin qu'elle soit au premier plan.
$pmCs = @'
using System; using System.Runtime.InteropServices;
public static class PM {
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [StructLayout(LayoutKind.Sequential)] public struct P { public int X, Y; }
  [DllImport("user32.dll")] public static extern bool ScreenToClient(IntPtr h, ref P p);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
  [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr h, int i, int v);
  [DllImport("user32.dll")] public static extern bool SetLayeredWindowAttributes(IntPtr h, uint k, byte a, uint f);
  public static void Hide(IntPtr h) { if (h == IntPtr.Zero) return; SetWindowLong(h, -20, GetWindowLong(h, -20) | 0x80000 | 0x80); SetLayeredWindowAttributes(h, 0, 0, 2); }
  public static void Click(IntPtr h, int sx, int sy) {
    P p; p.X = sx; p.Y = sy; ScreenToClient(h, ref p); IntPtr l = (IntPtr)((p.Y << 16) | (p.X & 0xFFFF));
    PostMessage(h, 0x0200, IntPtr.Zero, l); PostMessage(h, 0x0201, (IntPtr)1, l); PostMessage(h, 0x0202, IntPtr.Zero, l);
  }
}
'@
# Active Equalizer APO sur Art Tune + sans ouvrir le Device Selector : on ecrit exactement ce qu'il ecrit
# en mode "Installer en tant que LFX/GFX" (releve sur une installation reelle) :
#   MMDevices\...\Render\{id}\FxProperties : {d04e05a6...},1 = APO pre-mix, ,2 = APO post-mix
#   EqualizerAPO\Child APOs\{id}           : sauvegarde des effets d'origine ("!VALUE" = absent) + options
# Renvoie $false (=> repli sur le Device Selector) si la sortie a deja des effets a preserver ou si l'ecriture echoue.
function Enable-EapoDirect([scriptblock]$log) {
    $id = (Find-CableEndpoints).Render16; if (-not $id) { return $false }
    $fxSub = "SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render\$id\FxProperties"
    $pk = '{d04e05a6-594b-4fb6-a80d-01af5eed7d1d}'
    $fx = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($fxSub, [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree, [Security.AccessControl.RegistryRights]'SetValue, QueryValues')
    if (-not $fx) { & $log "  Ecriture directe impossible (FxProperties absent)"; return $false }
    try {
        $orig = @{}
        foreach ($n in 1, 2, 5, 6, 7) { $v = $fx.GetValue("$pk,$n"); if ($v -and ($EapoClsids -notcontains "$v".ToUpper())) { $orig[$n] = "$v" } }
        if ($orig.Count) { & $log "  Effets d'origine presents sur Art Tune + : Device Selector utilise"; return $false }
        $ch = [Microsoft.Win32.Registry]::LocalMachine.CreateSubKey("SOFTWARE\EqualizerAPO\Child APOs\$id")
        foreach ($n in 1, 2, 5, 6, 7) { $ch.SetValue("$pk,$n", '!VALUE', 'String') }
        $ch.SetValue('PreMixChild', '', 'String'); $ch.SetValue('PostMixChild', '', 'String')
        $ch.SetValue('AllowSilentBufferModification', 'false', 'String'); $ch.SetValue('Version', '2', 'String'); $ch.Close()
        $fx.SetValue("$pk,1", $EapoClsids[0], 'String'); $fx.SetValue("$pk,2", $EapoClsids[1], 'String')
    } catch { & $log "  Ecriture directe impossible ($($_.Exception.Message))"; return $false } finally { $fx.Close() }
    try { Restart-Service Audiosrv -Force -ErrorAction Stop } catch {}
    Start-Sleep 2
    $plus = Get-Endpoints | Where-Object { $_.Id -eq $id } | Select-Object -First 1
    $ok = [bool]($plus -and $plus.Eapo)
    & $log $(if ($ok) { "  Equalizer APO actif sur Art Tune + (reglage direct, sans Device Selector)" } else { "  Reglage direct non confirme : Device Selector utilise" })
    $ok
}
function Invoke-DeviceSelectorAuto([scriptblock]$log) {
    Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
    if (-not ('PM' -as [type])) { Add-Type $pmCs }
    [void][PM]::SetProcessDPIAware()
    $A = [Windows.Automation.AutomationElement]; $CT = [Windows.Automation.ControlType]
    function Cond($prop, $val) { New-Object Windows.Automation.PropertyCondition($prop, $val) }
    function Mid($el) { $r = $el.Current.BoundingRectangle; [int]($r.X + $r.Width / 2), [int]($r.Y + $r.Height / 2) }
    Get-Process DeviceSelector -ErrorAction SilentlyContinue | Stop-Process -Force
    $env:QT_PLUGIN_PATH = "C:\Program Files\EqualizerAPO\qt"
    $p = Start-Process "C:\Program Files\EqualizerAPO\DeviceSelector.exe" -WorkingDirectory "C:\Program Files\EqualizerAPO" -PassThru
    for ($i = 0; $i -lt 400 -and $p.MainWindowHandle -eq 0; $i++) { Start-Sleep -Milliseconds 50; $p.Refresh() }
    if ($p.MainWindowHandle -eq 0) { throw "Le Device Selector ne s'est pas ouvert." }
    [PM]::Hide($p.MainWindowHandle)   # fenetre deplacee hors de l'ecran : pilotage invisible
    Start-Sleep 1
    $h = $p.MainWindowHandle; $w = $A::FromHandle($h)
    $row = $null
    for ($i = 0; $i -lt 10 -and -not $row; $i++) {
        $row = $w.FindFirst('Descendants', (New-Object Windows.Automation.AndCondition((Cond $A::NameProperty 'Art Tune +'), (Cond $A::ControlTypeProperty $CT::TreeItem))))
        if (-not $row) { Start-Sleep -Milliseconds 500 }
    }
    if (-not $row) { throw "Art Tune + n'apparait pas dans le Device Selector." }
    try { $row.GetCurrentPattern([Windows.Automation.ScrollItemPattern]::Pattern).ScrollIntoView(); Start-Sleep -Milliseconds 400 } catch {}
    # 1. Cocher Art Tune +
    $tg = $row.GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern)
    foreach ($dx in 8, 22, 14) {
        if ($tg.Current.ToggleState -eq 'On') { break }
        $rc = $row.Current.BoundingRectangle; [PM]::Click($h, [int]($rc.X + $dx), [int]($rc.Y + $rc.Height / 2)); Start-Sleep -Milliseconds 700
    }
    if ($tg.Current.ToggleState -ne 'On') { throw "Impossible de cocher Art Tune + dans le Device Selector." }
    & $log "  Art Tune + coche"
    # 2. Options de depannage + clic sur le nom
    $tb = $w.FindFirst('Descendants', (Cond $A::AutomationIdProperty 'DeviceSelectorClass.troubleshootingGroupBox'))
    $t2 = $tb.GetCurrentPattern([Windows.Automation.TogglePattern]::Pattern); if ($t2.Current.ToggleState -ne 'On') { $t2.Toggle(); Start-Sleep -Milliseconds 500 }
    $sib = [Windows.Automation.TreeWalker]::ControlViewWalker.GetNextSibling($row)
    $x, $y = Mid $sib; [PM]::Click($h, $x, $y); Start-Sleep 1
    $cb = $tb.FindFirst('Descendants', (Cond $A::ControlTypeProperty $CT::ComboBox))
    if (-not $cb) { throw "Les options de depannage ne se sont pas affichees." }
    # 3. Choisir "Installer en tant que LFX/GFX"
    function CbVal { try { $cb.GetCurrentPattern([Windows.Automation.ValuePattern]::Pattern).Current.Value } catch { '' } }
    for ($try = 0; $try -lt 3 -and (CbVal) -notmatch 'LFX'; $try++) {
        try { $cb.GetCurrentPattern([Windows.Automation.ExpandCollapsePattern]::Pattern).Expand() } catch { $x, $y = Mid $cb; [PM]::Click($h, $x, $y) }
        Start-Sleep -Milliseconds 700
        $it = $A::RootElement.FindAll('Descendants', (New-Object Windows.Automation.AndCondition((Cond $A::ProcessIdProperty $p.Id), (Cond $A::ControlTypeProperty $CT::ListItem)))) | Where-Object { $_.Current.Name -match 'LFX' } | Select-Object -First 1
        if ($it) {
            if ($try -eq 0) { try { $it.GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern).Select() } catch {} }
            else {
                $ph = $it.Current.NativeWindowHandle; $anc = $it
                while ($ph -eq 0 -and $anc) { $anc = [Windows.Automation.TreeWalker]::RawViewWalker.GetParent($anc); if ($anc) { $ph = $anc.Current.NativeWindowHandle } }
                $x, $y = Mid $it; [PM]::Click([IntPtr]$ph, $x, $y)
            }
        }
        Start-Sleep -Milliseconds 500
        try { $cb.GetCurrentPattern([Windows.Automation.ExpandCollapsePattern]::Pattern).Collapse() } catch {}
        Start-Sleep -Milliseconds 300
    }
    if ((CbVal) -notmatch 'LFX') { throw "Impossible de choisir LFX/GFX (valeur : $(CbVal))." }
    & $log "  Mode : $(CbVal)"
    # 4. OK puis fenetres de confirmation
    $ok = $w.FindFirst('Descendants', (New-Object Windows.Automation.AndCondition((Cond $A::NameProperty 'OK'), (Cond $A::ControlTypeProperty $CT::Button))))
    try { $ok.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke() } catch { $x, $y = Mid $ok; [PM]::Click($h, $x, $y) }
    & $log "  Validation envoyee"
    for ($i = 0; $i -lt 200 -and -not $p.HasExited; $i++) {
        Start-Sleep -Milliseconds 150
        foreach ($win in $A::RootElement.FindAll('Children', (Cond $A::ProcessIdProperty $p.Id))) {
            if ($win.Current.Name -match 'Device Selector$') { continue }
            $txt = ($win.FindAll('Descendants', (Cond $A::ControlTypeProperty $CT::Text)) | ForEach-Object { $_.Current.Name }) -join ' '
            try { [PM]::Hide([IntPtr]$win.Current.NativeWindowHandle) } catch {}
            $btns = @($win.FindAll('Descendants', (Cond $A::ControlTypeProperty $CT::Button)) | ForEach-Object { $_ })
            if (-not $btns.Count) { continue }
            $pick = if ($txt -match 'red.marr|restart|reboot') { $btns | Where-Object { $_.Current.Name -match '^(Non|No|Plus tard|Later)$' } | Select-Object -First 1 } else { $null }
            if (-not $pick) { $pick = $btns | Where-Object { $_.Current.Name -match '^(OK|Oui|Yes)$' } | Select-Object -First 1 }
            if ($pick) {
                & $log "  Fenetre : $($txt.Substring(0, [Math]::Min(100, $txt.Length))) -> $($pick.Current.Name)"
                try { $pick.GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern).Invoke() } catch { $x, $y = Mid $pick; [PM]::Click([IntPtr]$win.Current.NativeWindowHandle, $x, $y) }
            }
        }
    }
    if (-not $p.HasExited) { try { $p.Kill() } catch {} }
    try { Restart-Service Audiosrv -Force -ErrorAction Stop } catch {}
    Start-Sleep 2
    $plus = Get-Endpoints | Where-Object { $_.Flow -eq 'Render' -and $_.Name -eq 'Art Tune +' } | Select-Object -First 1
    & $log $(if ($plus -and $plus.Eapo) { "  Equalizer APO actif sur Art Tune +" } else { "  Equalizer APO pas encore actif sur Art Tune +" })
    [bool]($plus -and $plus.Eapo)
}

# Reglages par defaut que HeSuVi.exe ecrit a son premier lancement (generiques, aucun peripherique).
# Les ecrire nous-memes evite de lancer HeSuVi, qui ouvrirait sa fenetre et sa page web.
$HeSuViDefaults = [ordered]@{
    'cfact.txt' = @('Eval: usecf=false')
    'cfmaster.txt' = @('Copy: LCF=1.00*LCF RCF=1.00*RCF')
    'conn.txt' = @('Copy: L=LVI R=RVI SL=0.0 SR=0.0 C=0.0 SUB=0.0 RL=0.0 RR=0.0', '# Copy: L=LVI R=RVI SL=LVI SR=RVI C=LVI SUB=RVI RL=LVI RR=RVI')
    'conv.txt' = @('Convolution: hrir\sonic-.wav')
    'conv44.txt' = @('Convolution: hrir\44\sonic-.wav')
    'crofe.txt' = @('Eval: cffq=700; dshb=3; xatt=-9; xdel=18; xshd=-10; xmet=false')
    'deact.txt' = @('Eval: active=true')
    'devna.txt' = @('Eval: device=""')
    'eocc.txt' = @('Eval: enough=true')
    'eqb.txt' = @('#1')
    'eqc.txt' = @('#1')
    'eqf.txt' = @('#1')
    'eqs.txt' = @('#1')
    'gain.txt' = @('Copy: L=-0dB*L R=-0dB*R C=-0dB*C SUB=-0dB*SUB RL=-0dB*RL RR=-0dB*RR SL=-0dB*SL SR=-0dB*SR')
    'incc.txt' = @('Eval: fakeChannelCount=inputChannelCount')
    'lfc.txt' = @('Copy: CVI=1.00*CVI+2.00*SUBVI')
    'master.txt' = @('Copy: LVI=1.00*LVI RVI=1.00*RVI')
    'matrix.txt' = @('Copy: L=0.5*L R=0.5*R C=0.2*L+0.2*R SUB=0.0 RL=0.3*L+-0.2*R RR=-0.2*L+0.3*R SL=0.45*L+-0.25*R SR=-0.25*L+0.45*R')
    'matrix5.1.txt' = @('Copy: RL=5 RR=6 SL=0.0 SR=0.0')
    'mix.txt' = @('Copy: LVI=1.00*L0+1.00*SL0+1.00*RL0+C0+1.00*L1+1.00*SL1+1.00*RL1 RVI=1.00*R1+1.00*SR1+1.00*RR1+1.00*R0+1.00*SR0+1.00*RR0+C1')
    'move.txt' = @('Copy: LVI=1.00*L+0.00*SL RVI=1.00*R+0.00*SR CVI=0.00*L+0.00*R+C RLVI=1.00*RL+0.00*RR+0.00*SL SUBVI=SUB RRVI=0.00*RL+1.00*RR+0.00*SR SLVI=0.00*L+0.00*RL+1.00*SL SRVI=0.00*R+0.00*RR+1.00*SR')
    'postlude.txt' = @('# Include: ')
    'prelude.txt' = @('# Include: ')
}
# 7-Zip temporaire (extrait du MSI officiel, rien n'est installe) pour deballer ReaPlugs et HeSuVi sans leurs fenetres
function Get-SevenZip {
    $zd = Join-Path $InstTemp '7z'
    $z = Get-ChildItem $zd -Recurse -Filter 7z.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
    if ($z) { return $z }
    $page = (Invoke-WebRequest 'https://www.7-zip.org/download.html' -UseBasicParsing -TimeoutSec 30).Content
    $msi = [regex]::Match($page, 'a/7z\d+-x64\.msi').Value; if (-not $msi) { $msi = 'a/7z2301-x64.msi' }
    $zm = Join-Path $InstTemp '7z.msi'
    Get-File "https://www.7-zip.org/$msi" $zm $null $script:__log '7-Zip (outil temporaire)' | Out-Null
    Start-Process msiexec.exe "/a `"$zm`" /qn TARGETDIR=`"$zd`"" -Wait -WindowStyle Hidden
    $z = Get-ChildItem $zd -Recurse -Filter 7z.exe | Select-Object -First 1 -ExpandProperty FullName
    if (-not $z) { throw "7-Zip introuvable" }
    $z
}
function Install-Silent([scriptblock]$log, [scriptblock]$progress) {
    $script:__log = $log
    New-Item -ItemType Directory $InstTemp -Force | Out-Null
    $step = 0; $total = 10
    # Step : debut d'une etape (10 % chacune) ; Sub : vraie avancee a l'interieur de l'etape (0..1)
    function Step($msg) { $script:__s++; $script:__m = $msg; & $progress ([int](10 * ($script:__s - 1))) $msg; & $log "[$($script:__s)/10] $msg" }
    function Sub([double]$f) { & $progress ([int](10 * ($script:__s - 1) + 10 * [Math]::Min(0.99, $f))) $script:__m }
    $script:__s = 0
    Get-Process voicemeeter*, Editor, DeviceSelector -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    # Memorise la vraie sortie par defaut AVANT que les cables virtuels ne la remplacent
    $defOut = Get-DefaultOutputName
    if ($defOut) { & $log "Sortie audio actuelle : $defOut (sera utilisee comme sortie A1 de Voicemeeter)" }

    Step "Telechargement des composants"
    Wait-Network $log
    $f = @{
        VBCable = Join-Path $InstTemp 'VBCable.zip'; Voicemeeter = Join-Path $InstTemp 'Voicemeeter.zip'
        ReaPlugs = Join-Path $InstTemp 'reaplugs.exe'; EAPO = Join-Path $InstTemp 'EqualizerAPO.exe'; HeSuVi = Join-Path $InstTemp 'HeSuVi.exe'
    }
    $needCable = -not (Find-CableEndpoints).Render16
    $needVm = -not (Test-Path "$VmDir\voicemeeter_x64.exe")
    $needRea = @(Get-ChildItem "$env:ProgramFiles\VSTPlugins\ReaPlugs\*.dll" -ErrorAction SilentlyContinue).Count -lt 5
    $needHe = -not (Test-Path "$Root\HeSuVi")
    $nDl = 1 + [int]$needCable + [int]$needVm + [int]$needRea + [int]$needHe; $iDl = 0; Sub 0.03
    if ($needCable) { Get-File 'https://download.vb-audio.com/Download_CABLE/VBCABLE_Driver_Pack45.zip' $f.VBCable $null $log 'VB-CABLE'; $iDl++; Sub ($iDl / $nDl) }
    if ($needVm)    { Get-File (Get-VoicemeeterUrl) $f.Voicemeeter $null $log 'Voicemeeter'; $iDl++; Sub ($iDl / $nDl) }
    if ($needRea)   { Get-File 'https://www.reaper.fm/reaplugs/reaplugs236_x64-install.exe' $f.ReaPlugs $null $log 'ReaPlugs'; $iDl++; Sub ($iDl / $nDl) }
    Get-File 'https://cdn.artiswar.io/other-installers/EqualizerAPO-x64-1.4.2.exe' $f.EAPO 'https://sourceforge.net/projects/equalizerapo/files/1.4/EqualizerAPO64-1.4.exe/download' $log 'Equalizer APO'; $iDl++; Sub ($iDl / $nDl)
    if ($needHe)    { Get-File 'https://cdn.artiswar.io/other-installers/HeSuVi_2.0.0.1.exe' $f.HeSuVi 'https://sourceforge.net/projects/hesuvi/files/HeSuVi_2.0.0.1.exe/download' $log 'HeSuVi' }

    Step "Installation de VB-CABLE (Windows peut demander d'autoriser le pilote)"
    if ($needCable) {
        $x = Join-Path $InstTemp 'vbcable'; Expand-Archive $f.VBCable $x -Force; Sub 0.3
        $exe = Get-ChildItem $x -Recurse -Filter VBCABLE_Setup_x64.exe | Select-Object -First 1
        $rc = Wait-ProcAuto (Start-Process $exe.FullName '-i -h' -PassThru) 240 $log
        & $log "  VB-CABLE : code $rc"
    } else { & $log "  Deja installe" }

    Step "Installation de Voicemeeter"
    if ($needVm) {
        $x = Join-Path $InstTemp 'vm'; Expand-Archive $f.Voicemeeter $x -Force; Sub 0.3
        $exe = Get-ChildItem $x -Recurse -Filter '*Setup*.exe' | Select-Object -First 1
        # Options ecrites AVANT tout lancement : zone de notification, fenetre cachee au demarrage.
        # Sinon Voicemeeter s'affiche jusqu'a son reglage en fin d'installation.
        Set-VMOptions $null
        # L'installateur lance Voicemeeter a la fin (fenetre visible un instant) : une surveillance le ferme des
        # qu'il apparait, pendant toute l'installation. Il est relance cache a l'etape 10.
        $vmWatch = Start-Job { $end = (Get-Date).AddMinutes(4); while ((Get-Date) -lt $end) { Get-Process voicemeeter, voicemeeter_x64 -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue; Start-Sleep -Milliseconds 80 } }
        Start-Sleep -Milliseconds 1500   # le temps que la surveillance demarre
        $rc = Wait-ProcAuto (Start-Process $exe.FullName '-i -h' -PassThru) 180 $log
        & $log "  Voicemeeter : code $rc"
        Start-Sleep 2; Stop-Job $vmWatch -ErrorAction SilentlyContinue; Remove-Job $vmWatch -Force -ErrorAction SilentlyContinue
        Get-Process voicemeeter, voicemeeter_x64 -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    } else { & $log "  Deja installe" }
    Set-VMOptions $null

    Step "Installation de ReaPlugs"
    if ($needRea) {
        # Extraction directe des fichiers (identiques a l'installateur) : pas de fenetre ni de page web
        $ok = $false
        try {
            $z = Get-SevenZip; Sub 0.35
            $out = Join-Path $InstTemp 'reaplugs'
            & $z x $f.ReaPlugs "-o$out" -y | Out-Null; Sub 0.65
            $dst = "$env:ProgramFiles\VSTPlugins\ReaPlugs"; New-Item -ItemType Directory $dst -Force | Out-Null
            Get-ChildItem $out -Recurse -File | Where-Object { $_.Name -notmatch '^reastream-standalone-\d+\.dll$|\.nsis$' } | ForEach-Object {
                $rel = $_.FullName.Substring($out.Length + 1); $t = Join-Path $dst $rel
                New-Item -ItemType Directory (Split-Path $t) -Force | Out-Null; Copy-Item $_.FullName $t -Force }
            $ok = @(Get-ChildItem "$dst\*.dll").Count -ge 5
            & $log "  ReaPlugs installe ($(@(Get-ChildItem "$dst\*.dll").Count) DLL, fichiers identiques a l'installateur officiel)"
        } catch { & $log "  Extraction impossible ($($_.Exception.Message)), installation classique" }
        if (-not $ok) { $rc = Wait-Proc (Start-Process $f.ReaPlugs '/S' -PassThru -WindowStyle Hidden) 120; & $log "  ReaPlugs : code $rc" }
    } else { & $log "  Deja installe" }

    Step "Installation d'Equalizer APO"
    $eapoRoot = Join-Path $env:ProgramFiles 'EqualizerAPO'
    $p = Start-Process $f.EAPO "/S /D=$eapoRoot" -PassThru
    # L'installateur ouvre le Device Selector a la fin : on le laisse ouvert pour l'etape 2
    for ($i = 0; $i -lt 240 -and -not $p.HasExited; $i++) {
        if (Get-Process DeviceSelector -ErrorAction SilentlyContinue) { break }
        if ($i % 2 -eq 0) { Sub ([Math]::Min(0.8, $i / 100)) }
        Start-Sleep -Milliseconds 500
    }
    Get-Process DeviceSelector -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    [void]$p.WaitForExit(60000); Sub 0.85
    if (-not (Test-Path $Root)) { throw "Equalizer APO ne s'est pas installe." }
    New-Item -ItemType Directory $DB -Force | Out-Null
    Set-Content (Join-Path $DB 'ArtIsWar.url') "[InternetShortcut]`r`nURL=https://artiswar.io"
    Set-Content (Join-Path $DB 'ArtTuneDB.url') "[InternetShortcut]`r`nURL=https://github.com/ArtIsWar/ArtTuneDB"
    Ensure-DbExtras
    try { Invoke-WebRequest 'https://cdn.artiswar.io/ArtTuneDBLogo.ico' -OutFile (Join-Path $DB 'ArtTuneDB.ico') -UseBasicParsing -TimeoutSec 30 } catch {}
    & $log "  Equalizer APO installe"

    Step "Installation de HeSuVi"
    if ($needHe) {
        # Extraction directe : l'installateur lance setup.cmd (fenetre noire) qui copie le dossier HeSuVi,
        # cree un raccourci puis ouvre HeSuVi et sa page web. On fait la copie et le raccourci, sans rien ouvrir.
        $ok = $false
        try {
            $z = Get-SevenZip; Sub 0.3
            & $z x $f.HeSuVi 'HeSuVi\*' "-o$Root" -y | Out-Null; Sub 0.85
            $ok = Test-Path "$Root\HeSuVi\hesuvi.txt"
            if ($ok) { foreach ($k in $HeSuViDefaults.Keys) { $t = Join-Path "$Root\HeSuVi" $k; if (-not (Test-Path $t)) { [IO.File]::WriteAllText($t, ($HeSuViDefaults[$k] -join "`r`n")) } } }
            if ($ok) {
                $sm = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\HeSuVi'; New-Item -ItemType Directory $sm -Force | Out-Null
                $s = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $sm 'HeSuVi.lnk')); $s.TargetPath = "$Root\HeSuVi\HeSuVi.exe"; $s.Save()
            }
        } catch { & $log "  Extraction impossible ($($_.Exception.Message)), installation classique" }
        if (-not $ok) {
            $rc = Wait-ProcAuto (Start-Process $f.HeSuVi '-y' -PassThru) 180 $log
            Start-Sleep 2; Get-Process HeSuVi* -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        }
        & $log $(if (Test-Path "$Root\HeSuVi") { "  HeSuVi installe (sans fenetre)" } else { "  HeSuVi non installe (inutile pour les presets 16ch comme MW4)" })
    } else { & $log "  Deja installe" }

    Step "Bibliotheque ArtTuneDB et moteur ATK"
    $rel = Get-RemoteRelease; if (-not $rel) { throw "Impossible de joindre GitHub / artiswar.io pour la bibliotheque." }; Sub 0.15
    Update-Library $rel $log

    Step "HRIR"
    $h = Join-Path $Root 'HeSuVi\hrir'; New-Item -ItemType Directory "$h\44" -Force | Out-Null
    foreach ($n in 'EAC_Default', 'EAC_Refined') {
        try { Invoke-WebRequest "https://cdn.artiswar.io/HeSuVi/hrir/$n.wav" -OutFile "$h\$n.wav" -UseBasicParsing -TimeoutSec 60
              Invoke-WebRequest "https://cdn.artiswar.io/HeSuVi/hrir/44/$n.wav" -OutFile "$h\44\$n.wav" -UseBasicParsing -TimeoutSec 60; & $log "  $n OK"; Sub $(if ($n -eq 'EAC_Default') { 0.5 } else { 0.95 }) }
        catch { & $log "  $n : echec ($($_.Exception.Message))" }
    }

    Step "Configuration des peripheriques audio"
    Sync-PersonalEq
    $e = Set-CableEndpoints $log; Sub 0.4
    $e = Find-CableEndpoints
    Write-StarterConfig $e; Sub 0.6
    if (-not (Test-Path $BoostF)) { [IO.File]::WriteAllText($BoostF, "# ArtTuneDB Output Boost -- set your dB below and save. 0 dB = off.`r`n# config.txt includes this last on every chain; E-APO reloads it live.`r`nPreamp: 0 dB`r`n") }
    $st = Get-State
    $g, $v = if ($st.Game) { $st.Game -split '\|' } else { 'MW4', 'V1' }
    $t = Apply-Selection $g $v $(if ($st.Family) { $st.Family } else { 'TheaterClear' }) $(if ($st.Gun) { $st.Gun } else { 'UltraLo' }) $(if ($st.Hrir) { $st.Hrir } else { 'KU100' }) $st.Eq ([int](Get-Boost))
    & $log "  config.txt ecrit, preset : $(Split-Path $t.Path -Leaf)"

    Step "Activation d'Equalizer APO et nettoyage"
    # Reglage direct du registre (invisible) ; Device Selector pilote seulement en secours
    $direct = $false; try { $direct = Enable-EapoDirect $log } catch { & $log "  Reglage direct : $($_.Exception.Message)" }
    if (-not $direct) { try { [void](Invoke-DeviceSelectorAuto $log) } catch { & $log "  Device Selector : $($_.Exception.Message)" } }
    Sub 0.3
    Set-Format16 $log; Sub 0.5
    Disable-ExtraDevices $log; Sub 0.65
    # Voicemeeter : entree Art Tune Unified Output, sortie A1 = la sortie par defaut d'avant l'installation
    try {
        $st = $null
        if (Test-Path (Join-Path $DB '.')) { $st = Get-State; if ($defOut) { $st['VmOut'] = $defOut; Save-State $st } elseif ($st.VmOut) { $defOut = $st.VmOut } }
        # Une sortie deja choisie dans Tune Manager (reinstallation, reparation) reste prioritaire si elle existe encore
        $out = $null
        if ($st -and $st.VmA1) { $out = @(Get-VMOutputs) | Where-Object { $_ -eq $st.VmA1 } | Select-Object -First 1; if ($out) { & $log "  Sortie A1 conservee : $out" } }
        if (-not $out) { $out = Select-VMOutput $defOut }
        # $instLog et non $log : dans Configure-VM, $log designe ce bloc lui-meme (recursion infinie)
        $instLog = $log
        if ($out) { & $log "  Voicemeeter :"; Configure-VM $out { param($m) & $instLog "    $m" } } else { & $log "  Voicemeeter : aucune sortie trouvee, a regler a l'etape 3" }
    } catch { & $log "  Voicemeeter : $($_.Exception.Message) (a regler a l'etape 3)" }
    Remove-Item $InstTemp -Recurse -Force -ErrorAction SilentlyContinue
    & $progress 100 "Termine"
    & $log ""
    & $log "Installation terminee."
}

function Uninstall-Silent([scriptblock]$log, [scriptblock]$progress) {
    & $progress 5 "Arret des applications audio"
    Get-Process voicemeeter*, VBVoicemeeter*, VBCABLE*, HeSuVi*, Editor, DeviceSelector -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    $steps = @(
        @('Equalizer APO', "$env:ProgramFiles\EqualizerAPO\Uninstall.exe", '/S'),
        @('ReaPlugs', "$env:ProgramFiles\VSTPlugins\ReaPlugs\ReaPlugs-Uninst.exe", '/S'),
        @('VB-CABLE', "$env:ProgramFiles\VB\CABLE\VBCABLE_Setup_x64.exe", '-u -h'),
        @('Voicemeeter VAIO', "$env:ProgramFiles\VB\VBVoicemeeterVAIOs\VBVoicemeeterVAIO_Setup_x64.exe", '-u -h'),
        @('Voicemeeter', "$VmDir\voicemeetersetup.exe", '-u -h'))
    $i = 0
    foreach ($s in $steps) {
        $i++; & $progress ([int](10 + 60 * $i / $steps.Count)) "Desinstallation : $($s[0])"
        if (Test-Path $s[1]) { $rc = Wait-ProcAuto (Start-Process $s[1] $s[2] -PassThru) 180 $log; & $log "$($s[0]) : code $rc" } else { & $log "$($s[0]) : absent" }
    }
    & $progress 72 "Suppression des peripheriques fantomes"
    # Peripheriques VB-Audio / Voicemeeter (presents ou fantomes) - jamais ceux d'une vraie carte son
    $devs = @(Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { ("$($_.FriendlyName)" -match 'VB-Audio|Voicemeeter|Virtual Cable') -or ("$($_.Manufacturer)" -match 'VB-Audio') })
    foreach ($d in $devs) {
        $p = Start-Process pnputil.exe "/remove-device `"$($d.InstanceId)`"" -Wait -PassThru -WindowStyle Hidden
        if ($p.ExitCode -eq 0) { & $log "Peripherique retire : $($d.FriendlyName)" }
    }
    & $log "$($devs.Count) peripherique(s) VB-Audio traite(s)"
    & $progress 74 "Reinitialisation des cartes son"
    # Cartes son reelles dont une sortie a ete renommee par une installation Art Tune : on les retire
    # puis Windows les redetecte avec leurs noms et reglages d'origine (comme un rebranchement sur un PC neuf).
    $hw = @{}
    foreach ($flow in 'Render', 'Capture') {
        foreach ($k in Get-ChildItem "$MMDev\$flow" -ErrorAction SilentlyContinue) {
            $p = Get-ItemProperty "$($k.PSPath)\Properties" -ErrorAction SilentlyContinue
            if (-not $p) { continue }
            $nm = "$($p.$PK_Friendly)"; $ifc = "$($p.$PK_Desc)"; $par = "$($p.'{b3f8fa53-0004-438e-9003-51a46e139bfc},2')" -replace '^\{\d+\}\.', ''
            if ($ifc -match 'VB-Audio|Voicemeeter' -or -not $par) { continue }
            if ($nm -match '^(Art Tune|Audio Normal|Normal Audio|Virtual Mix)') { $hw[$par] = $ifc }
        }
    }
    foreach ($par in $hw.Keys) {
        $eps = @(Get-PnpDevice -Class AudioEndpoint -ErrorAction SilentlyContinue | Where-Object { "$($_.FriendlyName)" -like "*($($hw[$par]))" })
        foreach ($d in $eps) { [void](Start-Process pnputil.exe "/remove-device `"$($d.InstanceId)`"" -Wait -PassThru -WindowStyle Hidden) }
        [void](Start-Process pnputil.exe "/remove-device `"$par`"" -Wait -PassThru -WindowStyle Hidden)
        & $log "Carte son reinitialisee : $($hw[$par])"
    }
    if ($hw.Count) { Start-Sleep 2; [void](Start-Process pnputil.exe '/scan-devices' -Wait -PassThru -WindowStyle Hidden); Start-Sleep 5 }
    else { & $log "Aucune carte son a reinitialiser" }
    & $progress 76 "Suppression des pilotes VB-Audio"
    $drv = @(Get-WindowsDriver -Online -ErrorAction SilentlyContinue | Where-Object { "$($_.ProviderName)" -match 'VB-Audio' })
    foreach ($d in $drv) {
        $p = Start-Process pnputil.exe "/delete-driver $($d.Driver) /uninstall /force" -Wait -PassThru -WindowStyle Hidden
        & $log "Pilote $($d.Driver) ($($d.OriginalFileName | Split-Path -Leaf)) : $(if ($p.ExitCode -eq 0) { 'supprime' } else { "code $($p.ExitCode)" })"
    }
    if (-not $drv.Count) { & $log "Aucun pilote VB-Audio dans le magasin de pilotes" }
    & $progress 80 "Suppression des restes"
    foreach ($d in "$env:ProgramFiles\EqualizerAPO", "$env:ProgramFiles\VSTPlugins\ArtTuneKit", "$env:ProgramFiles\VSTPlugins\ReaPlugs", "${env:ProgramFiles(x86)}\VB", "$env:ProgramFiles\VB", 'C:\ProgramData\ArtTune', "$env:TEMP\ArtIsWar-Setup", $InstTemp, "$env:USERPROFILE\Documents\Voicemeeter") {
        if (Test-Path $d) { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue; & $log "Supprime : $d" }
    }
    if ((Test-Path "$env:ProgramFiles\VSTPlugins") -and -not (Get-ChildItem "$env:ProgramFiles\VSTPlugins")) { Remove-Item "$env:ProgramFiles\VSTPlugins" -Force }
    foreach ($l in "$([Environment]::GetFolderPath('Desktop'))\ArtTuneDB.lnk", "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\Voicemeeter (VB-Audio).LNK", "$env:APPDATA\VoiceMeeterDefault.xml") {
        if (Test-Path $l) { Remove-Item $l -Force; & $log "Supprime : $l" }
    }
    Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'Voicemeeter' -ErrorAction SilentlyContinue
    Remove-Item 'HKLM:\SOFTWARE\EqualizerAPO' -Recurse -Force -ErrorAction SilentlyContinue
    # Reglages Voicemeeter / VB-Audio : sinon une reinstallation reprend l'ancienne configuration
    foreach ($k in 'HKLM:\SOFTWARE\VB-Audio', 'HKLM:\SOFTWARE\WOW6432Node\VB-Audio', 'HKCU:\Software\VB-Audio') {
        if (Test-Path $k) { Remove-Item $k -Recurse -Force -ErrorAction SilentlyContinue; & $log "Supprime : $k" }
    }
    # Entrees "Programmes installes" orphelines (si un desinstalleur a echoue et que son dossier n'existe plus)
    foreach ($k in Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall' -ErrorAction SilentlyContinue) {
        $p = Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue
        if ("$($p.DisplayName)" -match '^(Equalizer APO|ReaPlugs|Voicemeeter|VB-Audio|VB-CABLE|HeSuVi)') {
            $exe = ("$($p.UninstallString)" -replace '^"([^"]+)".*$', '$1')
            if (-not $exe -or -not (Test-Path $exe)) { Remove-Item $k.PSPath -Recurse -Force -ErrorAction SilentlyContinue; & $log "Entree orpheline supprimee : $($p.DisplayName)" }
        }
    }
    Register-UpdateTask $false
    & $progress 100 "Termine"
    & $log ""
    & $log "Desinstallation terminee. Redemarre le PC pour retirer completement les pilotes audio."
}

# Verification d'integrite : fichiers installes = fichiers de la bibliotheque officielle
function Test-Integrity {
    $r = @()
    $srcVst = Join-Path $Lib 'vst'
    if (Test-Path $srcVst) {
        foreach ($d in Get-ChildItem $srcVst -Filter *.dll) {
            $dst = Join-Path $VstDir $d.Name
            $r += [pscustomobject]@{ Ok = (Test-Path $dst) -and ((Get-FileHash $dst).Hash -eq (Get-FileHash $d.FullName).Hash); Text = "Moteur VST identique a l'officiel : $($d.Name)" }
        }
    }
    $srcJs = Join-Path $Lib 'jsfx'
    if (Test-Path $srcJs) {
        foreach ($d in Get-ChildItem $srcJs -Filter *.jsfx) {
            $dst = Join-Path $JsfxDir $d.Name
            $r += [pscustomobject]@{ Ok = (Test-Path $dst) -and ((Get-FileHash $dst).Hash -eq (Get-FileHash $d.FullName).Hash); Text = "Moteur JSFX identique a l'officiel : $($d.Name)" }
        }
    }
    $tune = if (Test-Path $TuneF) { (Select-String $TuneF -Pattern '^Include:\s*(.+)$').Matches[0].Groups[1].Value.Trim() } else { $null }
    $r += [pscustomobject]@{ Ok = $tune -and (Test-Path (Join-Path $DB $tune)); Text = "Preset actif present dans la bibliotheque officielle$(if ($tune) { " ($(Split-Path $tune -Leaf))" })" }
    $r
}

$ProgFile = Join-Path $env:TEMP 'TuneManager-progress.json'
if ($RunRepair) {
    $L = New-Object System.Collections.Generic.List[string]; $lg = { param($m) $L.Add([string]$m); $L | Set-Content "$env:PUBLIC\tm-repair.log" -Encoding UTF8 }
    try { New-Item -ItemType Directory $InstTemp -Force | Out-Null; [void](Set-CableEndpoints $lg); Write-StarterConfig (Find-CableEndpoints); if (-not (Enable-EapoDirect $lg)) { [void](Invoke-DeviceSelectorAuto $lg) }; Set-Format16 $lg; Disable-ExtraDevices $lg; & $lg "FIN" } catch { & $lg "ERREUR : $($_.Exception.Message)" }
    exit
}
if ($RunInstall -or $RunUninstall) {
    $script:P = @{ Pct = 0; Msg = 'Demarrage'; Step = 0; Done = $false; Error = $null; Log = New-Object System.Collections.Generic.List[string] }
    function Save-P { try { ($script:P | ConvertTo-Json -Depth 3 -Compress) | Set-Content $ProgFile -Encoding UTF8 } catch {} }
    $lg = { param($m) $script:P.Log.Add([string]$m); Save-P }
    $pg = { param($pct, $msg) $script:P.Pct = $pct; $script:P.Msg = $msg; $script:P.Step = $(if ($script:__s) { [int]$script:__s } else { [int][Math]::Ceiling($pct / 10) }); Save-P }
    Save-P
    try { if ($RunInstall) { Install-Silent $lg $pg | Out-Null } else { Uninstall-Silent $lg $pg | Out-Null } }
    catch { $script:P.Error = $_.Exception.Message; $script:P.Log.Add("ERREUR : $($_.Exception.Message)") }
    $script:P.Done = $true; Save-P
    exit
}
# ============================================================================
# Modes texte
# ============================================================================
if ($Check) {
    "Tune Manager - diagnostic (lecture seule)"; "Bibliotheque locale : $(Get-LocalVersion)"
    $rel = Get-RemoteRelease; "Derniere version publiee : $(if ($rel) { "$($rel.Version) ($($rel.Source))" } else { 'injoignable' })"
    "Presets 16ch : $((Get-Tunes).Count)"
    Get-Diagnostic | ForEach-Object { "{0}  {1}" -f $(if ($_.Ok) { '[OK]' } else { '[!] ' }), $_.Text }
    $vm = if (Get-Process voicemeeter* -ErrorAction SilentlyContinue) { Get-VMCurrent }; if ($vm) { "Voicemeeter : entree 1 = $($vm.Input) ; A1 = $($vm.A1)" }
    exit
}
if ($VmTest) { "Sorties :"; Get-VMOutputs; $v = Get-VMCurrent; "Actuel : $($v.Input) / $($v.A1)"; exit }
if ($AutoCheck) {
    $rel = Get-RemoteRelease; $loc = Get-LocalVersion
    if ($rel -and $loc -and $rel.Version -ne $loc) {
        Add-Type -AssemblyName System.Windows.Forms, System.Drawing
        $n = New-Object Windows.Forms.NotifyIcon; $n.Icon = [Drawing.SystemIcons]::Information; $n.Visible = $true
        $n.BalloonTipTitle = 'Tune Manager'; $n.BalloonTipText = "Nouvelle bibliotheque ArtTuneDB : $($rel.Version) (tu as $loc). Ouvre Tune Manager pour mettre a jour."
        $n.add_BalloonTipClicked({ Start-Process powershell "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`"" })
        $n.ShowBalloonTip(15000); Start-Sleep 20; $n.Dispose()
    }
    exit
}

# ============================================================================
# Installation du logiciel lui-meme (comme un programme classique)
#   -InstallApp : copie dans Program Files, raccourcis, entree "Applications installees"
#   -RemoveApp  : desinstalle le logiciel (et, si demande, toute la chaine audio)
# ============================================================================
$AppDir    = Join-Path $env:ProgramFiles 'Tune Manager'
$AppUninst = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\TuneManager'
# Version et depot GitHub : version.txt / repo.txt a cote du script (installes), ou dans Setup\ (developpement)
function Read-AppFile([string]$n) {
    foreach ($d in $PSScriptRoot, (Join-Path $PSScriptRoot 'Setup')) { $f = Join-Path $d $n; if (Test-Path $f) { return ([IO.File]::ReadAllText($f)).Trim() } }
    $null
}
$AppVer  = Read-AppFile 'version.txt'; if (-not $AppVer) { $AppVer = '2.0.0' }
$AppRepo = Read-AppFile 'repo.txt'       # ex. "compte/tune-manager"
$StartTask = 'TuneManager - demarrage'
function New-AppShortcut([string]$lnk, [string]$script, [string]$args2 = '') {
    $sh = New-Object -ComObject WScript.Shell; $s = $sh.CreateShortcut($lnk)
    $s.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $s.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`"$args2"
    $s.WorkingDirectory = Split-Path $script; $s.WindowStyle = 7
    $ico = Join-Path (Split-Path $script) 'TuneManager.ico'; if (Test-Path $ico) { $s.IconLocation = "$ico,0" }
    $s.Description = 'Tune Manager - chaine audio ArtTuneDB'; $s.Save()
}
function Register-StartupTask([bool]$enable, [string]$script = $PSCommandPath) {
    Unregister-ScheduledTask -TaskName $StartTask -Confirm:$false -ErrorAction SilentlyContinue
    if (-not $enable) { return }
    $exe = Join-Path (Split-Path $script) 'TuneManager.exe'
    $a = if (Test-Path $exe) { New-ScheduledTaskAction -Execute $exe -Argument '-Tray' } else { New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`" -Tray" }
    $t = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"; $t.Delay = 'PT20S'
    $p = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
    $se = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)
    Register-ScheduledTask -TaskName $StartTask -Action $a -Trigger $t -Principal $p -Settings $se -Description 'Lance Tune Manager dans la zone de notification' | Out-Null
}
function Test-StartupTask { [bool](Get-ScheduledTask -TaskName $StartTask -ErrorAction SilentlyContinue) }
# Boite de dialogue aux couleurs de Tune Manager (remplace la MessageBox grise de Windows).
# Renvoie 'Yes' / 'No' / 'Cancel' / 'OK' comme MessageBox. $labels : textes des boutons, ex. @{ Yes = 'Supprimer' }
# Titre : premiere ligne du message (si courte), le reste est le texte.
function Show-Msg([string]$t, [string]$btn = 'OK', [string]$icon = 'Information', [hashtable]$labels = @{}) {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    $dx = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Tune Manager" Width="520" SizeToContent="Height" WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ResizeMode="NoResize" WindowStartupLocation="CenterScreen" ShowInTaskbar="False" Topmost="True"
        FontFamily="Segoe UI Variable Display, Segoe UI" Foreground="#F5EFEE">
  <Window.Resources>
    <LinearGradientBrush x:Key="Acc" StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#FF6A45" Offset="0"/><GradientStop Color="#E23A22" Offset="1"/></LinearGradientBrush>
    <Style x:Key="P" TargetType="Button">
      <Setter Property="Foreground" Value="White"/><Setter Property="FontSize" Value="14"/><Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Height" Value="42"/><Setter Property="Padding" Value="22,0"/><Setter Property="Cursor" Value="Hand"/><Setter Property="Margin" Value="10,0,0,0"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
        <Grid x:Name="g">
          <Border CornerRadius="14" Background="#FF4A2E"><Border.Effect><DropShadowEffect Color="#FF4A2E" BlurRadius="22" ShadowDepth="0" Opacity="0.5"/></Border.Effect></Border>
          <Border CornerRadius="14" Background="{StaticResource Acc}" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
        </Grid>
        <ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="g" Property="Opacity" Value="0.9"/></Trigger></ControlTemplate.Triggers>
      </ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style x:Key="G" TargetType="Button">
      <Setter Property="Foreground" Value="#F5EFEE"/><Setter Property="FontSize" Value="14"/><Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Height" Value="42"/><Setter Property="Padding" Value="20,0"/><Setter Property="Cursor" Value="Hand"/><Setter Property="Margin" Value="10,0,0,0"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
        <Border x:Name="b" CornerRadius="14" Background="#1C1110" BorderBrush="#3A2420" BorderThickness="1" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
        <ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="#FF5236"/></Trigger></ControlTemplate.Triggers>
      </ControlTemplate></Setter.Value></Setter>
    </Style>
  </Window.Resources>
  <Grid Margin="24">
    <Border CornerRadius="22" Background="#140B0A"><Border.Effect><DropShadowEffect Color="#FF4A2E" BlurRadius="40" ShadowDepth="0" Opacity="0.28"/></Border.Effect></Border>
    <Border x:Name="Frame" CornerRadius="22" BorderBrush="#5A2A20" BorderThickness="1" Padding="28,24,28,22">
      <Border.Background><LinearGradientBrush StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#2A1411" Offset="0"/><GradientStop Color="#140B0A" Offset="1"/></LinearGradientBrush></Border.Background>
      <StackPanel>
        <Grid Margin="0,0,0,16">
          <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition/></Grid.ColumnDefinitions>
          <Border x:Name="Ico" Width="46" Height="46" CornerRadius="15" Margin="0,0,18,0" VerticalAlignment="Top">
            <TextBlock x:Name="IcoT" FontSize="22" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <StackPanel Grid.Column="1" VerticalAlignment="Center">
            <TextBlock Text="TUNE MANAGER" FontSize="11" FontWeight="Bold" Foreground="#FF5236" Margin="0,0,0,4"/>
            <TextBlock x:Name="Ttl" FontSize="19" FontWeight="Bold" TextWrapping="Wrap"/>
          </StackPanel>
        </Grid>
        <TextBlock x:Name="Msg" FontSize="14" Foreground="#C9BAB6" TextWrapping="Wrap" LineHeight="21" Margin="0,0,0,24"/>
        <StackPanel x:Name="Btns" Orientation="Horizontal" HorizontalAlignment="Right"/>
      </StackPanel>
    </Border>
  </Grid>
</Window>
'@
    $w = [Windows.Markup.XamlReader]::Parse($dx)
    $bc = New-Object Windows.Media.BrushConverter
    $parts = $t -split "`n", 2
    if ($parts.Count -gt 1 -and $parts[0].Length -le 70) { $ttl = $parts[0]; $body = $parts[1].Trim() } else { $ttl = 'Tune Manager'; $body = $t }
    $w.FindName('Ttl').Text = $ttl; $w.FindName('Msg').Text = ($body -replace "`r?`n", "`n`n")
    if (-not $body) { $w.FindName('Msg').Visibility = 'Collapsed' }
    $ico = $w.FindName('Ico'); $it = $w.FindName('IcoT')
    if ($icon -match 'Warning|Error|Exclamation|Stop|Hand') {
        $ico.Background = $bc.ConvertFromString('#2E1210'); $ico.BorderBrush = $bc.ConvertFromString('#FF5236'); $ico.BorderThickness = 1.5; $it.Text = '!'; $it.Foreground = $bc.ConvertFromString('#FF5236')
    } else {
        $ico.Background = $w.FindResource('Acc'); $it.Foreground = [Windows.Media.Brushes]::White; $it.Text = $(if ($icon -eq 'Question') { '?' } else { 'i' })
    }
    $res = @{ V = $(switch ($btn) { 'YesNo' { 'No' } 'YesNoCancel' { 'Cancel' } 'OKCancel' { 'Cancel' } default { 'OK' } }) }
    $def = @{ Yes = 'Oui'; No = 'Non'; Cancel = 'Annuler'; OK = 'OK' }
    $order = switch ($btn) { 'YesNo' { @('No', 'Yes') } 'YesNoCancel' { @('Cancel', 'No', 'Yes') } 'OKCancel' { @('Cancel', 'OK') } default { @('OK') } }
    # Trois boutons aux libelles longs : la fenetre s'elargit pour qu'aucun ne soit coupe
    $w.Width = [Math]::Max(520.0, 140.0 + (($order | ForEach-Object { $(if ($labels.ContainsKey($_)) { $labels[$_] } else { $def[$_] }).Length }) | Measure-Object -Sum).Sum * 9.0 + 60.0 * $order.Count)
    foreach ($k in $order) {
        $b = New-Object Windows.Controls.Button
        $b.Content = if ($labels.ContainsKey($k)) { $labels[$k] } else { $def[$k] }
        $b.Style = $w.FindResource($(if ($k -eq 'Yes' -or $k -eq 'OK') { 'P' } else { 'G' }))
        $b.Tag = $k
        $b.Add_Click({ param($s) $res.V = [string]$s.Tag; [Windows.Window]::GetWindow($s).Close() }.GetNewClosure())
        if ($k -eq 'Cancel' -or ($k -eq 'No' -and $btn -eq 'YesNo') -or $btn -eq 'OK') { $b.IsCancel = $true }
        $w.FindName('Btns').Children.Add($b) | Out-Null
    }
    $w.FindName('Frame').Add_MouseLeftButtonDown({ param($s) try { [Windows.Window]::GetWindow($s).DragMove() } catch {} })
    try { if ($win -and $win.IsVisible) { $w.Owner = $win; $w.WindowStartupLocation = 'CenterOwner'; $w.Topmost = $false } } catch {}
    [void]$w.ShowDialog()
    $res.V
}
if ($InstallApp) {
    try {
        # Fermer toute instance en cours, y compris celle cachee dans la zone de notification (sans fenetre),
        # sinon TuneManager.ico reste verrouille et la copie echoue
        $others = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match 'TuneManager\.ps1' -and $_.CommandLine -notmatch '-InstallApp' })
        foreach ($o in $others) { Stop-Process -Id $o.ProcessId -Force -ErrorAction SilentlyContinue }
        for ($i = 0; $i -lt 20 -and @($others | Where-Object { Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue }).Count; $i++) { Start-Sleep -Milliseconds 250 }
        New-Item -ItemType Directory $AppDir -Force | Out-Null
        $src = Split-Path $PSCommandPath
        Copy-Item $PSCommandPath (Join-Path $AppDir 'TuneManager.ps1') -Force
        foreach ($f in 'TuneManager.ico', 'README.md') { if (Test-Path (Join-Path $src $f)) { Copy-Item (Join-Path $src $f) $AppDir -Force } }
        $app = Join-Path $AppDir 'TuneManager.ps1'
        New-AppShortcut (Join-Path ([Environment]::GetFolderPath('CommonDesktopDirectory')) 'Tune Manager.lnk') $app
        New-AppShortcut (Join-Path ([Environment]::GetFolderPath('CommonPrograms')) 'Tune Manager.lnk') $app
        # Ancien raccourci personnel (version de developpement) remplace par celui de Program Files
        $old = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Tune Manager.lnk'; if (Test-Path $old) { Remove-Item $old -Force }
        New-Item $AppUninst -Force | Out-Null
        $vals = @{ DisplayName = 'Tune Manager'; DisplayVersion = $AppVer; Publisher = 'Tune Manager'; InstallLocation = $AppDir
            DisplayIcon = (Join-Path $AppDir 'TuneManager.ico'); UninstallString = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$app`" -RemoveApp"
            Comments = 'Installation et gestion de la chaine audio ArtTuneDB (Equalizer APO)' }
        foreach ($k in $vals.Keys) { Set-ItemProperty $AppUninst -Name $k -Value $vals[$k] }
        Set-ItemProperty $AppUninst -Name NoModify -Value 1 -Type DWord; Set-ItemProperty $AppUninst -Name NoRepair -Value 1 -Type DWord
        Set-ItemProperty $AppUninst -Name EstimatedSize -Value ([int]((Get-ChildItem $AppDir -File | Measure-Object Length -Sum).Sum / 1KB)) -Type DWord
        if (Test-StartupTask) { Register-StartupTask $true $app }
        if ((Show-Msg "Tune Manager est installé.`n`nRaccourcis créés sur le bureau et dans le menu Démarrer. Il se désinstalle depuis Paramètres > Applications.`n`nLancer Tune Manager maintenant ?" 'YesNo') -eq 'Yes') {
            Start-Process powershell "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$app`""
        }
    } catch { Show-Msg "Installation impossible : $($_.Exception.Message)" 'OK' 'Error' | Out-Null }
    exit
}
if ($RemoveApp) {
    # -AfterChain : lance par l'application apres "Tout desinstaller, logiciel compris" (chaine deja retiree)
    $r = if ($AfterChain) { 'No' } else { Show-Msg "Désinstaller Tune Manager ?`nTout désinstaller : retire aussi toute la chaîne audio (Equalizer APO, Voicemeeter, VB-CABLE, ReaPlugs, bibliothèque).`nLogiciel seul : retire seulement Tune Manager et garde le son tel quel." 'YesNoCancel' 'Question' @{ Yes = 'Tout désinstaller'; No = 'Logiciel seul' } }
    if ($r -eq 'Cancel') { exit }
    $wipe = $false
    if ($r -eq 'Yes' -or $AfterChain) {
        $wipe = (Show-Msg "Supprimer aussi tes EQ et préférences ?`nIls sont dans C:\Users\Public\TuneManager. Si tu les gardes, tu les retrouveras à la prochaine installation." 'YesNo' 'Question' @{ Yes = 'Tout effacer'; No = 'Les garder' }) -eq 'Yes'
    }
    try {
        Get-Process powershell -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $PID } | ForEach-Object {
            try { if ((Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)").CommandLine -match 'TuneManager\.ps1') { Stop-Process $_ -Force } } catch {} }
        if ($r -eq 'Yes') {
            $log = Join-Path $env:PUBLIC 'tm-uninstall.log'; $L = New-Object Collections.Generic.List[string]
            $lg = { param($m) $L.Add([string]$m); $L | Set-Content $log -Encoding UTF8 }; $pg = { param($p, $m) }
            Uninstall-Silent $lg $pg | Out-Null
        }
        Register-StartupTask $false; Register-UpdateTask $false
        foreach ($l in (Join-Path ([Environment]::GetFolderPath('CommonDesktopDirectory')) 'Tune Manager.lnk'), (Join-Path ([Environment]::GetFolderPath('CommonPrograms')) 'Tune Manager.lnk')) { Remove-Item $l -Force -ErrorAction SilentlyContinue }
        Remove-Item $AppUninst -Recurse -Force -ErrorAction SilentlyContinue
        # Jeton GitHub et donnees propres a Tune Manager dans le profil de chaque utilisateur
        foreach ($u in Get-ChildItem 'C:\Users' -Directory -ErrorAction SilentlyContinue) {
            $d = Join-Path $u.FullName 'AppData\Roaming\TuneManager'
            if (Test-Path $d) { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
        }
        if ($wipe) { Remove-Item (Join-Path $env:PUBLIC 'TuneManager') -Recurse -Force -ErrorAction SilentlyContinue }
        # Le dossier contient ce script en cours d'execution : suppression differee
        Start-Process cmd.exe "/c timeout /t 3 /nobreak >nul & rmdir /s /q `"$AppDir`"" -WindowStyle Hidden
        Show-Msg $(if ($r -eq 'Yes' -or $AfterChain) { "Tune Manager et la chaîne audio ont été désinstallés$(if (-not $wipe) { ' (tes EQ et préférences restent dans C:\Users\Public\TuneManager)' }). Redémarre le PC pour terminer." } else { "Tune Manager a été désinstallé. Ta configuration audio est conservée (tes profils et EQ restent dans C:\Users\Public\TuneManager)." }) | Out-Null
    } catch { Show-Msg "Désinstallation incomplète : $($_.Exception.Message)" 'OK' 'Error' | Out-Null }
    exit
}

# ============================================================================
# Interface graphique (WPF) - direction artistique : noir chaud, lueur rouge,
# grille de points, cartes arrondies, accent rouge-orange.
# ============================================================================
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Tune Manager" Width="1080" Height="764" WindowStartupLocation="CenterScreen"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent" ResizeMode="CanMinimize"
        FontFamily="Segoe UI Variable Display, Segoe UI" Foreground="#F5EFEE">
  <Window.Resources>
    <SolidColorBrush x:Key="Accent" Color="#FF5236"/>
    <SolidColorBrush x:Key="Muted" Color="#9C8D8A"/>
    <SolidColorBrush x:Key="CardBorder" Color="#2E1C19"/>
    <LinearGradientBrush x:Key="CardBg" StartPoint="0,0" EndPoint="1,1">
      <GradientStop Color="#221412" Offset="0"/><GradientStop Color="#150C0B" Offset="1"/>
    </LinearGradientBrush>
    <LinearGradientBrush x:Key="AccentGrad" StartPoint="0,0" EndPoint="1,1">
      <GradientStop Color="#FF6A45" Offset="0"/><GradientStop Color="#E23A22" Offset="1"/>
    </LinearGradientBrush>

    <Style x:Key="Card" TargetType="Border">
      <Setter Property="Background" Value="{StaticResource CardBg}"/>
      <Setter Property="BorderBrush" Value="{StaticResource CardBorder}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CornerRadius" Value="20"/>
      <Setter Property="Padding" Value="26"/>
    </Style>
    <Style x:Key="Kicker" TargetType="TextBlock">
      <Setter Property="Foreground" Value="{StaticResource Accent}"/>
      <Setter Property="FontSize" Value="13"/><Setter Property="FontWeight" Value="SemiBold"/>
    </Style>
    <Style x:Key="H1" TargetType="TextBlock">
      <Setter Property="FontSize" Value="40"/><Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="Margin" Value="0,6,0,4"/>
    </Style>
    <Style x:Key="Sub" TargetType="TextBlock">
      <Setter Property="Foreground" Value="{StaticResource Muted}"/><Setter Property="FontSize" Value="14"/>
      <Setter Property="TextWrapping" Value="Wrap"/>
    </Style>
    <Style x:Key="Label" TargetType="TextBlock">
      <Setter Property="FontSize" Value="13"/><Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Foreground" Value="#D9CCC9"/><Setter Property="Margin" Value="0,0,0,8"/>
    </Style>

    <!-- Bouton principal : pilule rouge lumineuse -->
    <Style x:Key="Primary" TargetType="Button">
      <Setter Property="Foreground" Value="White"/><Setter Property="FontSize" Value="15"/>
      <Setter Property="FontWeight" Value="SemiBold"/><Setter Property="Height" Value="50"/>
      <Setter Property="Cursor" Value="Hand"/><Setter Property="Padding" Value="28,0"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Grid x:Name="b">
              <!-- lueur a part : un Effect sur le Border rendrait le texte du bouton flou -->
              <Border CornerRadius="16" Background="#FF4A2E">
                <Border.Effect><DropShadowEffect Color="#FF4A2E" BlurRadius="28" ShadowDepth="0" Opacity="0.55"/></Border.Effect>
              </Border>
              <Border CornerRadius="16" Background="{StaticResource AccentGrad}" Padding="{TemplateBinding Padding}">
                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Border>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Opacity" Value="0.9"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="b" Property="Opacity" Value="0.75"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="b" Property="Opacity" Value="0.35"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <!-- Bouton secondaire : contour arrondi -->
    <Style x:Key="Ghost" TargetType="Button">
      <Setter Property="Foreground" Value="#F5EFEE"/><Setter Property="FontSize" Value="14"/>
      <Setter Property="FontWeight" Value="SemiBold"/><Setter Property="Height" Value="46"/>
      <Setter Property="Cursor" Value="Hand"/><Setter Property="Padding" Value="22,0"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" CornerRadius="14" Background="#1C1110" BorderBrush="#3A2420" BorderThickness="1" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="#FF5236"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="b" Property="Background" Value="#2A1714"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <!-- Navigation laterale -->
    <Style x:Key="Nav" TargetType="RadioButton">
      <Setter Property="Foreground" Value="#B3A5A2"/><Setter Property="FontSize" Value="14"/>
      <Setter Property="FontWeight" Value="SemiBold"/><Setter Property="Height" Value="50"/>
      <Setter Property="Margin" Value="0,0,0,6"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Border x:Name="b" CornerRadius="14" Background="Transparent" BorderThickness="1" BorderBrush="Transparent" Padding="14,0">
              <Grid>
                <Grid.ColumnDefinitions><ColumnDefinition Width="34"/><ColumnDefinition/></Grid.ColumnDefinitions>
                <Border x:Name="dot" Width="26" Height="26" CornerRadius="8" Background="#2A1A17" HorizontalAlignment="Left">
                  <TextBlock Text="{TemplateBinding Tag}" FontSize="12" FontWeight="Bold" Foreground="#B3A5A2" HorizontalAlignment="Center" VerticalAlignment="Center" x:Name="num"/>
                </Border>
                <ContentPresenter Grid.Column="1" VerticalAlignment="Center"/>
              </Grid>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="#1A100F"/></Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="b" Property="Background" Value="#24130F"/>
                <Setter TargetName="b" Property="BorderBrush" Value="#4A2219"/>
                <Setter TargetName="dot" Property="Background" Value="{StaticResource AccentGrad}"/>
                <Setter TargetName="num" Property="Foreground" Value="White"/>
                <Setter Property="Foreground" Value="White"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <!-- Case a cocher : carre rouge arrondi avec coche -->
    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="#F5EFEE"/><Setter Property="FontSize" Value="14"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <StackPanel Orientation="Horizontal">
              <Border x:Name="box" Width="28" Height="28" CornerRadius="8" Background="#2A1A17" BorderBrush="#4A2E29" BorderThickness="1">
                <Path x:Name="tick" Data="M 7,14 L 12,19 L 21,9" Stroke="White" StrokeThickness="3" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round" Visibility="Collapsed"/>
              </Border>
              <ContentPresenter Margin="12,0,0,0" VerticalAlignment="Center"/>
            </StackPanel>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="box" Property="Background" Value="{StaticResource AccentGrad}"/>
                <Setter TargetName="box" Property="BorderThickness" Value="0"/>
                <Setter TargetName="tick" Property="Visibility" Value="Visible"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <!-- Boutons Reduire / Fermer de la barre de titre (sans le survol bleu de Windows) -->
    <Style x:Key="WinBtn" TargetType="Button">
      <Setter Property="Width" Value="40"/><Setter Property="Height" Value="32"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Foreground" Value="#9C8D8A"/><Setter Property="FontSize" Value="13"/><Setter Property="Focusable" Value="False"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" CornerRadius="10" Background="Transparent">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="#2A1915"/><Setter Property="Foreground" Value="#F5EFEE"/></Trigger>
              <MultiTrigger>
                <MultiTrigger.Conditions><Condition Property="Tag" Value="close"/><Condition Property="IsMouseOver" Value="True"/></MultiTrigger.Conditions>
                <Setter TargetName="b" Property="Background" Value="{StaticResource AccentGrad}"/><Setter Property="Foreground" Value="White"/>
              </MultiTrigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="b" Property="Opacity" Value="0.75"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <!-- Sous-menu de Configuration -->
    <Style x:Key="SubNav" TargetType="RadioButton">
      <Setter Property="Foreground" Value="#9C8D8A"/><Setter Property="FontSize" Value="13"/>
      <Setter Property="FontWeight" Value="SemiBold"/><Setter Property="Height" Value="36"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Grid Background="Transparent">
              <Border x:Name="bar" Width="2" HorizontalAlignment="Left" Background="#3A2420" Margin="0,4"/>
              <TextBlock x:Name="t" Text="{TemplateBinding Content}" Margin="18,0,0,0" VerticalAlignment="Center" Foreground="{TemplateBinding Foreground}"/>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="t" Property="Foreground" Value="#E6D9D6"/></Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="t" Property="Foreground" Value="#FFFFFF"/>
                <Setter TargetName="bar" Property="Background" Value="#FF5236"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <!-- Liste deroulante sombre et arrondie -->
    <Style TargetType="ComboBoxItem">
      <Setter Property="Foreground" Value="#F5EFEE"/><Setter Property="FontSize" Value="14"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBoxItem">
            <Border x:Name="b" CornerRadius="10" Padding="12,9" Margin="4,1" Background="Transparent">
              <ContentPresenter/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsHighlighted" Value="True"><Setter TargetName="b" Property="Background" Value="#3A1D17"/></Trigger>
              <Trigger Property="IsSelected" Value="True"><Setter TargetName="b" Property="Background" Value="#4A2219"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ComboBox">
      <Setter Property="Foreground" Value="#F5EFEE"/><Setter Property="FontSize" Value="14"/><Setter Property="Height" Value="46"/>
      <Setter Property="Margin" Value="0,0,0,18"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBox">
            <Grid>
              <ToggleButton x:Name="tg" Focusable="False" IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}">
                <ToggleButton.Template>
                  <ControlTemplate TargetType="ToggleButton">
                    <Border x:Name="bd" CornerRadius="14" Background="#1C1110" BorderBrush="#3A2420" BorderThickness="1">
                      <Path HorizontalAlignment="Right" Margin="0,0,18,0" VerticalAlignment="Center" Data="M 0,0 L 5,5 L 10,0" Stroke="#FF5236" StrokeThickness="2"/>
                    </Border>
                    <ControlTemplate.Triggers>
                      <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="BorderBrush" Value="#FF5236"/></Trigger>
                    </ControlTemplate.Triggers>
                  </ControlTemplate>
                </ToggleButton.Template>
              </ToggleButton>
              <ContentPresenter x:Name="cp" IsHitTestVisible="False" Margin="16,0,44,0" VerticalAlignment="Center"
                                Content="{TemplateBinding SelectionBoxItem}"/>
              <TextBox x:Name="PART_EditableTextBox" Visibility="Collapsed" Margin="14,0,44,0" VerticalAlignment="Center"
                       Background="Transparent" BorderThickness="0" Foreground="#F5EFEE" CaretBrush="#FF5236" FontSize="14"
                       IsReadOnly="{TemplateBinding IsReadOnly}"/>
              <Popup IsOpen="{TemplateBinding IsDropDownOpen}" Placement="Bottom" AllowsTransparency="True" Focusable="False" PopupAnimation="Fade">
                <Border CornerRadius="14" Background="#1C1110" BorderBrush="#3A2420" BorderThickness="1" Padding="0,6" Margin="0,6,0,0"
                        MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}" MaxHeight="320">
                  <ScrollViewer VerticalScrollBarVisibility="Auto"><ItemsPresenter/></ScrollViewer>
                </Border>
              </Popup>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsEditable" Value="True">
                <Setter TargetName="PART_EditableTextBox" Property="Visibility" Value="Visible"/>
                <Setter TargetName="cp" Property="Visibility" Value="Collapsed"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Input" TargetType="TextBox">
      <Setter Property="Foreground" Value="#F5EFEE"/><Setter Property="FontSize" Value="14"/><Setter Property="Height" Value="46"/>
      <Setter Property="CaretBrush" Value="#FF5236"/><Setter Property="VerticalContentAlignment" Value="Center"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="TextBox">
            <Border x:Name="bd" CornerRadius="14" Background="#1C1110" BorderBrush="#3A2420" BorderThickness="1" Padding="14,0">
              <Grid>
                <TextBlock x:Name="ph" Text="{TemplateBinding Tag}" Foreground="#6E5E5A" VerticalAlignment="Center" IsHitTestVisible="False" Visibility="Collapsed"/>
                <ScrollViewer x:Name="PART_ContentHost" VerticalAlignment="Center"/>
              </Grid>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="Text" Value=""><Setter TargetName="ph" Property="Visibility" Value="Visible"/></Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="bd" Property="BorderBrush" Value="#FF5236"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Log" TargetType="TextBox">
      <Setter Property="Background" Value="#120A09"/><Setter Property="Foreground" Value="#D9CCC9"/>
      <Setter Property="BorderThickness" Value="0"/><Setter Property="FontFamily" Value="Cascadia Mono, Consolas"/>
      <Setter Property="FontSize" Value="12"/><Setter Property="IsReadOnly" Value="True"/><Setter Property="TextWrapping" Value="Wrap"/>
      <Setter Property="VerticalScrollBarVisibility" Value="Auto"/><Setter Property="Padding" Value="14"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="TextBox">
            <Border CornerRadius="14" Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}">
              <ScrollViewer x:Name="PART_ContentHost"/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ScrollBar">
      <Setter Property="Width" Value="8"/><Setter Property="MinWidth" Value="8"/><Setter Property="Background" Value="Transparent"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollBar">
            <Track x:Name="PART_Track" IsDirectionReversed="True">
              <Track.Thumb>
                <Thumb>
                  <Thumb.Template>
                    <ControlTemplate TargetType="Thumb"><Border CornerRadius="4" Background="#4A2A24" Margin="1,2"/></ControlTemplate>
                  </Thumb.Template>
                </Thumb>
              </Track.Thumb>
            </Track>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <!-- Grille de points en fond -->
    <DrawingBrush x:Key="Dots" TileMode="Tile" Viewport="0,0,44,44" ViewportUnits="Absolute" Viewbox="0,0,44,44" ViewboxUnits="Absolute" Stretch="None">
      <DrawingBrush.Drawing>
        <GeometryDrawing Brush="#40FF5236">
          <GeometryDrawing.Geometry><EllipseGeometry Center="2,2" RadiusX="1.1" RadiusY="1.1"/></GeometryDrawing.Geometry>
        </GeometryDrawing>
      </DrawingBrush.Drawing>
    </DrawingBrush>
  </Window.Resources>

  <Border CornerRadius="24" BorderBrush="#2E1C19" BorderThickness="1" ClipToBounds="True">
    <Border.Background>
      <RadialGradientBrush Center="0.55,1.05" GradientOrigin="0.55,1.05" RadiusX="0.75" RadiusY="0.9">
        <GradientStop Color="#3A0F08" Offset="0"/><GradientStop Color="#120807" Offset="0.55"/><GradientStop Color="#0A0606" Offset="1"/>
      </RadialGradientBrush>
    </Border.Background>
    <Grid>
      <Rectangle Fill="{StaticResource Dots}" Opacity="0.45" IsHitTestVisible="False"/>
      <!-- Aura qui suit la souris (deplacee par le code, sous le contenu) -->
      <Canvas x:Name="AuraLayer" IsHitTestVisible="False">
        <Ellipse x:Name="Aura" Width="520" Height="520" Opacity="0">
          <Ellipse.Fill>
            <RadialGradientBrush>
              <GradientStop Color="#5CFF5236" Offset="0"/><GradientStop Color="#26FF4A2E" Offset="0.45"/><GradientStop Color="#00FF4A2E" Offset="1"/>
            </RadialGradientBrush>
          </Ellipse.Fill>
          <Ellipse.RenderTransform><TranslateTransform/></Ellipse.RenderTransform>
        </Ellipse>
      </Canvas>
      <Grid>
        <Grid.ColumnDefinitions><ColumnDefinition Width="260"/><ColumnDefinition/></Grid.ColumnDefinitions>
        <Grid.RowDefinitions><RowDefinition Height="56"/><RowDefinition/><RowDefinition Height="Auto"/></Grid.RowDefinitions>

        <!-- Barre d'etat -->
        <Border Grid.Row="2" Grid.ColumnSpan="2" Background="#0E0807" BorderBrush="#2A1915" BorderThickness="0,1,0,0" CornerRadius="0,0,22,22" Padding="26,0">
          <Grid Height="44">
            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
              <Ellipse x:Name="SbDot" Width="8" Height="8" Fill="#FF5236" Margin="0,0,10,0">
                <Ellipse.Effect><DropShadowEffect Color="#FF5236" BlurRadius="10" ShadowDepth="0" Opacity="0.9"/></Ellipse.Effect>
              </Ellipse>
              <TextBlock Text="PROFIL" Foreground="#7E6E6A" FontSize="11" FontWeight="Bold" VerticalAlignment="Center" Margin="0,0,8,0"/>
              <TextBlock x:Name="SbProfile" Text="&#x2014;" Foreground="#F5EFEE" FontSize="13" FontWeight="SemiBold" VerticalAlignment="Center" MaxWidth="300" TextTrimming="CharacterEllipsis"/>
              <Border Width="1" Height="18" Background="#2A1915" Margin="18,0"/>
              <TextBlock Text="SORTIE" Foreground="#7E6E6A" FontSize="11" FontWeight="Bold" VerticalAlignment="Center" Margin="0,0,8,0"/>
              <TextBlock x:Name="SbOut" Text="&#x2014;" Foreground="#D9CCC9" FontSize="13" VerticalAlignment="Center" MaxWidth="260" TextTrimming="CharacterEllipsis"/>
            </StackPanel>
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
              <Border x:Name="SbChain" CornerRadius="9" Padding="10,4" Background="#231513" BorderBrush="#3A2420" BorderThickness="1" Margin="0,0,8,0">
                <TextBlock x:Name="SbChainT" Text="Art Tune +" FontSize="12" FontWeight="SemiBold" Foreground="#D9CCC9"/>
              </Border>
              <Border x:Name="SbVm" CornerRadius="9" Padding="10,4" Background="#231513" BorderBrush="#3A2420" BorderThickness="1">
                <TextBlock x:Name="SbVmT" Text="Voicemeeter" FontSize="12" FontWeight="SemiBold" Foreground="#D9CCC9"/>
              </Border>
            </StackPanel>
          </Grid>
        </Border>

        <!-- Barre de titre -->
        <Grid x:Name="TitleBar" Grid.ColumnSpan="2" Background="Transparent">
          <StackPanel Orientation="Horizontal" VerticalAlignment="Center" Margin="26,0,0,0">
            <Image x:Name="TitleLogo" Width="22" Height="22" RenderOptions.BitmapScalingMode="HighQuality" VerticalAlignment="Center"/>
            <TextBlock Text="TUNE MANAGER" Margin="10,0,0,0" VerticalAlignment="Center" FontSize="12" FontWeight="Bold" Foreground="#D9CCC9"/>
          </StackPanel>
          <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,0,16,0">
            <Button x:Name="BtnMin" Style="{StaticResource WinBtn}" Content="&#x2014;"/>
            <Button x:Name="BtnClose" Style="{StaticResource WinBtn}" Tag="close" Content="&#x2715;" Margin="6,0,0,0"/>
          </StackPanel>
        </Grid>

        <!-- Navigation -->
        <StackPanel Grid.Row="1" Margin="20,8,12,20">
          <RadioButton x:Name="Nav3" Style="{StaticResource Nav}" Tag="&#x266A;" Content="Profils" GroupName="nav"/>
          <RadioButton x:Name="NavCfg" Style="{StaticResource Nav}" Tag="&#x2699;" Content="Configuration" GroupName="nav"/>
          <StackPanel x:Name="CfgSub" Visibility="Collapsed" Margin="26,0,0,6">
            <RadioButton x:Name="Nav0" Style="{StaticResource SubNav}" Content="Installation" GroupName="sub"/>
            <RadioButton x:Name="Nav1" Style="{StaticResource SubNav}" Content="Diagnostic" GroupName="sub"/>
            <RadioButton x:Name="Nav2" Style="{StaticResource SubNav}" Content="Voicemeeter" GroupName="sub"/>
          </StackPanel>
          <RadioButton x:Name="Nav4" Style="{StaticResource Nav}" Tag="&#x2261;" Content="Param&#xE8;tres" GroupName="nav"/>
          <Border Style="{StaticResource Card}" Margin="0,24,0,0" Padding="18">
            <StackPanel>
              <TextBlock Text="&#x2014;  BIBLIOTH&#xC8;QUE" Style="{StaticResource Kicker}" FontSize="11"/>
              <TextBlock x:Name="SideVer" Text="..." FontSize="18" FontWeight="Bold" Margin="0,8,0,2"/>
              <TextBlock x:Name="SideVerSub" Text="" Style="{StaticResource Sub}" FontSize="12"/>
            </StackPanel>
          </Border>
        </StackPanel>

        <!-- Pages -->
        <Grid Grid.Row="1" Grid.Column="1" Margin="12,8,34,28">

          <!-- 1. Installation -->
          <Grid x:Name="Page0">
            <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
            <StackPanel Margin="0,0,0,18">
              <TextBlock Text="&#x2014;  CONFIGURATION" Style="{StaticResource Kicker}"/>
              <TextBlock x:Name="InstTitle" Text="Installation" Style="{StaticResource H1}"/>
              <TextBlock x:Name="InstSub" Text="Installe toute la cha&#xEE;ne audio ArtIsWar en silence : VB-CABLE, Voicemeeter, Equalizer APO, moteur ATK, biblioth&#xE8;que et r&#xE9;glages." Style="{StaticResource Sub}"/>
            </StackPanel>
            <!-- Rangee d'etapes -->
            <Border x:Name="StepCard" Grid.Row="1" Style="{StaticResource Card}" Padding="22,18" Margin="0,0,0,14">
              <UniformGrid x:Name="StepDots" Rows="1"/>
            </Border>
            <!-- Chaine deja installee : etat seul, le suivi d'installation n'apparait que pendant une installation -->
            <Border x:Name="InstDone" Grid.Row="1" Grid.RowSpan="3" Style="{StaticResource Card}" Padding="26,24" VerticalAlignment="Top" Visibility="Collapsed">
              <Grid>
                <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition/></Grid.ColumnDefinitions>
                <Border Width="52" Height="52" CornerRadius="16" Background="{StaticResource AccentGrad}" VerticalAlignment="Top" Margin="0,0,20,0">
                  <Path Data="M 15,27 L 23,35 L 38,18" Stroke="White" StrokeThickness="4" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round"/>
                </Border>
                <StackPanel Grid.Column="1">
                  <TextBlock Text="Cha&#xEE;ne audio install&#xE9;e" FontSize="20" FontWeight="Bold"/>
                  <TextBlock x:Name="InstDoneSub" Style="{StaticResource Sub}" Margin="0,6,0,0" Text="VB-CABLE, Voicemeeter, Equalizer APO, moteur ATK et biblioth&#xE8;que sont en place."/>
                  <TextBlock Style="{StaticResource Sub}" FontSize="13" Margin="0,14,0,0" Text="En cas de souci de son, lance d'abord le Diagnostic. R&#xE9;parer r&#xE9;installe toute la cha&#xEE;ne en gardant tes profils."/>
                </StackPanel>
              </Grid>
            </Border>
            <!-- Carte en cours -->
            <Border x:Name="ProgCard" Grid.Row="2" Style="{StaticResource Card}" Padding="22" Margin="0,0,0,14">
              <StackPanel>
                <Grid>
                  <TextBlock x:Name="CurTask" Text="Pr&#xEA;t &#xE0; installer" FontSize="17" FontWeight="SemiBold"/>
                  <TextBlock x:Name="CurPct" Text="0 %" HorizontalAlignment="Right" FontSize="17" FontWeight="Bold" Foreground="{StaticResource Accent}"/>
                </Grid>
                <Border Height="10" CornerRadius="5" Background="#2A1A17" Margin="0,14,0,0">
                  <Grid HorizontalAlignment="Stretch" x:Name="BarHost">
                    <Border x:Name="BarFill" HorizontalAlignment="Left" Width="0" CornerRadius="5" Background="{StaticResource AccentGrad}">
                      <Border.Effect><DropShadowEffect Color="#FF4A2E" BlurRadius="14" ShadowDepth="0" Opacity="0.7"/></Border.Effect>
                    </Border>
                    <!-- reflet qui parcourt la barre pendant l'installation -->
                    <Canvas x:Name="BarShineHost" HorizontalAlignment="Left" Width="0" ClipToBounds="True" IsHitTestVisible="False">
                      <Rectangle x:Name="BarShine" Width="140" Height="10" Visibility="Collapsed">
                        <Rectangle.Fill>
                          <LinearGradientBrush StartPoint="0,0" EndPoint="1,0">
                            <GradientStop Color="#00FFFFFF" Offset="0"/><GradientStop Color="#80FFE2D6" Offset="0.5"/><GradientStop Color="#00FFFFFF" Offset="1"/>
                          </LinearGradientBrush>
                        </Rectangle.Fill>
                        <Rectangle.RenderTransform><TranslateTransform/></Rectangle.RenderTransform>
                      </Rectangle>
                    </Canvas>
                  </Grid>
                </Border>
                <Border x:Name="WarnBanner" Visibility="Collapsed" CornerRadius="10" Background="#3A1410" BorderBrush="#7A2618" BorderThickness="1" Padding="12,8" Margin="0,14,0,0">
                  <TextBlock Text="Ne ferme pas Tune Manager. Le son du PC peut couper quelques instants, c'est normal." Foreground="#FF9A80" FontSize="12.5" TextWrapping="Wrap"/>
                </Border>
              </StackPanel>
            </Border>
            <TextBox x:Name="InstLog" Grid.Row="3" Style="{StaticResource Log}" Margin="0,0,0,14"/>
            <WrapPanel Grid.Row="4">
              <Button x:Name="BtnInstall" Style="{StaticResource Primary}" Content="Installer" Margin="0,0,12,0"/>
              <Button x:Name="BtnUninstall" Style="{StaticResource Ghost}" Content="Tout d&#xE9;sinstaller" Margin="0,0,12,0"/>
              <Button x:Name="BtnOfficial" Style="{StaticResource Ghost}" Content="Script officiel (avanc&#xE9;)"/>
            </WrapPanel>
          </Grid>
          <!-- 2. Windows -->
          <Grid x:Name="Page1" Visibility="Collapsed">
            <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
            <StackPanel Margin="0,0,0,20">
              <TextBlock Text="&#x2014;  CONFIGURATION" Style="{StaticResource Kicker}"/>
              <TextBlock Text="Diagnostic" Style="{StaticResource H1}"/>
              <TextBlock x:Name="DiagSummary" Text="V&#xE9;rification de Windows et d'Equalizer APO." Style="{StaticResource Sub}"/>
            </StackPanel>
            <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto"><StackPanel x:Name="DiagList"/></ScrollViewer>
            <WrapPanel Grid.Row="2" Margin="0,18,0,0">
              <Button x:Name="BtnDiag" Style="{StaticResource Primary}" Content="V&#xE9;rifier" Margin="0,0,12,0"/>
              <Button x:Name="BtnDisable" Style="{StaticResource Ghost}" Content="D&#xE9;sactiver les p&#xE9;riph&#xE9;riques inutiles" Margin="0,0,12,0"/>
              <Button x:Name="BtnDevSel" Style="{StaticResource Ghost}" Content="Device Selector" Margin="0,0,12,0"/>
              <Button x:Name="BtnSound" Style="{StaticResource Ghost}" Content="Param&#xE8;tres Son"/>
            </WrapPanel>
          </Grid>

          <!-- 3. Voicemeeter -->
          <Grid x:Name="Page2" Visibility="Collapsed">
            <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition/></Grid.RowDefinitions>
            <StackPanel Margin="0,0,0,20">
              <TextBlock Text="&#x2014;  CONFIGURATION" Style="{StaticResource Kicker}"/>
              <TextBlock Text="Voicemeeter" Style="{StaticResource H1}"/>
              <TextBlock Text="Voicemeeter re&#xE7;oit le son trait&#xE9; (Art Tune Unified Output) et l'envoie &#xE0; ton casque (sortie A1)." Style="{StaticResource Sub}"/>
            </StackPanel>
            <Border Grid.Row="1" Style="{StaticResource Card}" Margin="0,0,0,18">
              <StackPanel>
                <TextBlock Text="O&#xF9; entends-tu ton son ?" Style="{StaticResource Label}"/>
                <ComboBox x:Name="CbOut"/>
                <WrapPanel>
                  <Button x:Name="BtnVm" Style="{StaticResource Primary}" Content="Configurer Voicemeeter" Margin="0,0,12,0"/>
                  <Button x:Name="BtnVmLoad" Style="{StaticResource Ghost}" Content="Rafra&#xEE;chir la liste"/>
                </WrapPanel>
              </StackPanel>
            </Border>
            <TextBox x:Name="VmLog" Grid.Row="2" Style="{StaticResource Log}"/>
          </Grid>

          <!-- 4. Preset -->
          <Grid x:Name="Page3" Visibility="Collapsed">
            <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition/></Grid.RowDefinitions>
            <StackPanel Margin="0,0,0,18">
              <TextBlock Text="&#x2014;  ACCUEIL" Style="{StaticResource Kicker}"/>
              <TextBlock Text="Profils audio" Style="{StaticResource H1}"/>
              <TextBlock x:Name="PresetStatus" Text="Un clic sur un profil l'applique en direct sur Art Tune +." Style="{StaticResource Sub}"/>
            </StackPanel>
            <!-- Profil actif -->
            <!-- Lueur sur un calque separe : un Effect pose sur la carte rasterise tout son contenu (texte flou) -->
            <Border Grid.Row="1" CornerRadius="20" Background="#160D0C" Margin="0,0,0,22" IsHitTestVisible="False">
              <Border.Effect><DropShadowEffect Color="#FF4A2E" BlurRadius="40" ShadowDepth="0" Opacity="0.18"/></Border.Effect>
            </Border>
            <Border Grid.Row="1" CornerRadius="20" Padding="26,22" BorderThickness="1" BorderBrush="#5A2A20" Margin="0,0,0,22">
              <Border.Background>
                <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                  <GradientStop Color="#2A1411" Offset="0"/><GradientStop Color="#160D0C" Offset="1"/>
                </LinearGradientBrush>
              </Border.Background>
              <Grid>
                <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                <StackPanel>
                  <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                    <Ellipse Width="8" Height="8" Fill="#FF5236" VerticalAlignment="Center" Margin="0,0,8,0">
                      <Ellipse.Effect><DropShadowEffect Color="#FF5236" BlurRadius="10" ShadowDepth="0" Opacity="0.9"/></Ellipse.Effect>
                    </Ellipse>
                    <TextBlock Text="PROFIL ACTIF" Style="{StaticResource Kicker}" FontSize="12"/>
                  </StackPanel>
                  <TextBlock x:Name="ActName" Text="Aucun profil" FontSize="26" FontWeight="Bold" TextTrimming="CharacterEllipsis"/>
                  <TextBlock x:Name="ActSub" Text="" Style="{StaticResource Sub}" Margin="0,2,0,12"/>
                  <WrapPanel x:Name="ActChips"/>
                  <Grid x:Name="ActBoostRow" Margin="0,6,24,0">
                    <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition/><ColumnDefinition Width="64"/></Grid.ColumnDefinitions>
                    <TextBlock Text="Boost" Style="{StaticResource Label}" Margin="0,0,14,0" VerticalAlignment="Center"/>
                    <Slider x:Name="ActBoost" Grid.Column="1" Minimum="0" Maximum="12" IsSnapToTickEnabled="True" TickFrequency="1" Foreground="#FF5236" VerticalAlignment="Center"/>
                    <TextBlock x:Name="ActBoostVal" Grid.Column="2" Text="off" HorizontalAlignment="Right" VerticalAlignment="Center" Foreground="{StaticResource Accent}" FontWeight="Bold"/>
                  </Grid>
                </StackPanel>
                <StackPanel Grid.Column="1" VerticalAlignment="Center">
                  <Button x:Name="BtnGameSettings" Style="{StaticResource Ghost}" Content="R&#xE9;glages en jeu" Width="150" Margin="0,0,0,10"/>
                  <Button x:Name="BtnEditProfile" Style="{StaticResource Ghost}" Content="Modifier" Width="150" Margin="0,0,0,10"/>
                  <Button x:Name="BtnDelProfile" Style="{StaticResource Ghost}" Content="Supprimer" Width="150"/>
                </StackPanel>
              </Grid>
            </Border>
            <Grid Grid.Row="2" Margin="0,0,0,12">
              <TextBlock Text="Mes profils" FontSize="18" FontWeight="Bold" VerticalAlignment="Center"/>
              <Button x:Name="BtnNewProfile" Style="{StaticResource Primary}" Content="+  Nouveau profil" Height="42" HorizontalAlignment="Right"/>
            </Grid>
            <ScrollViewer Grid.Row="3" VerticalScrollBarVisibility="Auto" Margin="0,0,-12,0">
              <WrapPanel x:Name="ProfList" Margin="0,0,0,8"/>
            </ScrollViewer>

            <!-- Reglages a faire dans le jeu -->
            <Grid x:Name="GameOverlay" Grid.RowSpan="4" Visibility="Collapsed" Background="#E00C0706" Margin="-20">
              <Border Style="{StaticResource Card}" Background="#150C0B" Width="660" Margin="0,10" VerticalAlignment="Center" Padding="28,20">
                <Border.Effect><DropShadowEffect Color="#000000" BlurRadius="50" ShadowDepth="0" Opacity="0.7"/></Border.Effect>
                <StackPanel>
                  <TextBlock Text="R&#xC9;GLAGES EN JEU  &#xB7;  OBLIGATOIRES POUR QUE LA CHA&#xCE;NE FONCTIONNE" Style="{StaticResource Kicker}" FontSize="12"/>
                  <TextBlock x:Name="GsTitle" Text="Call of Duty" FontSize="26" FontWeight="Bold" Margin="0,6,0,4"/>
                  <TextBlock x:Name="GsSub" Style="{StaticResource Sub}" Margin="0,0,0,12"/>
                  <StackPanel x:Name="GsList"/>
                  <TextBlock Style="{StaticResource Sub}" FontSize="12" Margin="0,14,0,0" Text="Source : COD_SETTINGS.md de la biblioth&#xE8;que ArtTuneDB (ArtIsWar)."/>
                  <Button x:Name="GsClose" Style="{StaticResource Primary}" Content="Compris" Height="42" HorizontalAlignment="Right" Margin="0,10,0,0"/>
                </StackPanel>
              </Border>
            </Grid>

            <!-- Assistant Nouveau profil -->
            <Grid x:Name="Wizard" Grid.RowSpan="4" Visibility="Collapsed" Background="#E00C0706" Margin="-20">
              <Border Style="{StaticResource Card}" Background="#150C0B" Width="680" Margin="0,24" VerticalAlignment="Stretch" Padding="30,26">
                <Border.Effect><DropShadowEffect Color="#000000" BlurRadius="50" ShadowDepth="0" Opacity="0.7"/></Border.Effect>
                <Grid>
                  <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
                  <TextBlock x:Name="WzKicker" Text="NOUVEAU PROFIL  &#xB7;  &#xC9;TAPE 1 / 3" Style="{StaticResource Kicker}" FontSize="12"/>
                  <!-- progression -->
                  <Grid Grid.Row="1" Margin="0,10,0,18">
                    <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="8"/><ColumnDefinition/><ColumnDefinition Width="8"/><ColumnDefinition/></Grid.ColumnDefinitions>
                    <Border x:Name="WzBar1" Height="4" CornerRadius="2" Background="#FF5236"/>
                    <Border x:Name="WzBar2" Grid.Column="2" Height="4" CornerRadius="2" Background="#3A2420"/>
                    <Border x:Name="WzBar3" Grid.Column="4" Height="4" CornerRadius="2" Background="#3A2420"/>
                  </Grid>
                  <Grid Grid.Row="2">
                    <!-- 1. Casque -->
                    <Grid x:Name="WzStep1">
                      <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition/></Grid.RowDefinitions>
                      <StackPanel Margin="0,0,0,14">
                        <TextBlock Text="Ton casque" FontSize="24" FontWeight="Bold"/>
                        <TextBlock Text="Choisis un EQ install&#xE9;, ou cherche ton mod&#xE8;le : l'EQ est cr&#xE9;&#xE9; depuis squig.link sur la target ArtIsWar." Style="{StaticResource Sub}"/>
                      </StackPanel>
                      <TextBox x:Name="WzSearch" Grid.Row="1" Style="{StaticResource Input}" Tag="Rechercher un casque ou des &#xE9;couteurs (ex. Kiwi Ears Astral)" Margin="0,0,0,12"/>
                      <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto"><StackPanel x:Name="WzPhones"/></ScrollViewer>
                    </Grid>
                    <!-- 2. Jeu et son -->
                    <ScrollViewer x:Name="WzStep2" Visibility="Collapsed" VerticalScrollBarVisibility="Auto">
                      <StackPanel>
                        <TextBlock Text="Jeu et son" FontSize="24" FontWeight="Bold" Margin="0,0,0,14"/>
                        <TextBlock x:Name="WzGameLbl" Text="Jeu / version" Style="{StaticResource Label}"/>
                        <WrapPanel x:Name="WzGames" Margin="0,0,0,12"/>
                        <TextBlock Text="Style de preset" Style="{StaticResource Label}"/>
                        <UniformGrid x:Name="WzFams" Columns="2" Margin="0,0,0,12"/>
                        <TextBlock Text="Niveau de ta propre arme" Style="{StaticResource Label}"/>
                        <WrapPanel x:Name="WzGuns" Margin="0,0,0,12"/>
                        <TextBlock Text="HRIR (spatialisation)" Style="{StaticResource Label}"/>
                        <WrapPanel x:Name="WzHrirs"/>
                      </StackPanel>
                    </ScrollViewer>
                    <!-- 3. Finitions -->
                    <StackPanel x:Name="WzStep3" Visibility="Collapsed">
                      <TextBlock Text="Finitions" FontSize="24" FontWeight="Bold" Margin="0,0,0,14"/>
                      <TextBlock Text="Nom du profil" Style="{StaticResource Label}"/>
                      <TextBox x:Name="WzName" Style="{StaticResource Input}" Margin="0,0,0,18"/>
                      <Grid Margin="0,0,0,8">
                        <TextBlock Text="Boost de sortie" Style="{StaticResource Label}"/>
                        <TextBlock x:Name="WzBoostVal" Text="off" HorizontalAlignment="Right" Foreground="{StaticResource Accent}" FontWeight="Bold"/>
                      </Grid>
                      <Slider x:Name="WzBoost" Minimum="0" Maximum="12" IsSnapToTickEnabled="True" TickFrequency="1" Foreground="#FF5236" Margin="0,0,0,22"/>
                      <Border CornerRadius="14" Background="#1C1110" BorderBrush="#3A2420" BorderThickness="1" Padding="18,14">
                        <StackPanel>
                          <TextBlock Text="R&#xC9;SUM&#xC9;" Style="{StaticResource Kicker}" FontSize="11" Foreground="{StaticResource Muted}"/>
                          <TextBlock x:Name="WzSummary" Margin="0,6,0,0" TextWrapping="Wrap" Foreground="#E6D9D6" FontSize="14" LineHeight="22"/>
                        </StackPanel>
                      </Border>
                    </StackPanel>
                  </Grid>
                  <Grid Grid.Row="3" Margin="0,18,0,0">
                    <TextBlock x:Name="WzMsg" VerticalAlignment="Center" Foreground="#FF7A5C" FontSize="13" TextWrapping="Wrap" Margin="0,0,330,0"/>
                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                      <Button x:Name="WzCancel" Style="{StaticResource Ghost}" Content="Annuler" Margin="0,0,10,0"/>
                      <Button x:Name="WzBack" Style="{StaticResource Ghost}" Content="Retour" Margin="0,0,10,0"/>
                      <Button x:Name="WzNext" Style="{StaticResource Primary}" Content="Suivant" Height="46"/>
                    </StackPanel>
                  </Grid>
                </Grid>
              </Border>
            </Grid>
          </Grid>

          <!-- 5. Mises a jour -->
          <Grid x:Name="Page4" Visibility="Collapsed">
            <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition/></Grid.RowDefinitions>
            <StackPanel Margin="0,0,0,22">
              <TextBlock Text="&#x2014;  PARAM&#xC8;TRES" Style="{StaticResource Kicker}"/>
              <TextBlock Text="Param&#xE8;tres" Style="{StaticResource H1}"/>
              <TextBlock x:Name="UpSummary" Text="" Style="{StaticResource Sub}"/>
            </StackPanel>
            <!-- install&#xE9;e vs publi&#xE9;e -->
            <Grid Grid.Row="1" Margin="0,0,0,22">
              <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="90"/><ColumnDefinition/></Grid.ColumnDefinitions>
              <Border Style="{StaticResource Card}" Padding="22">
                <StackPanel>
                  <TextBlock Text="INSTALL&#xC9;E" Style="{StaticResource Kicker}" Foreground="{StaticResource Muted}" FontSize="11"/>
                  <TextBlock x:Name="VerLocal" Text="..." FontSize="28" FontWeight="Bold" Margin="0,6,0,0"/>
                </StackPanel>
              </Border>
              <Border Grid.Column="1" Width="58" Height="58" CornerRadius="29" BorderBrush="#FF5236" BorderThickness="1.5" Background="#140B0A">
                <Border.Effect><DropShadowEffect Color="#FF4A2E" BlurRadius="18" ShadowDepth="0" Opacity="0.6"/></Border.Effect>
                <TextBlock Text="vs" FontFamily="Georgia" FontStyle="Italic" FontSize="20" HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Border>
              <Border x:Name="RemoteCard" Grid.Column="2" Style="{StaticResource Card}" Padding="22" BorderBrush="#FF5236">
                <Border.Effect><DropShadowEffect Color="#FF4A2E" BlurRadius="30" ShadowDepth="0" Opacity="0.35"/></Border.Effect>
                <StackPanel>
                  <TextBlock Text="PUBLI&#xC9;E" Style="{StaticResource Kicker}" FontSize="11"/>
                  <TextBlock x:Name="VerRemote" Text="..." FontSize="28" FontWeight="Bold" Foreground="{StaticResource Accent}" Margin="0,6,0,0"/>
                </StackPanel>
              </Border>
            </Grid>
            <StackPanel Grid.Row="2" Margin="0,0,0,18">
              <WrapPanel Margin="0,0,0,16">
                <Button x:Name="BtnUpdate" Style="{StaticResource Primary}" Content="Mettre &#xE0; jour" Margin="0,0,12,0"/>
                <Button x:Name="BtnCheckUp" Style="{StaticResource Ghost}" Content="V&#xE9;rifier maintenant"/>
              </WrapPanel>
              <CheckBox x:Name="ChkAuto" Content="V&#xE9;rifier les mises &#xE0; jour de la biblioth&#xE8;que &#xE0; chaque d&#xE9;marrage de Windows" Margin="0,0,0,10"/>
              <CheckBox x:Name="ChkStartup" Content="Lancer Tune Manager avec Windows, dans la zone de notification" Margin="0,0,0,10"/>
              <CheckBox x:Name="ChkCloseTray" Content="La croix r&#xE9;duit Tune Manager dans la zone de notification (au lieu de le quitter)"/>
              <Border CornerRadius="16" Background="#1A0F0E" BorderBrush="#2E1C19" BorderThickness="1" Padding="18,14" Margin="0,16,0,0">
                <Grid>
                  <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                  <StackPanel>
                    <TextBlock Text="MISES &#xC0; JOUR DE TUNE MANAGER  &#xB7;  GITHUB" Style="{StaticResource Kicker}" FontSize="11"/>
                    <TextBlock x:Name="AppVerText" FontSize="14" FontWeight="SemiBold" Margin="0,6,0,8"/>
                    <Grid>
                      <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                      <PasswordBox x:Name="GhToken" Height="40" Background="#1C1110" Foreground="#F5EFEE" BorderBrush="#3A2420" CaretBrush="#FF5236" Padding="10,0" VerticalContentAlignment="Center" ToolTip="Jeton GitHub (lecture seule sur le d&#xE9;p&#xF4;t)">
                        <PasswordBox.Template>
                          <ControlTemplate TargetType="PasswordBox">
                            <Border CornerRadius="12" Background="#1C1110" BorderBrush="#3A2420" BorderThickness="1" Padding="12,0"><ScrollViewer x:Name="PART_ContentHost" VerticalAlignment="Center"/></Border>
                          </ControlTemplate>
                        </PasswordBox.Template>
                      </PasswordBox>
                      <Button x:Name="BtnGhSave" Grid.Column="1" Style="{StaticResource Ghost}" Content="Enregistrer" Height="40" Margin="10,0,0,0"/>
                    </Grid>
                    <TextBlock x:Name="GhTokenState" Style="{StaticResource Sub}" FontSize="12" Margin="0,6,0,0"/>
                  </StackPanel>
                  <Button x:Name="BtnAppUpd" Grid.Column="1" Style="{StaticResource Ghost}" Content="V&#xE9;rifier" VerticalAlignment="Top" Margin="16,0,0,0"/>
                </Grid>
              </Border>
            </StackPanel>
            <TextBox x:Name="UpLog" Grid.Row="3" Style="{StaticResource Log}"/>
          </Grid>
        </Grid>
        <!-- Fenetre de mise a jour de Tune Manager -->
        <Grid x:Name="UpdOverlay" Grid.RowSpan="3" Grid.ColumnSpan="2" Visibility="Collapsed" Background="#D80B0606">
          <Grid Width="520" VerticalAlignment="Center" HorizontalAlignment="Center">
          <Border CornerRadius="22" Background="#140B0A" IsHitTestVisible="False">
            <Border.Effect><DropShadowEffect Color="#FF4A2E" BlurRadius="60" ShadowDepth="0" Opacity="0.30"/></Border.Effect>
          </Border>
          <Border CornerRadius="22" BorderBrush="#5A2A20" BorderThickness="1" Padding="34,30">
            <Border.Background>
              <LinearGradientBrush StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#2A1411" Offset="0"/><GradientStop Color="#140B0A" Offset="1"/></LinearGradientBrush>
            </Border.Background>
            <StackPanel>
              <Border Width="56" Height="56" CornerRadius="18" Background="{StaticResource AccentGrad}" HorizontalAlignment="Left" Margin="0,0,0,20">
                <Border.Effect><DropShadowEffect Color="#FF4A2E" BlurRadius="28" ShadowDepth="0" Opacity="0.6"/></Border.Effect>
                <Path Data="M 28,14 L 28,38 M 18,29 L 28,39 L 38,29" Stroke="White" StrokeThickness="4" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round"/>
              </Border>
              <TextBlock Text="MISE &#xC0; JOUR DISPONIBLE" Style="{StaticResource Kicker}" FontSize="12"/>
              <TextBlock Text="Nouvelle version de Tune Manager" FontSize="26" FontWeight="Bold" Margin="0,6,0,10" TextWrapping="Wrap"/>
              <TextBlock x:Name="UpdText" Style="{StaticResource Sub}" Margin="0,0,0,26" LineHeight="21"/>
              <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                <Button x:Name="UpdLater" Style="{StaticResource Ghost}" Content="Plus tard" Margin="0,0,10,0"/>
                <Button x:Name="UpdNow" Style="{StaticResource Primary}" Content="Mettre &#xE0; jour" Height="46"/>
              </StackPanel>
            </StackPanel>
          </Border>
          </Grid>
        </Grid>
      </Grid>
    </Grid>
  </Border>
</Window>
'@

$win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$ui = @{}
$xaml.SelectNodes('//*[@*[local-name()="Name"]]') | ForEach-Object { $n = $_.GetAttribute('Name', 'http://schemas.microsoft.com/winfx/2006/xaml'); if ($n) { $ui[$n] = $win.FindName($n) } }
if (Test-Path "$PSScriptRoot\TuneManager.ico") { try { $win.Icon = [Windows.Media.Imaging.BitmapFrame]::Create([Uri]"$PSScriptRoot\TuneManager.ico") } catch {} } elseif (Test-Path "$DB\ArtTuneDB.ico") { try { $win.Icon = [Windows.Media.Imaging.BitmapFrame]::Create([Uri]"$DB\ArtTuneDB.ico") } catch {} }

# Aura rouge-orange qui suit la souris ; apparait / disparait en fondu
function Fade-Aura([double]$to) {
    $a = New-Object Windows.Media.Animation.DoubleAnimation($to, [Windows.Duration][TimeSpan]::FromMilliseconds(250))
    $ui.Aura.BeginAnimation([Windows.UIElement]::OpacityProperty, $a)
}
$win.Add_MouseMove({
    $p = $_.GetPosition($ui.AuraLayer)
    $t = $ui.Aura.RenderTransform; $t.X = $p.X - $ui.Aura.Width / 2; $t.Y = $p.Y - $ui.Aura.Height / 2
    if ($ui.Aura.Tag -ne 'on') { $ui.Aura.Tag = 'on'; Fade-Aura 1 }
})
$win.Add_MouseLeave({ $ui.Aura.Tag = $null; Fade-Aura 0 })
# ClipToBounds coupe en rectangle : sans ce masque arrondi, l'aura deborde dans les coins transparents de la fenetre
$ui.AuraLayer.Add_SizeChanged({ param($s) $s.Clip = New-Object Windows.Media.RectangleGeometry((New-Object Windows.Rect(0, 0, $s.ActualWidth, $s.ActualHeight)), 23, 23) })

# Logo de l'application dans la barre de titre (plus grande image de l'icone)
foreach ($f in "$PSScriptRoot\TuneManager.ico", "$DB\ArtTuneDB.ico") {
    if (Test-Path $f) {
        try { $dec = New-Object Windows.Media.Imaging.IconBitmapDecoder([Uri]$f, 'None', 'OnLoad'); $ui.TitleLogo.Source = ($dec.Frames | Sort-Object PixelWidth -Descending | Select-Object -First 1); break } catch {}
    }
}

$bc = New-Object Windows.Media.BrushConverter
function Brush($hex) { $bc.ConvertFromString($hex) }
function Pump { $win.Dispatcher.Invoke([Action]{}, [Windows.Threading.DispatcherPriority]::Background) }
function LogTo($box, $msg) { $box.AppendText("$msg`r`n"); $box.ScrollToEnd(); Pump }

# Barre de titre / navigation
$ui.TitleBar.Add_MouseLeftButtonDown({ $win.DragMove() })
$ui.BtnMin.Add_Click({ $win.WindowState = 'Minimized' })
$pages = 0..4 | ForEach-Object { $ui["Page$_"] }
$script:lastCfg = 0
# Pages : 0 Installation, 1 Windows, 2 Voicemeeter (sous-menus de Configuration), 3 Profils, 4 Parametres
function Show-Page([int]$i) {
    for ($k = 0; $k -lt 5; $k++) { $pages[$k].Visibility = $(if ($k -eq $i) { 'Visible' } else { 'Collapsed' }) }
    $cfg = $i -le 2
    $ui.CfgSub.Visibility = $(if ($cfg) { 'Visible' } else { 'Collapsed' })
    if ($cfg) { $script:lastCfg = $i; if (-not $ui.NavCfg.IsChecked) { $ui.NavCfg.IsChecked = $true }; if (-not $ui["Nav$i"].IsChecked) { $ui["Nav$i"].IsChecked = $true } }
    elseif (-not $ui["Nav$i"].IsChecked) { $ui["Nav$i"].IsChecked = $true }
}
foreach ($k in 0..4) { $ui["Nav$k"].Add_Checked({ param($s) Show-Page ([int]$s.Name.Substring(3)) }) }
$ui.NavCfg.Add_Checked({ if ($pages[$script:lastCfg].Visibility -ne 'Visible') { Show-Page $script:lastCfg } })

# ---- Barre d'etat
function Set-Pill($b, $t, [string]$txt, [string]$kind) {
    $t.Text = $txt
    switch ($kind) {
        'ok'   { $b.Background = Brush '#1F1A12'; $b.BorderBrush = Brush '#4E4026'; $t.Foreground = Brush '#E9D7A8' }
        'bad'  { $b.Background = Brush '#2E1210'; $b.BorderBrush = Brush '#7A2A1E'; $t.Foreground = Brush '#FF8A70' }
        default { $b.Background = Brush '#231513'; $b.BorderBrush = Brush '#3A2420'; $t.Foreground = Brush '#D9CCC9' }
    }
}
function Update-StatusBar {
    try {
        $st = Get-State
        $ui.SbProfile.Text = if ($st.Active) { $st.Active } elseif ($st.Game) { "$($st.Game -replace '\|', ' ') (sans profil)" } else { 'aucun' }
        $vmOn = [bool](Get-Process voicemeeter* -ErrorAction SilentlyContinue)
        if (-not $st.VmA1 -and $vmOn -and -not $script:vmA1Tried) {
            $script:vmA1Tried = $true; $c = Get-VMCurrent
            if ($c -and $c.A1) { $st.VmA1 = $c.A1; try { Save-State $st } catch {} }
        }
        $ui.SbOut.Text = if ($st.VmA1) { $st.VmA1 } else { 'non réglée' }
        $e = Find-CableEndpoints
        $plus = if ($e.Render16) { Get-Endpoints | Where-Object { $_.Id -eq $e.Render16 } | Select-Object -First 1 }
        if (-not $plus) { Set-Pill $ui.SbChain $ui.SbChainT 'Art Tune + absent' 'bad' }
        elseif ($plus.Eapo -and $plus.Channels -eq 16) { Set-Pill $ui.SbChain $ui.SbChainT 'Art Tune +  ·  16 ch  ·  E-APO' 'ok' }
        else { Set-Pill $ui.SbChain $ui.SbChainT 'Art Tune + à réparer' 'bad' }
        Set-Pill $ui.SbVm $ui.SbVmT $(if ($vmOn) { 'Voicemeeter actif' } else { 'Voicemeeter arrêté' }) $(if ($vmOn) { 'ok' } else { 'bad' })
        $ui.SbDot.Fill = Brush $(if ($plus -and $plus.Eapo -and $vmOn) { '#FF5236' } else { '#5A4A46' })
    } catch {}
}
# Nom de sortie affiche : celui choisi par Tune Manager pour Voicemeeter (Haut-parleurs GC7, etc.)
function Select-VMOutputName([string]$pref) {
    if ($pref -match '\(([^)]*Sound Blaster[^)]*)\)\s*$') { return "Haut-parleurs ($($Matches[1]))" }
    $pref
}
$sbTimer = New-Object Windows.Threading.DispatcherTimer; $sbTimer.Interval = [TimeSpan]::FromSeconds(15)
$sbTimer.Add_Tick({ if ($win.IsVisible) { Update-StatusBar } }); $sbTimer.Start()

# ---- Icone dans la zone de notification
$script:quitting = $false
$trayIcon = New-Object Windows.Forms.NotifyIcon
$trayIcon.Text = 'Tune Manager'
$icoPath = if (Test-Path "$PSScriptRoot\TuneManager.ico") { "$PSScriptRoot\TuneManager.ico" } elseif (Test-Path "$DB\ArtTuneDB.ico") { "$DB\ArtTuneDB.ico" } else { $null }
$trayIcon.Icon = if ($icoPath) { New-Object Drawing.Icon $icoPath } else { [Drawing.SystemIcons]::Application }
$trayIcon.Visible = $true
function Show-Main { $win.ShowInTaskbar = $true; $win.Show(); if ($win.WindowState -eq 'Minimized') { $win.WindowState = 'Normal' }; $win.Activate() | Out-Null; Update-StatusBar }
function Build-TrayMenu {
    $m = New-Object Windows.Forms.ContextMenuStrip
    $m.BackColor = [Drawing.Color]::FromArgb(26, 15, 14); $m.ForeColor = [Drawing.Color]::FromArgb(245, 239, 238); $m.ShowImageMargin = $false; $m.ShowCheckMargin = $true
    $h = $m.Items.Add('Profils'); $h.Enabled = $false
    $st = Get-State
    foreach ($p in $script:Profiles) {
        $it = New-Object Windows.Forms.ToolStripMenuItem $p.Name; $it.Tag = $p.Name; $it.Checked = ($p.Name -eq $st.Active)
        $it.Add_Click({ param($s) Activate-Profile $s.Tag; if ($script:Profiles) { $trayIcon.ShowBalloonTip(2500, 'Tune Manager', "Profil « $($s.Tag) » appliqué.", 'None') } })
        [void]$m.Items.Add($it)
    }
    if (-not $script:Profiles.Count) { $x = $m.Items.Add('(aucun profil)'); $x.Enabled = $false }
    [void]$m.Items.Add((New-Object Windows.Forms.ToolStripSeparator))
    $o = $m.Items.Add('Ouvrir Tune Manager'); $o.Font = New-Object Drawing.Font($o.Font, [Drawing.FontStyle]::Bold); $o.Add_Click({ Show-Main })
    $q = $m.Items.Add('Quitter'); $q.Add_Click({ $script:quitting = $true; $win.Close() })
    $m
}
$trayIcon.Add_MouseUp({ param($s, $e) if ($e.Button -eq 'Right') { $trayIcon.ContextMenuStrip = Build-TrayMenu; $mi = $trayIcon.GetType().GetMethod('ShowContextMenu', [Reflection.BindingFlags]'Instance,NonPublic'); $mi.Invoke($trayIcon, $null) } })
$trayIcon.Add_MouseClick({ param($s, $e) if ($e.Button -eq 'Left') { Show-Main } })
$trayIcon.Add_BalloonTipClicked({ Show-Main })
$ui.BtnClose.Add_Click({ $win.Close() })
$win.Add_Closing({ param($s, $e)
    if (-not $script:quitting -and (Get-UiPref 'CloseToTray' $true)) {
        $e.Cancel = $true; $win.Hide()
        if (-not $script:trayHinted) { $script:trayHinted = $true; $trayIcon.ShowBalloonTip(3500, 'Tune Manager', 'Tune Manager reste dans la zone de notification. Clic droit sur l''icône pour changer de profil.', 'None') }
    }
})
$win.Add_Closed({ $trayIcon.Visible = $false; $trayIcon.Dispose() })

# ---- Preferences de l'interface (C:\Users\Public\TuneManager\ui.json)
$UiPrefF = Join-Path $env:PUBLIC 'TuneManager\ui.json'
function Get-UiPref([string]$k, $def) { try { $j = [IO.File]::ReadAllText($UiPrefF) | ConvertFrom-Json; if ($null -ne $j.$k) { return $j.$k } } catch {}; $def }
function Set-UiPref([string]$k, $v) {
    $h = @{}; try { ([IO.File]::ReadAllText($UiPrefF) | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $h[$_.Name] = $_.Value } } catch {}
    $h[$k] = $v; New-Item -ItemType Directory (Split-Path $UiPrefF) -Force | Out-Null; [IO.File]::WriteAllText($UiPrefF, (ConvertTo-Json $h))
}

# ---- Une seule instance : un second lancement affiche la fenetre deja ouverte
$showEvt = New-Object Threading.EventWaitHandle($false, 'AutoReset', 'Local\TuneManagerShow')
$evtTimer = New-Object Windows.Threading.DispatcherTimer; $evtTimer.Interval = [TimeSpan]::FromMilliseconds(400)
$evtTimer.Add_Tick({ if ($showEvt.WaitOne(0)) { Show-Main } }); $evtTimer.Start()

# Ligne de statut style "carte avec case rouge"
function New-Row($ok, $title, $detail) {
    $b = New-Object Windows.Controls.Border; $b.CornerRadius = 16; $b.Padding = '18,14'; $b.Margin = '0,0,0,10'; $b.BorderThickness = 1
    $b.Background = Brush '#1A0F0E'; $b.BorderBrush = Brush $(if ($ok) { '#2E1C19' } else { '#5A2418' })
    $g = New-Object Windows.Controls.Grid
    $c0 = New-Object Windows.Controls.ColumnDefinition; $c0.Width = '52'; $g.ColumnDefinitions.Add($c0); $g.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition))
    $ic = New-Object Windows.Controls.Border; $ic.Width = 34; $ic.Height = 34; $ic.CornerRadius = 10; $ic.HorizontalAlignment = 'Left'; $ic.VerticalAlignment = 'Top'
    if ($ok) {
        $ic.Background = $win.FindResource('AccentGrad')
        $sh = New-Object Windows.Media.Effects.DropShadowEffect; $sh.Color = [Windows.Media.Color]::FromRgb(255,74,46); $sh.BlurRadius = 16; $sh.ShadowDepth = 0; $sh.Opacity = 0.5; $ic.Effect = $sh
        $p = New-Object Windows.Shapes.Path; $p.Data = [Windows.Media.Geometry]::Parse('M 9,17 L 14,22 L 25,11'); $p.Stroke = [Windows.Media.Brushes]::White; $p.StrokeThickness = 3
        $p.StrokeStartLineCap = 'Round'; $p.StrokeEndLineCap = 'Round'; $p.StrokeLineJoin = 'Round'; $ic.Child = $p
    } else {
        $ic.Background = Brush '#2A1A17'; $ic.BorderBrush = Brush '#FF5236'; $ic.BorderThickness = 1.5
        $t = New-Object Windows.Controls.TextBlock; $t.Text = '!'; $t.FontWeight = 'Bold'; $t.FontSize = 16; $t.Foreground = Brush '#FF5236'
        $t.HorizontalAlignment = 'Center'; $t.VerticalAlignment = 'Center'; $ic.Child = $t
    }
    $g.Children.Add($ic) | Out-Null
    $sp = New-Object Windows.Controls.StackPanel; [Windows.Controls.Grid]::SetColumn($sp, 1); $sp.VerticalAlignment = 'Center'
    $tt = New-Object Windows.Controls.TextBlock; $tt.Text = $title; $tt.FontSize = 15; $tt.FontWeight = 'SemiBold'; $tt.TextWrapping = 'Wrap'; $tt.Foreground = Brush '#F5EFEE'
    $sp.Children.Add($tt) | Out-Null
    if ($detail) { $d = New-Object Windows.Controls.TextBlock; $d.Text = $detail; $d.FontSize = 12.5; $d.Margin = '0,4,0,0'; $d.TextWrapping = 'Wrap'; $d.Foreground = Brush '#B3A5A2'; $sp.Children.Add($d) | Out-Null }
    $g.Children.Add($sp) | Out-Null; $b.Child = $g; $b
}

# ---------------------------------------------------------------- 1. Installation
$StepNames = @('Telechargement', 'VB-CABLE', 'Voicemeeter', 'ReaPlugs', 'Equalizer APO', 'HeSuVi', 'Bibliotheque', 'HRIR', 'Peripheriques', 'Nettoyage')
$StepLabels = @('Fichiers', 'VB-CABLE', 'Voicemeeter', 'ReaPlugs', 'E-APO', 'HeSuVi', 'Biblioth&#232;que', 'HRIR', 'P&#233;riph.', 'Finition')
# Etapes animees : anneau qui tourne sur l'etape en cours, arc = vraie progression de l'etape,
# retournement 3D + coche a la fin d'une etape, ligne lumineuse vers la suivante, relief de l'etape active.
$Inv = [Globalization.CultureInfo]::InvariantCulture
function New-Anim([double]$to, [int]$ms) {
    $a = New-Object Windows.Media.Animation.DoubleAnimation($to, [Windows.Duration][TimeSpan]::FromMilliseconds($ms))
    $e = New-Object Windows.Media.Animation.CubicEase; $e.EasingMode = 'EaseOut'; $a.EasingFunction = $e; $a
}
function Get-ArcGeometry([double]$f) {
    if ($f -le 0.001) { return $null }
    if ($f -ge 0.999) { return New-Object Windows.Media.EllipseGeometry((New-Object Windows.Point(22, 22)), 20, 20) }
    $a = 2 * [Math]::PI * $f; $x = 22 + 20 * [Math]::Sin($a); $y = 22 - 20 * [Math]::Cos($a)
    [Windows.Media.Geometry]::Parse([string]::Format($Inv, 'M 22,2 A 20,20 0 {0} 1 {1:0.##},{2:0.##}', $(if ($f -gt 0.5) { 1 } else { 0 }), $x, $y))
}
$script:dots = @()
for ($i = 0; $i -lt 10; $i++) {
    $cell = New-Object Windows.Controls.StackPanel
    $top = New-Object Windows.Controls.Grid; $top.Height = 48
    $top.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition)); $top.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition))
    $lines = @()
    foreach ($side in 0, 1) {
        if (($side -eq 0 -and $i -eq 0) -or ($side -eq 1 -and $i -eq 9)) { $lines += , $null; continue }
        $lg = New-Object Windows.Controls.Grid; $lg.Height = 2; $lg.VerticalAlignment = 'Center'; [Windows.Controls.Grid]::SetColumn($lg, $side)
        $tr = New-Object Windows.Shapes.Rectangle; $tr.Fill = Brush '#3A2420'
        $fl = New-Object Windows.Shapes.Rectangle; $fl.Fill = $win.FindResource('AccentGrad'); $fl.RenderTransformOrigin = '0,0.5'
        $fs = New-Object Windows.Media.ScaleTransform(0, 1); $fl.RenderTransform = $fs
        $lg.Children.Add($tr) | Out-Null; $lg.Children.Add($fl) | Out-Null; $top.Children.Add($lg) | Out-Null
        $lines += , $fs
    }
    $host_ = New-Object Windows.Controls.Grid; $host_.Width = 44; $host_.Height = 44; [Windows.Controls.Grid]::SetColumnSpan($host_, 2)
    $host_.RenderTransformOrigin = '0.5,0.5'; $hs = New-Object Windows.Media.ScaleTransform(1, 1); $host_.RenderTransform = $hs
    $mask = New-Object Windows.Shapes.Ellipse; $mask.Fill = Brush '#1A0F0E'
    $track = New-Object Windows.Shapes.Ellipse; $track.Stroke = Brush '#3A2420'; $track.StrokeThickness = 3; $track.Margin = '0.5'
    $arc = New-Object Windows.Shapes.Path; $arc.Stroke = $win.FindResource('AccentGrad'); $arc.StrokeThickness = 3; $arc.StrokeStartLineCap = 'Round'; $arc.StrokeEndLineCap = 'Round'
    # anneau tournant : un quart de cercle en degrade qui fait le tour
    $spin = New-Object Windows.Shapes.Path; $spin.Data = [Windows.Media.Geometry]::Parse('M 22,-1 A 23,23 0 0 1 45,22'); $spin.StrokeThickness = 2; $spin.StrokeEndLineCap = 'Round'
    $sg = New-Object Windows.Media.LinearGradientBrush; $sg.StartPoint = '0,0'; $sg.EndPoint = '1,1'
    $sg.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromArgb(0, 255, 82, 54), 0))); $sg.GradientStops.Add((New-Object Windows.Media.GradientStop([Windows.Media.Color]::FromArgb(255, 255, 140, 100), 1)))
    $spin.Stroke = $sg; $spin.Visibility = 'Hidden'; $rt = New-Object Windows.Media.RotateTransform(0, 22, 22); $spin.RenderTransform = $rt
    # halo qui respire (calque separe : un Effect sur le disque rendrait le chiffre flou)
    $glow = New-Object Windows.Shapes.Ellipse; $glow.Width = 32; $glow.Height = 32; $glow.Fill = Brush '#FF4A2E'; $glow.Opacity = 0
    $ge = New-Object Windows.Media.Effects.DropShadowEffect; $ge.Color = [Windows.Media.Color]::FromRgb(255, 74, 46); $ge.BlurRadius = 22; $ge.ShadowDepth = 0; $glow.Effect = $ge
    $d = New-Object Windows.Controls.Border; $d.Width = 32; $d.Height = 32; $d.CornerRadius = 16; $d.Background = Brush '#2A1A17'; $d.BorderBrush = Brush '#4A2E29'; $d.BorderThickness = 1.5
    $d.RenderTransformOrigin = '0.5,0.5'; $flip = New-Object Windows.Media.ScaleTransform(1, 1); $d.RenderTransform = $flip
    $n = New-Object Windows.Controls.TextBlock; $n.Text = "$($i + 1)"; $n.FontSize = 12; $n.FontWeight = 'Bold'; $n.Foreground = Brush '#9C8D8A'; $n.HorizontalAlignment = 'Center'; $n.VerticalAlignment = 'Center'; $d.Child = $n
    foreach ($c in $mask, $track, $arc, $spin, $glow, $d) { $host_.Children.Add($c) | Out-Null }
    $top.Children.Add($host_) | Out-Null
    $t = New-Object Windows.Controls.TextBlock; $t.Text = [Net.WebUtility]::HtmlDecode($StepLabels[$i]); $t.FontSize = 11; $t.Foreground = Brush '#9C8D8A'; $t.HorizontalAlignment = 'Center'; $t.Margin = '0,6,0,0'
    $pc = New-Object Windows.Controls.TextBlock; $pc.FontSize = 10.5; $pc.FontWeight = 'Bold'; $pc.Foreground = Brush '#FF7A5C'; $pc.HorizontalAlignment = 'Center'; $pc.Margin = '0,2,0,0'; $pc.Text = ' '
    $cell.Children.Add($top) | Out-Null; $cell.Children.Add($t) | Out-Null; $cell.Children.Add($pc) | Out-Null
    $ui.StepDots.Children.Add($cell) | Out-Null
    $script:dots += , @{ Cell = $cell; Disk = $d; Num = $n; Lbl = $t; Pct = $pc; Arc = $arc; Spin = $spin; Rot = $rt; Glow = $glow; Flip = $flip; Scale = $hs; L = $lines[0]; R = $lines[1]; State = 'todo'; Shown = 0.0; Target = 0.0 }
}

function Set-DiskLook($s, [string]$state) {
    $d = $s.Disk; $n = $s.Num
    switch ($state) {
        'done'   { $d.Background = $win.FindResource('AccentGrad'); $d.BorderThickness = 0; $n.Text = [string][char]0x2713; $n.FontSize = 15; $n.Foreground = [Windows.Media.Brushes]::White; $s.Lbl.Foreground = Brush '#F5EFEE' }
        'active' { $d.Background = Brush '#24130F'; $d.BorderBrush = Brush '#FF5236'; $d.BorderThickness = 2; $n.FontSize = 12; $n.Foreground = Brush '#FF5236'; $s.Lbl.Foreground = Brush '#FF7A5C' }
        default  { $d.Background = Brush '#2A1A17'; $d.BorderBrush = Brush '#4A2E29'; $d.BorderThickness = 1.5; $n.FontSize = 12; $n.Foreground = Brush '#9C8D8A'; $s.Lbl.Foreground = Brush '#9C8D8A' }
    }
    if ($state -ne 'done') { $n.Text = "$([array]::IndexOf($script:dots, $s) + 1)" }
}
function Set-StepState($s, [string]$state, [bool]$animate) {
    if ($s.State -eq $state) { return }
    $prev = $s.State; $s.State = $state
    $s.Rot.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty, $null)
    $s.Glow.BeginAnimation([Windows.UIElement]::OpacityProperty, $null); $s.Glow.Opacity = 0
    if ($state -eq 'active') {
        $s.Spin.Visibility = 'Visible'
        $r = New-Object Windows.Media.Animation.DoubleAnimation(0, 360, [Windows.Duration][TimeSpan]::FromSeconds(1.1)); $r.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
        $s.Rot.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty, $r)
        $g = New-Object Windows.Media.Animation.DoubleAnimation(0.25, 0.75, [Windows.Duration][TimeSpan]::FromSeconds(1.2)); $g.AutoReverse = $true; $g.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
        $s.Glow.BeginAnimation([Windows.UIElement]::OpacityProperty, $g)
        Set-DiskLook $s 'active'
    } else {
        $s.Spin.Visibility = 'Hidden'; $s.Pct.Text = ' '
    }
    if ($state -eq 'done') {
        $s.Target = 1; $s.Shown = 1; $s.Arc.Data = $null
        if ($animate) {
            # retournement facon piece : le disque se replie, change de face, puis revient avec un rebond
            $kf = New-Object Windows.Media.Animation.DoubleAnimationUsingKeyFrames; $kf.Duration = [TimeSpan]::FromMilliseconds(560)
            $kf.KeyFrames.Add((New-Object Windows.Media.Animation.LinearDoubleKeyFrame(0, [Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromMilliseconds(140))))) | Out-Null
            $b = New-Object Windows.Media.Animation.BackEase; $b.Amplitude = 0.6; $b.EasingMode = 'EaseOut'
            $kf.KeyFrames.Add((New-Object Windows.Media.Animation.EasingDoubleKeyFrame(1, [Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromMilliseconds(560)), $b))) | Out-Null
            $s.Flip.BeginAnimation([Windows.Media.ScaleTransform]::ScaleXProperty, $kf)
            # la face change quand le disque est replie (traite par $arcTimer)
            $script:flipQueue.Add(@{ S = $s; At = [DateTime]::Now.AddMilliseconds(140) })
            if ($s.R) { $s.R.BeginAnimation([Windows.Media.ScaleTransform]::ScaleXProperty, (New-Anim 1 380)) }
            $k = [array]::IndexOf($script:dots, $s)
            if ($k -lt 9 -and $script:dots[$k + 1].L) { $a2 = New-Anim 1 380; $a2.BeginTime = [TimeSpan]::FromMilliseconds(330); $script:dots[$k + 1].L.BeginAnimation([Windows.Media.ScaleTransform]::ScaleXProperty, $a2) }
        } else {
            $s.Flip.BeginAnimation([Windows.Media.ScaleTransform]::ScaleXProperty, $null); $s.Flip.ScaleX = 1; Set-DiskLook $s 'done'
            if ($s.R) { $s.R.BeginAnimation([Windows.Media.ScaleTransform]::ScaleXProperty, $null); $s.R.ScaleX = 1 }
            $k = [array]::IndexOf($script:dots, $s); if ($k -lt 9 -and $script:dots[$k + 1].L) { $script:dots[$k + 1].L.BeginAnimation([Windows.Media.ScaleTransform]::ScaleXProperty, $null); $script:dots[$k + 1].L.ScaleX = 1 }
        }
    } elseif ($state -eq 'todo') {
        $s.Target = 0; $s.Shown = 0; $s.Arc.Data = $null; Set-DiskLook $s 'todo'
        $s.Flip.BeginAnimation([Windows.Media.ScaleTransform]::ScaleXProperty, $null); $s.Flip.ScaleX = 1
        foreach ($l in $s.L, $s.R) { if ($l) { $l.BeginAnimation([Windows.Media.ScaleTransform]::ScaleXProperty, $null); $l.ScaleX = 0 } }
    }
}
# Relief : l'etape active avance au premier plan, celles a venir reculent pendant l'installation
function Set-Relief($s, [double]$scale, [double]$op) {
    $s.Scale.BeginAnimation([Windows.Media.ScaleTransform]::ScaleXProperty, (New-Anim $scale 300))
    $s.Scale.BeginAnimation([Windows.Media.ScaleTransform]::ScaleYProperty, (New-Anim $scale 300))
    $s.Cell.BeginAnimation([Windows.UIElement]::OpacityProperty, (New-Anim $op 300))
}
# $cur : etape en cours (1..10), $done : tout est fini, $stepPct : avancee reelle de l'etape en cours (0..100)
function Set-Dots([int]$cur, [bool]$done, [double]$stepPct = 0, [bool]$animate = $true) {
    $running = $cur -gt 0 -and -not $done
    for ($i = 0; $i -lt 10; $i++) {
        $s = $script:dots[$i]
        $state = if ($done -or $i -lt $cur - 1) { 'done' } elseif ($i -eq $cur - 1) { 'active' } else { 'todo' }
        Set-StepState $s $state $animate
        if ($state -eq 'active') { $s.Target = [Math]::Max(0.0, [Math]::Min(1.0, $stepPct / 100.0)) }
        $sc, $op = if (-not $running) { 1.0, 1.0 } elseif ($state -eq 'active') { 1.18, 1.0 } elseif ($state -eq 'done') { 0.96, 1.0 } else { 0.9, 0.5 }
        if ($s.RelS -ne $sc -or $s.RelO -ne $op) { $s.RelS = $sc; $s.RelO = $op; Set-Relief $s $sc $op }
    }
    if ($running) { Start-Shine } else { Stop-Shine }
}
# Arc de l'etape en cours : avance en douceur vers la vraie valeur
$arcTimer = New-Object Windows.Threading.DispatcherTimer; $arcTimer.Interval = [TimeSpan]::FromMilliseconds(30)
$script:flipQueue = New-Object System.Collections.ArrayList
$arcTimer.Add_Tick({
    for ($q = $script:flipQueue.Count - 1; $q -ge 0; $q--) {
        $it = $script:flipQueue[$q]
        if ([DateTime]::Now -ge $it.At) { if ($it.S.State -eq 'done') { Set-DiskLook $it.S 'done' }; $script:flipQueue.RemoveAt($q) }
    }
    foreach ($s in $script:dots) {
        if ($s.State -ne 'active') { continue }
        $diff = $s.Target - $s.Shown
        if ([Math]::Abs($diff) -gt 0.002) { $s.Shown += $diff * 0.12 } else { $s.Shown = $s.Target }
        $s.Arc.Data = Get-ArcGeometry $s.Shown
        $s.Pct.Text = "$([int]($s.Shown * 100)) %"
    }
})
$arcTimer.Start()
function Start-Shine {
    if ($ui.BarShine.Visibility -eq 'Visible') { return }
    $ui.BarShine.Visibility = 'Visible'
    $a = New-Object Windows.Media.Animation.DoubleAnimation(-140, 900, [Windows.Duration][TimeSpan]::FromSeconds(1.8)); $a.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
    $ui.BarShine.RenderTransform.BeginAnimation([Windows.Media.TranslateTransform]::XProperty, $a)
}
function Stop-Shine { $ui.BarShine.RenderTransform.BeginAnimation([Windows.Media.TranslateTransform]::XProperty, $null); $ui.BarShine.Visibility = 'Collapsed' }
function Set-Bar([int]$pct) {
    $w = $ui.BarHost.ActualWidth; if ($w -le 0) { $w = 700 }
    $to = [Math]::Max(0, [Math]::Min($w, $w * $pct / 100))
    $ui.BarFill.BeginAnimation([Windows.FrameworkElement]::WidthProperty, (New-Anim $to 450))
    $ui.BarShineHost.Width = $to; $ui.CurPct.Text = "$pct %"
}

$script:job = $null; $script:jobKind = $null
$timer = New-Object Windows.Threading.DispatcherTimer; $timer.Interval = [TimeSpan]::FromMilliseconds(600)
$timer.Add_Tick({
    if (-not (Test-Path $ProgFile)) { return }
    try { $p = Get-Content $ProgFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return }
    $ui.CurTask.Text = $p.Msg; Set-Bar ([int]$p.Pct)
    if ($script:jobKind -eq 'install') { $stp = [int]$p.Step; Set-Dots $stp ([bool]$p.Done -and -not $p.Error) $(if ($stp -gt 0) { ([double]$p.Pct - 10 * ($stp - 1)) * 10 } else { 0 }) }
    else { Start-Shine }
    $txt = ($p.Log -join "`r`n"); if ($ui.InstLog.Text -ne $txt) { $ui.InstLog.Text = $txt; $ui.InstLog.ScrollToEnd() }
    if ($p.Done -or ($script:job -and $script:job.HasExited)) {
        $timer.Stop(); $ui.WarnBanner.Visibility = 'Collapsed'; Stop-Shine
        $ui.BtnInstall.IsEnabled = $true; $ui.BtnUninstall.IsEnabled = $true
        if ($p.Error) { $ui.InstTitle.Text = 'Installation interrompue'; $ui.CurTask.Text = "Erreur : $($p.Error)"; $ui.CurTask.Foreground = Brush '#FF5236' }
        elseif ($script:jobKind -eq 'install') {
            $ui.InstTitle.Text = 'Installation termin&#233;e' -replace '&#233;', [char]0xE9
            try { Load-Presets; Update-Side; Show-Diag } catch { $script:loading = $false }
            # Le Device Selector est regle automatiquement a l'etape 10 : on ne l'ouvre que si Equalizer APO
            # n'est toujours pas actif sur Art Tune + (reglage automatique rate)
            $eapoOk = $false
            try { $ce = Find-CableEndpoints; $plus = Get-Endpoints | Where-Object { $_.Id -eq $ce.Render16 } | Select-Object -First 1; $eapoOk = [bool]($plus -and $plus.Eapo) } catch {}
            if ($eapoOk) {
                Show-Msg "Installation terminée`nTout est prêt : Equalizer APO est activé sur Art Tune +. Choisis ou crée ton profil dans l'onglet Profils." | Out-Null
                Show-Page 3
            } else {
                Show-Msg "Installation terminée`nUne dernière étape manuelle : le Device Selector va s'ouvrir. Coche « Art Tune + », coche « Troubleshooting options », choisis « LFX/GFX », puis OK." 'OK' 'Warning' | Out-Null
                $env:QT_PLUGIN_PATH = "C:\Program Files\EqualizerAPO\qt"; Start-Process "C:\Program Files\EqualizerAPO\DeviceSelector.exe" -WorkingDirectory "C:\Program Files\EqualizerAPO"
                Show-Page 1
            }
        } elseif ($script:removeAppAfter -and -not $p.Error) {
            # Chaine retiree : on retire maintenant le logiciel lui-meme (raccourcis, dossier, entree Applications)
            $ui.InstTitle.Text = 'D' + [char]0xE9 + 'sinstallation de Tune Manager...'
            Start-Process powershell "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`" -RemoveApp -AfterChain" -WindowStyle Hidden
            $script:quitting = $true; $win.Close()
        } else { $ui.InstTitle.Text = 'D' + [char]0xE9 + 'sinstallation termin' + [char]0xE9 + 'e'; Update-Side; $ui.Nav0.Content = 'Installation'; $ui.BtnInstall.Content = 'Installer' }
    }
})
function Start-Job2([string]$kind) {
    Remove-Item $ProgFile -ErrorAction SilentlyContinue
    $ui.InstLog.Clear(); $ui.CurTask.Foreground = Brush '#F5EFEE'; Set-Bar 0; Set-Dots 0 $false
    $ui.BtnInstall.IsEnabled = $false; $ui.BtnUninstall.IsEnabled = $false; $ui.WarnBanner.Visibility = 'Visible'
    $ui.InstTitle.Text = if ($kind -eq 'install') { 'Installation en cours' } else { 'D' + [char]0xE9 + 'sinstallation en cours' }
    $sw = if ($kind -eq 'install') { '-RunInstall' } else { '-RunUninstall' }
    $script:jobKind = $kind
    $script:job = Start-Process powershell "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`" $sw" -WindowStyle Hidden -PassThru
    $timer.Start()
}
# Chaine deja en place : page "Chaine audio" (etat + Reparer) au lieu du parcours d'installation
function Test-ChainInstalled { (Test-Path $Lib) -and (Test-Path (Join-Path $VmDir 'voicemeeter*.exe')) -and (Test-Path "$env:ProgramFiles\EqualizerAPO") }
function Update-InstallView {
    if ($script:jobKind -and $timer.IsEnabled) { return }
    $inst = Test-ChainInstalled
    $v = if ($inst) { 'Collapsed' } else { 'Visible' }
    $ui.StepCard.Visibility = $v; $ui.ProgCard.Visibility = $v; $ui.InstLog.Visibility = $v
    $ui.InstDone.Visibility = $(if ($inst) { 'Visible' } else { 'Collapsed' })
    $ui.Nav0.Content = if ($inst) { 'Cha' + [char]0xEE + 'ne audio' } else { 'Installation' }
    $ui.InstTitle.Text = $ui.Nav0.Content
    $ui.BtnInstall.Content = if ($inst) { 'R' + [char]0xE9 + 'parer' } else { 'Installer' }
    $ui.InstSub.Text = if ($inst) { 'Tout est install' + [char]0xE9 + '. Tes profils s''appliquent depuis l''onglet Profils.' } else { 'Installe toute la cha' + [char]0xEE + 'ne audio ArtIsWar en silence : VB-CABLE, Voicemeeter, Equalizer APO, moteur ATK, biblioth' + [char]0xE8 + 'que et r' + [char]0xE9 + 'glages.' }
}
function Show-InstallProgress {
    $ui.InstDone.Visibility = 'Collapsed'; $ui.StepCard.Visibility = 'Visible'; $ui.ProgCard.Visibility = 'Visible'; $ui.InstLog.Visibility = 'Visible'
}
Update-InstallView
$ui.BtnInstall.Add_Click({ Show-InstallProgress; Start-Job2 'install' })
$ui.BtnUninstall.Add_Click({
    $r = Show-Msg "Que veux-tu désinstaller ?`nChaîne audio seule : retire Equalizer APO, ReaPlugs, plugins, VB-CABLE, Voicemeeter et la bibliothèque. Tune Manager reste installé.`nTout, logiciel compris : retire aussi Tune Manager (raccourcis, dossier, entrée dans Applications)." 'YesNoCancel' 'Warning' @{ Yes = 'Tout, logiciel compris'; No = 'Chaîne audio seule' }
    if ($r -eq 'Cancel') { return }
    $script:removeAppAfter = ($r -eq 'Yes')
    Show-InstallProgress; Start-Job2 'uninstall'
})
$ui.BtnOfficial.Add_Click({ Start-Process powershell -Verb RunAs -ArgumentList "-NoExit -NoProfile -ExecutionPolicy Bypass -Command `"$OfficialCmd`"" })
# ---------------------------------------------------------------- 2. Windows
function Show-Diag {
    $ui.DiagList.Children.Clear()
    $items = @(Get-Diagnostic) + @(Test-Integrity | ForEach-Object { $_ | Add-Member Fix "Onglet Mises a jour > Reinstaller, pour remettre les fichiers officiels." -PassThru }); $bad = @($items | Where-Object { -not $_.Ok }).Count
    foreach ($d in $items) { $ui.DiagList.Children.Add((New-Row $d.Ok $d.Text $(if (-not $d.Ok) { $d.Fix }))) | Out-Null }
    Update-Side
    $ui.DiagSummary.Text = if ($bad -eq 0) { "Tout est en ordre : $($items.Count) points vérifiés." } else { "$bad point(s) à corriger sur $($items.Count)." }
}
$ui.BtnDiag.Add_Click({ try { Show-Diag } catch { $ui.DiagSummary.Text = "Erreur : $($_.Exception.Message)" } })
$ui.BtnDisable.Add_Click({
    try { $script:msgs = @(); Disable-ExtraDevices { param($m) $script:msgs += $m }; Show-Diag; if ($script:msgs.Count) { $ui.DiagSummary.Text = ($script:msgs -join ' | ') } }
    catch { $ui.DiagSummary.Text = "Erreur : $($_.Exception.Message)" }
})
$ui.BtnDevSel.Add_Click({
    $ds = "C:\Program Files\EqualizerAPO\DeviceSelector.exe"
    if (Test-Path $ds) { $env:QT_PLUGIN_PATH = "C:\Program Files\EqualizerAPO\qt"; Start-Process $ds -WorkingDirectory "C:\Program Files\EqualizerAPO"; Show-Msg "Device Selector`nCoche « Art Tune + », coche « Troubleshooting options », choisis « LFX/GFX », puis OK. Redémarre le PC si c'est demandé." | Out-Null }
    else { Show-Msg "Equalizer APO n'est pas installé`nInstalle d'abord la chaîne audio depuis Configuration." 'OK' 'Warning' | Out-Null }
})
$ui.BtnSound.Add_Click({ Start-Process "mmsys.cpl" })

# ---------------------------------------------------------------- 3. Voicemeeter
function Load-VmOutputs {
    try {
        $outs = @(Get-VMOutputs); $cur = Get-VMCurrent
        $ui.CbOut.Items.Clear(); foreach ($o in $outs) { [void]$ui.CbOut.Items.Add($o) }
        if ($cur -and $outs -contains $cur.A1) { $ui.CbOut.SelectedItem = $cur.A1 } elseif ($outs.Count) { $ui.CbOut.SelectedItem = (Select-VMOutput (Get-State).VmOut) }
        $ui.VmLog.Text = if ($cur) { "Actuel`r`n  Entree 1 : $($cur.Input)`r`n  Sortie A1 : $($cur.A1)" } else { "" }
    } catch { $ui.VmLog.Text = "Erreur : $($_.Exception.Message)" }
}
$ui.BtnVmLoad.Add_Click({ Load-VmOutputs })
$ui.BtnVm.Add_Click({
    if (-not $ui.CbOut.SelectedItem) { $ui.VmLog.Text = "Choisis d'abord ton casque dans la liste."; return }
    $ui.VmLog.Clear()
    try { Configure-VM $ui.CbOut.SelectedItem { param($m) LogTo $ui.VmLog $m } } catch { LogTo $ui.VmLog "Erreur : $($_.Exception.Message)" }
})

# ---------------------------------------------------------------- 4. Profils
# Un profil = casque (EQ) + jeu/version + style + arme + HRIR + boost. Un clic l'applique en direct.
$ProfF = Join-Path $env:PUBLIC 'TuneManager\profiles.json'
$script:Tunes = @(); $script:state = @{}; $script:Profiles = @(); $script:Phones = $null
function Load-Profiles {
    $script:Profiles = @()
    if (Test-Path $ProfF) { try { $script:Profiles = @([IO.File]::ReadAllText($ProfF) | ConvertFrom-Json) } catch {} }
}
function Save-Profiles {
    New-Item -ItemType Directory (Split-Path $ProfF) -Force | Out-Null
    [IO.File]::WriteAllText($ProfF, (ConvertTo-Json @($script:Profiles) -Depth 4))
}
function Eq-Label([string]$file) { $b = [IO.Path]::GetFileNameWithoutExtension($file) -replace ' - [\w-]+V\d+$', ''; if ($b -eq 'Flat_EQ') { 'Aucun EQ (plat)' } else { $b } }
function Fam-Name($k) { if ($FamNames[$k]) { $FamNames[$k] } else { $k } }
function Gun-Name($k) { if ($GunNames[$k]) { $GunNames[$k] -replace ' \(.*\)$', '' } else { $k } }
# Premier lancement : un profil a partir du preset deja applique
function Seed-Profile {
    if ($script:Profiles.Count) { return }
    $st = Get-State; if (-not $st.Game) { return }
    $g, $v = $st.Game -split '\|'
    $eqName = if ($st.Eq) { Split-Path $st.Eq -Leaf } else { 'Flat_EQ.txt' }
    $ph = Eq-Label $eqName
    $script:Profiles = @([pscustomobject]@{ Name = "$ph  ·  $g $v"; Game = $g; Ver = $v; Family = $st.Family; Gun = $st.Gun; Hrir = $st.Hrir
        Phone = $ph; PhoneFile = ''; EqName = $eqName; Boost = [int](Get-Boost) })
    try { Save-Profiles; $st.Active = $script:Profiles[0].Name; Save-State $st } catch {}
}
function New-Chip([string]$t, [bool]$hot = $false) {
    $b = New-Object Windows.Controls.Border; $b.CornerRadius = 9; $b.Padding = '10,4'; $b.Margin = '0,0,8,8'
    $b.Background = Brush $(if ($hot) { '#3A1A14' } else { '#231513' }); $b.BorderBrush = Brush $(if ($hot) { '#7A3426' } else { '#3A2420' }); $b.BorderThickness = 1
    $tb = New-Object Windows.Controls.TextBlock; $tb.Text = $t; $tb.FontSize = 12; $tb.FontWeight = 'SemiBold'; $tb.Foreground = Brush $(if ($hot) { '#FFB09C' } else { '#D9CCC9' })
    $b.Child = $tb; $b
}
function Profile-Chips($p) { @((Fam-Name $p.Family), "Arme $(Gun-Name $p.Gun)", $p.Hrir, $(if ([int]$p.Boost -gt 0) { "Boost +$($p.Boost) dB" } else { 'Boost off' })) }
function Render-Profiles {
    $st = Get-State; $active = $script:Profiles | Where-Object { $_.Name -eq $st.Active } | Select-Object -First 1
    if ($active) {
        $ui.ActName.Text = $active.Phone; $ui.ActSub.Text = "$($active.Game) $($active.Ver)$(if ($active.Name -ne "$($active.Phone)  ·  $($active.Game) $($active.Ver)") { "  ·  $($active.Name)" })"
        $ui.ActChips.Children.Clear(); foreach ($c in (Profile-Chips $active)) { [void]$ui.ActChips.Children.Add((New-Chip $c $true)) }
        $ui.BtnEditProfile.IsEnabled = $true; $ui.BtnDelProfile.IsEnabled = $true; $ui.BtnGameSettings.IsEnabled = $true
        $script:boostSync = $true; $ui.ActBoost.Value = [int]$active.Boost; $script:boostSync = $false
        $ui.ActBoostVal.Text = if ([int]$active.Boost -gt 0) { "+$($active.Boost) dB" } else { 'off' }; $ui.ActBoostRow.Visibility = 'Visible'
    } else {
        $ui.ActBoostRow.Visibility = 'Collapsed'
        $ui.ActName.Text = 'Aucun profil actif'; $ui.ActSub.Text = 'Crée ton premier profil avec « Nouveau profil ».'; $ui.ActChips.Children.Clear()
        $ui.BtnEditProfile.IsEnabled = $false; $ui.BtnDelProfile.IsEnabled = $false; $ui.BtnGameSettings.IsEnabled = $false
    }
    $ui.ProfList.Children.Clear()
    foreach ($p in $script:Profiles) {
        $on = $active -and $p.Name -eq $active.Name
        $b = New-Object Windows.Controls.Border; $b.Width = 262; $b.Margin = '0,0,14,14'; $b.Padding = '18,16'; $b.CornerRadius = 18; $b.Cursor = 'Hand'
        $b.Background = Brush $(if ($on) { '#2A1411' } else { '#1A0F0E' }); $b.BorderThickness = 1; $b.BorderBrush = Brush $(if ($on) { '#FF5236' } else { '#3A2420' }); $b.Tag = $p.Name
        $sp = New-Object Windows.Controls.StackPanel
        $top = New-Object Windows.Controls.Grid
        $n = New-Object Windows.Controls.TextBlock; $n.Text = $p.Phone; $n.FontSize = 15; $n.FontWeight = 'Bold'; $n.TextTrimming = 'CharacterEllipsis'; $n.Margin = '0,0,58,0'
        [void]$top.Children.Add($n)
        if ($on) { $badge = New-Chip 'ACTIF' $true; $badge.HorizontalAlignment = 'Right'; $badge.Margin = '0'; $badge.Padding = '8,2'; [void]$top.Children.Add($badge) }
        [void]$sp.Children.Add($top)
        $s = New-Object Windows.Controls.TextBlock; $s.Text = "$($p.Game) $($p.Ver)  ·  $(Fam-Name $p.Family)"; $s.Foreground = Brush '#B3A5A2'; $s.FontSize = 13; $s.Margin = '0,4,0,10'
        [void]$sp.Children.Add($s)
        $s2 = New-Object Windows.Controls.TextBlock; $s2.Text = "Arme $(Gun-Name $p.Gun)  ·  $($p.Hrir)  ·  $(if ([int]$p.Boost -gt 0) { "+$($p.Boost) dB" } else { 'boost off' })"; $s2.Foreground = Brush '#8E7F7B'; $s2.FontSize = 12
        [void]$sp.Children.Add($s2)
        $b.Child = $sp
        $b.Add_MouseEnter({ param($s) if ($s.BorderBrush.Color -ne [Windows.Media.Color]::FromRgb(255, 82, 54)) { $s.BorderBrush = Brush '#7A3426' } })
        $b.Add_MouseLeave({ param($s) $st2 = Get-State; $s.BorderBrush = Brush $(if ($s.Tag -eq $st2.Active) { '#FF5236' } else { '#3A2420' }) })
        $b.Add_MouseLeftButtonUp({ param($s) Activate-Profile $s.Tag })
        [void]$ui.ProfList.Children.Add($b)
    }
    Update-StatusBar
}
function Set-Status([string]$t, [bool]$err = $false) { $ui.PresetStatus.Foreground = Brush $(if ($err) { '#FF5236' } else { '#FF7A5C' }); $ui.PresetStatus.Text = $t }
function Activate-Profile([string]$name) {
    $p = $script:Profiles | Where-Object { $_.Name -eq $name } | Select-Object -First 1; if (-not $p) { return }
    try {
        if (-not (Ensure-ConfigHooks)) { throw "config.txt n'a pas de section 16ch (fais d'abord l'étape 1)." }
        $eq = Join-Path $Lib "$($p.Game)\$($p.Ver)\eq\$($p.EqName)"
        if (-not (Test-Path $eq) -and $p.PhoneFile) {
            Set-Status "Création de l'EQ $($p.Phone) pour $($p.Game) $($p.Ver)..."; $win.Cursor = 'Wait'; Pump
            $eq = New-HeadphoneEq $p.Phone $p.PhoneFile $p.Game $p.Ver
        }
        $t = Apply-Selection $p.Game $p.Ver $p.Family $p.Gun $p.Hrir $eq ([int]$p.Boost)
        $st = Get-State; $st.Active = $p.Name; if ($p.PhoneFile) { $st.Phone = "$($p.Phone)|$($p.PhoneFile)" }; Save-State $st
        Render-Profiles
        Set-Status "Profil « $($p.Name) » appliqué sur Art Tune +."
    } catch { Set-Status "Erreur : $($_.Exception.Message)" $true }
    finally { $win.Cursor = $null }
}
function Load-Presets {
    $script:Tunes = @(Get-Tunes); $script:state = Get-State
    Sync-PersonalEq; Ensure-DbExtras
    Load-Profiles; Seed-Profile; Render-Profiles
}

# ---- Assistant
$script:wz = @{}
function New-Tile([string]$title, [string]$desc, $tag, [bool]$sel, [scriptblock]$onClick, [double]$w = 0) {
    $b = New-Object Windows.Controls.Border; $b.CornerRadius = 14; $b.Padding = $(if ($desc) { '16,12' } else { '16,10' }); $b.Margin = '0,0,10,10'; $b.Cursor = 'Hand'
    if ($w) { $b.Width = $w }
    $b.Background = Brush $(if ($sel) { '#2E1512' } else { '#1C1110' }); $b.BorderThickness = 1; $b.BorderBrush = Brush $(if ($sel) { '#FF5236' } else { '#3A2420' })
    $sp = New-Object Windows.Controls.StackPanel
    $t = New-Object Windows.Controls.TextBlock; $t.Text = $title; $t.FontSize = 14; $t.FontWeight = 'SemiBold'; $t.Foreground = Brush $(if ($sel) { '#FFFFFF' } else { '#E6D9D6' })
    [void]$sp.Children.Add($t)
    if ($desc) { $d = New-Object Windows.Controls.TextBlock; $d.Text = $desc; $d.FontSize = 12; $d.Foreground = Brush '#9C8C88'; $d.TextWrapping = 'Wrap'; $d.Margin = '0,3,0,0'; [void]$sp.Children.Add($d) }
    $b.Child = $sp; $b.Tag = $tag; $b.Add_MouseLeftButtonUp($onClick)
    $b
}
function Wz-Set($sets) {
    $g, $v = $script:wz.Game -split '\|'
    @($script:Tunes | Where-Object { $_.Game -eq $g -and $_.Ver -eq $v })
}
function Wz-Phones {
    $q = "$($ui.WzSearch.Text)".Trim()
    $ui.WzPhones.Children.Clear()
    $g, $v = $script:wz.Game -split '\|'
    # EQ deja installes pour ce jeu
    $local = @(Get-ChildItem (Join-Path $Lib "$g\$v\eq") -Filter *.txt -ErrorAction SilentlyContinue | ForEach-Object { [pscustomobject]@{ Label = (Eq-Label $_.Name); File = ''; EqName = $_.Name } })
    $rows = @($local | Where-Object { -not $q -or $_.Label -like "*$q*" })
    $have = @($local.Label)
    if ($script:Phones) { $rows += @($script:Phones | Where-Object { $have -notcontains $_.Label -and (-not $q -or $_.Label -like "*$q*") } | Select-Object -First 60 | ForEach-Object { [pscustomobject]@{ Label = $_.Label; File = $_.File; EqName = '' } }) }
    foreach ($r in $rows) {
        $sel = $script:wz.Phone -eq $r.Label
        $b = New-Object Windows.Controls.Border; $b.CornerRadius = 12; $b.Padding = '16,11'; $b.Margin = '0,0,0,6'; $b.Cursor = 'Hand'; $b.Tag = $r
        $b.Background = Brush $(if ($sel) { '#2E1512' } else { '#1C1110' }); $b.BorderThickness = 1; $b.BorderBrush = Brush $(if ($sel) { '#FF5236' } else { '#2E1C19' })
        $gr = New-Object Windows.Controls.Grid
        $t = New-Object Windows.Controls.TextBlock; $t.Text = $r.Label; $t.FontSize = 14; $t.FontWeight = 'SemiBold'; $t.VerticalAlignment = 'Center'
        [void]$gr.Children.Add($t)
        $tag = if ($r.EqName -eq 'Flat_EQ.txt') { 'Plat' } elseif ($r.EqName) { 'EQ installé' } else { 'squig.link' }
        $c = New-Chip $tag ($tag -eq 'EQ installé'); $c.Margin = '0'; $c.HorizontalAlignment = 'Right'; [void]$gr.Children.Add($c)
        $b.Child = $gr
        $b.Add_MouseLeftButtonUp({ param($s) $script:wz.Phone = $s.Tag.Label; $script:wz.PhoneFile = $s.Tag.File; $script:wz.EqName = $s.Tag.EqName; Wz-Phones })
        [void]$ui.WzPhones.Children.Add($b)
    }
    if (-not $rows.Count) { $t = New-Object Windows.Controls.TextBlock; $t.Text = $(if ($script:Phones) { "Aucun modèle trouvé pour « $q »." } else { 'squig.link injoignable : seuls les EQ installés sont proposés.' }); $t.Foreground = Brush '#9C8C88'; $t.Margin = '4,8'; [void]$ui.WzPhones.Children.Add($t) }
}
function Wz-Options {
    foreach ($pn in 'WzGames', 'WzFams', 'WzGuns', 'WzHrirs') { $ui[$pn].Children.Clear() }
    $games = $script:Tunes | Select-Object Game, Ver -Unique | Sort-Object Game, @{ e = { [int]($_.Ver -replace '\D') }; Descending = $true }
    foreach ($x in $games) { $k = "$($x.Game)|$($x.Ver)"; [void]$ui.WzGames.Children.Add((New-Tile "$($x.Game)  $($x.Ver)" '' $k ($k -eq $script:wz.Game) { param($s) $script:wz.Game = $s.Tag; Wz-Options })) }
    $set = Wz-Set
    $fams = @($set.Family | Select-Object -Unique | Sort-Object { $i = $FamOrder.IndexOf($_); if ($i -lt 0) { 99 } else { $i } })
    if ($fams -notcontains $script:wz.Family) { $script:wz.Family = if ($fams -contains 'TheaterClear') { 'TheaterClear' } else { $fams[0] } }
    foreach ($f in $fams) { [void]$ui.WzFams.Children.Add((New-Tile (Fam-Name $f) $FamDesc[$f] $f ($f -eq $script:wz.Family) { param($s) $script:wz.Family = $s.Tag; Wz-Options })) }
    $guns = @($set.Gun | Select-Object -Unique | Sort-Object { $GunOrder.IndexOf($_) })
    if ($guns -notcontains $script:wz.Gun) { $script:wz.Gun = if ($guns -contains 'UltraLo') { 'UltraLo' } else { $guns[0] } }
    foreach ($x in $guns) { [void]$ui.WzGuns.Children.Add((New-Tile (Gun-Name $x) '' $x ($x -eq $script:wz.Gun) { param($s) $script:wz.Gun = $s.Tag; Wz-Options })) }
    $hr = @($set.Hrir | Select-Object -Unique | Sort-Object)
    if ($hr -notcontains $script:wz.Hrir) { $script:wz.Hrir = if ($hr -contains 'KU100') { 'KU100' } else { $hr[0] } }
    foreach ($x in $hr) { [void]$ui.WzHrirs.Children.Add((New-Tile $x '' $x ($x -eq $script:wz.Hrir) { param($s) $script:wz.Hrir = $s.Tag; Wz-Options })) }
}
function Wz-Step([int]$n) {
    $script:wz.Step = $n
    $ui.WzStep1.Visibility = $(if ($n -eq 1) { 'Visible' } else { 'Collapsed' })
    $ui.WzStep2.Visibility = $(if ($n -eq 2) { 'Visible' } else { 'Collapsed' })
    $ui.WzStep3.Visibility = $(if ($n -eq 3) { 'Visible' } else { 'Collapsed' })
    $ed = [bool]$script:wz.Edit
    # En modification : pas de choix du casque ni du jeu (un autre casque = un autre profil), 2 etapes seulement
    $ui.WzBar1.Visibility = $(if ($ed) { 'Collapsed' } else { 'Visible' })
    $cols = $ui.WzBar1.Parent.ColumnDefinitions
    $cols[0].Width = $(if ($ed) { '0' } else { '*' }); $cols[1].Width = $(if ($ed) { '0' } else { '8' })
    $ui.WzGameLbl.Visibility = $(if ($ed) { 'Collapsed' } else { 'Visible' }); $ui.WzGames.Visibility = $ui.WzGameLbl.Visibility
    for ($i = 1; $i -le 3; $i++) { $ui["WzBar$i"].Background = Brush $(if ($i -le $n) { '#FF5236' } else { '#3A2420' }) }
    $ui.WzKicker.Text = if ($ed) { "MODIFIER LE PROFIL  ·  ÉTAPE $($n - 1) / 2" } else { "NOUVEAU PROFIL  ·  ÉTAPE $n / 3" }
    $ui.WzBack.Visibility = $(if ($n -gt 1 -and -not ($ed -and $n -eq 2)) { 'Visible' } else { 'Collapsed' })
    $ui.WzNext.Content = $(if ($n -eq 3) { 'Créer et activer' } else { 'Suivant' }); if ($n -eq 3 -and $script:wz.Edit) { $ui.WzNext.Content = 'Enregistrer et activer' }
    $ui.WzMsg.Text = ''
    if ($n -eq 1) { Wz-Phones; $ui.WzSearch.Focus() | Out-Null }
    if ($n -eq 2) { Wz-Options }
    if ($n -eq 3) {
        $g, $v = $script:wz.Game -split '\|'
        if (-not $script:wz.NameTouched) { $ui.WzName.Text = "$($script:wz.Phone)  ·  $g $v" }
        Wz-Summary
    }
}
function Wz-Summary {
    $g, $v = $script:wz.Game -split '\|'; $bv = [int]$ui.WzBoost.Value
    $src = if ($script:wz.EqName) { 'EQ installé' } else { 'EQ créé depuis squig.link (target ArtIsWar)' }
    $ui.WzSummary.Text = "Casque : $($script:wz.Phone)  ($src)`nJeu : $g $v`nStyle : $(Fam-Name $script:wz.Family)   ·   Arme : $(Gun-Name $script:wz.Gun)   ·   HRIR : $($script:wz.Hrir)`nBoost : $(if ($bv) { "+$bv dB" } else { 'off' })"
}
function Open-Wizard($edit) {
    $st = Get-State
    $script:wz = @{ Edit = $edit; NameTouched = $false }
    if ($edit) {
        $script:wz.Game = "$($edit.Game)|$($edit.Ver)"; $script:wz.Family = $edit.Family; $script:wz.Gun = $edit.Gun; $script:wz.Hrir = $edit.Hrir
        $script:wz.Phone = $edit.Phone; $script:wz.PhoneFile = $edit.PhoneFile; $script:wz.EqName = $edit.EqName; $ui.WzBoost.Value = [int]$edit.Boost
        # Nom automatique (casque · jeu) : il suit les nouveaux choix ; un nom personnalise est garde
        $ui.WzName.Text = $edit.Name; $script:wz.NameTouched = ($edit.Name -ne "$($edit.Phone)  ·  $($edit.Game) $($edit.Ver)")
    } else {
        $script:wz.Game = if ($st.Game) { $st.Game } else { ($script:Tunes | Select-Object -First 1 | ForEach-Object { "$($_.Game)|$($_.Ver)" }) }
        $script:wz.Family = 'TheaterClear'; $script:wz.Gun = 'UltraLo'; $script:wz.Hrir = 'KU100'; $ui.WzBoost.Value = 0; $ui.WzName.Text = ''
    }
    $ui.WzSearch.Text = ''
    $ui.Wizard.Visibility = 'Visible'
    if ($edit) { Wz-Step 2; return }
    if (-not $script:Phones) { $ui.WzMsg.Text = 'Chargement de la liste squig.link...'; Pump; try { $script:Phones = @(Get-SquigPhones | Sort-Object Label) } catch {} }
    Wz-Step 1
}
$ui.BtnNewProfile.Add_Click({ if (-not $script:Tunes.Count) { Set-Status "Installe d'abord la bibliothèque (étape 1)." $true; return }; Open-Wizard $null })
# ---- Reglages en jeu (d'apres library\COD_SETTINGS.md d'ArtIsWar)
function Get-GameSettings([string]$game, [string]$ver) {
    $dev = if ($game -eq 'MW4' -or [int]($ver -replace '\D') -ge 5) { 'Art Tune +' } else { 'Art Tune' }
    if ($game -eq 'MW4') {
        return @(
            @('Game Sound Device', $dev, 'req'), @('Speaker Output', 'Windows Default', 'req'), @('Audio Mix', 'Headphones', 'rec'),
            @('Enhanced Headphone Mode', 'OFF', 'req'), @('Asymmetrical Hearing Compensation', 'OFF', ''),
            @('Master Volume', '100', ''), @('Effects Volume', '100', ''), @('Dialog Volume', '100', 'flex'),
            @('Voice Chat Output Device', 'Ton casque habituel', 'req'))
    }
    @(
        @('Game Sound Device', $dev, 'req'), @('Speaker Output', 'Windows Default', 'req'), @('Audio Mix', 'Headphones Bass Cut', 'rec'),
        @('Enhanced Headphone Mode', 'OFF', 'req'), @('Mono Audio', 'OFF', 'req'), @('Asymmetrical Hearing Compensation', 'OFF', ''),
        @('Master Volume', '100', ''), @('Effects Volume', '100', ''), @('Dialog Volume', '100', 'flex'),
        @('Music / Menu Music Volume', '0', 'rec'), @('Voice Chat Output Device', 'Ton casque habituel', 'req'))
}
function Show-GameSettings {
    $st = Get-State; $p = $script:Profiles | Where-Object { $_.Name -eq $st.Active } | Select-Object -First 1; if (-not $p) { return }
    $names = @{ MW4 = 'Modern Warfare 4 / Warzone'; BO7 = 'Black Ops 7 / Warzone'; BO6 = 'Black Ops 6'; 'PS5-BO6' = 'Black Ops 6 (PS5)'; BF6 = 'Battlefield 6' }
    $ui.GsTitle.Text = "Dans $(if ($names[$p.Game]) { $names[$p.Game] } else { $p.Game })"
    $ui.GsSub.Text = "Pour le profil « $($p.Name) ». Onglet Audio du jeu."
    $ui.GsList.Children.Clear()
    foreach ($r in (Get-GameSettings $p.Game $p.Ver)) {
        $b = New-Object Windows.Controls.Border; $b.CornerRadius = 10; $b.Padding = '14,5'; $b.Margin = '0,0,0,4'; $b.MinHeight = 40; $b.BorderThickness = 1
        $b.Background = Brush '#1C1110'; $b.BorderBrush = Brush $(if ($r[2] -eq 'req') { '#4A2219' } else { '#2E1C19' })
        $g = New-Object Windows.Controls.Grid
        $c1 = New-Object Windows.Controls.ColumnDefinition; $c2 = New-Object Windows.Controls.ColumnDefinition; $c2.Width = 'Auto'; $c3 = New-Object Windows.Controls.ColumnDefinition; $c3.Width = '118'
        $g.ColumnDefinitions.Add($c1); $g.ColumnDefinitions.Add($c2); $g.ColumnDefinitions.Add($c3)
        $t = New-Object Windows.Controls.TextBlock; $t.Text = $r[0]; $t.FontSize = 14; $t.Foreground = Brush '#D9CCC9'; $t.VerticalAlignment = 'Center'; [void]$g.Children.Add($t)
        $v = New-Object Windows.Controls.TextBlock; $v.Text = $r[1]; $v.FontSize = 14; $v.FontWeight = 'Bold'; $v.VerticalAlignment = 'Center'; $v.Margin = '12,0,12,0'
        $v.Foreground = Brush $(if ($r[2] -eq 'req') { '#FFFFFF' } else { '#E6D9D6' }); [Windows.Controls.Grid]::SetColumn($v, 1); [void]$g.Children.Add($v)
        $lbl = switch ($r[2]) { 'req' { 'Obligatoire' } 'rec' { 'Conseillé' } 'flex' { 'Au choix' } default { '' } }
        if ($lbl) { $c = New-Chip $lbl ($r[2] -eq 'req'); $c.Margin = '0'; $c.HorizontalAlignment = 'Right'; [Windows.Controls.Grid]::SetColumn($c, 2); [void]$g.Children.Add($c) }
        $b.Child = $g; [void]$ui.GsList.Children.Add($b)
    }
    $ui.GameOverlay.Visibility = 'Visible'
}
$ui.BtnGameSettings.Add_Click({ Show-GameSettings })
$ui.GsClose.Add_Click({ $ui.GameOverlay.Visibility = 'Collapsed' })
$ui.BtnEditProfile.Add_Click({ $st = Get-State; $p = $script:Profiles | Where-Object { $_.Name -eq $st.Active } | Select-Object -First 1; if ($p) { Open-Wizard $p } })
$ui.BtnDelProfile.Add_Click({
    $st = Get-State; $p = $script:Profiles | Where-Object { $_.Name -eq $st.Active } | Select-Object -First 1; if (-not $p) { return }
    if ((Show-Msg "Supprimer le profil « $($p.Name) » ?`nLe son actuel reste appliqué." 'YesNo' 'Warning' @{ Yes = 'Supprimer'; No = 'Annuler' }) -ne 'Yes') { return }
    $script:Profiles = @($script:Profiles | Where-Object { $_.Name -ne $p.Name }); Save-Profiles
    $st.Remove('Active'); Save-State $st; Render-Profiles; Set-Status "Profil supprimé."
})
# Boost rapide du profil actif : appliquer quand on relache le curseur (E-APO recharge boost.txt en direct)
$ui.ActBoost.Add_ValueChanged({ $v = [int]$ui.ActBoost.Value; $ui.ActBoostVal.Text = if ($v -eq 0) { 'off' } else { "+$v dB" } })
$applyBoost = {
    if ($script:boostSync) { return }
    $st = Get-State; $p = $script:Profiles | Where-Object { $_.Name -eq $st.Active } | Select-Object -First 1; if (-not $p) { return }
    $v = [int]$ui.ActBoost.Value; if ([int]$p.Boost -eq $v) { return }
    try {
        [IO.File]::WriteAllText($BoostF, "# ArtTuneDB Output Boost -- set your dB below and save. 0 dB = off.`r`n# config.txt includes this last on every chain; E-APO reloads it live.`r`nPreamp: $v dB`r`n")
        $p.Boost = $v; Save-Profiles; Render-Profiles
        Set-Status $(if ($v) { "Boost +$v dB appliqué." } else { 'Boost désactivé.' })
    } catch { Set-Status "Erreur : $($_.Exception.Message)" $true }
}
$ui.ActBoost.Add_PreviewMouseLeftButtonUp($applyBoost)
$ui.ActBoost.Add_PreviewKeyUp($applyBoost)
$ui.WzSearch.Add_TextChanged({ if ($script:wz.Step -eq 1) { Wz-Phones } })
$ui.WzName.Add_TextChanged({ if ($ui.WzName.IsKeyboardFocused) { $script:wz.NameTouched = $true } })
$ui.WzBoost.Add_ValueChanged({ $v = [int]$ui.WzBoost.Value; $ui.WzBoostVal.Text = if ($v -eq 0) { 'off' } else { "+$v dB" }; if ($script:wz.Step -eq 3) { Wz-Summary } })
$ui.WzCancel.Add_Click({ $ui.Wizard.Visibility = 'Collapsed' })
$ui.WzBack.Add_Click({ Wz-Step ($script:wz.Step - 1) })
$ui.WzNext.Add_Click({
    $n = $script:wz.Step
    if ($n -eq 1) { if (-not $script:wz.Phone) { $ui.WzMsg.Text = 'Choisis ton casque (ou « Aucun EQ (plat) »).'; return }; Wz-Step 2; return }
    if ($n -eq 2) { Wz-Step 3; return }
    $name = "$($ui.WzName.Text)".Trim(); if (-not $name) { $ui.WzMsg.Text = 'Donne un nom au profil.'; return }
    $old = if ($script:wz.Edit) { $script:wz.Edit.Name } else { $null }
    if ($script:Profiles | Where-Object { $_.Name -eq $name -and $_.Name -ne $old }) { $ui.WzMsg.Text = 'Un profil porte déjà ce nom.'; return }
    $g, $v = $script:wz.Game -split '\|'
    $eqName = $script:wz.EqName
    if (-not $eqName) {
        # EQ squig.link : le nom de fichier est celui que New-HeadphoneEq produira
        $eqName = "$(($script:wz.Phone -replace '[\\/:*?""<>|]', '-').Trim()) - $g$v.txt"
    } elseif (-not (Test-Path (Join-Path $Lib "$g\$v\eq\$eqName"))) {
        $same = Get-ChildItem (Join-Path $Lib "$g\$v\eq") -Filter "$($script:wz.Phone)*.txt" -ErrorAction SilentlyContinue | Select-Object -First 1
        $eqName = if ($same) { $same.Name } else { 'Flat_EQ.txt' }
    }
    $p = [pscustomobject]@{ Name = $name; Game = $g; Ver = $v; Family = $script:wz.Family; Gun = $script:wz.Gun; Hrir = $script:wz.Hrir
        Phone = $script:wz.Phone; PhoneFile = "$($script:wz.PhoneFile)"; EqName = $eqName; Boost = [int]$ui.WzBoost.Value }
    $script:Profiles = @($script:Profiles | Where-Object { $_.Name -ne $old }) + $p
    try { Save-Profiles } catch { $ui.WzMsg.Text = "Enregistrement impossible : $($_.Exception.Message)"; return }
    $ui.Wizard.Visibility = 'Collapsed'
    Activate-Profile $name
})

# ---------------------------------------------------------------- 5. Mises a jour
$script:release = $null
function Update-Side { $v = Get-LocalVersion; $ui.SideVer.Text = $(if ($v) { $v } else { 'Non installée' }) }
function Check-Updates {
    $loc = Get-LocalVersion; $script:release = Get-RemoteRelease
    $ui.VerLocal.Text = if ($loc) { $loc } else { 'aucune' }
    if (-not $script:release) { $ui.VerRemote.Text = '?'; $ui.UpSummary.Text = "Impossible de joindre GitHub / artiswar.io."; $ui.SideVerSub.Text = 'Hors ligne'; return }
    $ui.VerRemote.Text = $script:release.Version
    $new = $script:release.Version -ne $loc
    $ui.UpSummary.Text = if ($new) { "Nouvelle version disponible sur $($script:release.Source)." } else { "Tu es à jour ($($script:release.Source))." }
    $ui.SideVerSub.Text = if ($new) { "Mise à jour dispo : $($script:release.Version)" } else { 'À jour' }
    $ui.BtnUpdate.Content = if ($new) { "Mettre à jour vers $($script:release.Version)" } else { "Réinstaller $($script:release.Version)" }
    if ($script:release.Notes) { $ui.UpLog.Text = "Notes de version`r`n`r`n" + ($script:release.Notes -replace "`r?`n", "`r`n") }
    $new
}
$ui.BtnCheckUp.Add_Click({ try { [void](Check-Updates) } catch { $ui.UpLog.Text = "Erreur : $($_.Exception.Message)" } })
$ui.BtnUpdate.Add_Click({
    if (-not $script:release) { return }
    $ui.BtnUpdate.IsEnabled = $false; $ui.UpLog.Clear(); $win.Cursor = 'Wait'
    try {
        Update-Library $script:release { param($m) LogTo $ui.UpLog $m }
        Load-Presets; Update-Side; [void](Check-Updates)
    } catch { LogTo $ui.UpLog "Erreur : $($_.Exception.Message)"; LogTo $ui.UpLog "L'ancienne bibliotheque est conservee dans ArtTuneDB\library-previous-*." }
    finally { $win.Cursor = $null; $ui.BtnUpdate.IsEnabled = $true }
})
# ---- Mise a jour de Tune Manager lui-meme
#  1. GitHub : derniere Release du depot prive (repo.txt), avec un jeton d'acces
#  2. Secours (developpement) : l'installeur local d'origine a ete recompile depuis
$GhTokF = Join-Path $env:APPDATA 'TuneManager\github.token'
function Get-GitHubToken {
    try { if (Test-Path $GhTokF) { $ss = ConvertTo-SecureString ([IO.File]::ReadAllText($GhTokF).Trim()); return [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($ss)) } } catch {}
    try { $gh = Get-Command gh.exe -ErrorAction Stop; $t = (& $gh.Source auth token 2>$null | Select-Object -First 1); if ($t) { return "$t".Trim() } } catch {}
    $null
}
function Save-GitHubToken([string]$t) {
    New-Item -ItemType Directory (Split-Path $GhTokF) -Force | Out-Null
    if ($t) { [IO.File]::WriteAllText($GhTokF, (ConvertTo-SecureString $t -AsPlainText -Force | ConvertFrom-SecureString)) } else { Remove-Item $GhTokF -ErrorAction SilentlyContinue }
}
function Get-GitHubRelease {
    if (-not $AppRepo) { throw "Aucun dépôt GitHub configuré (repo.txt)." }
    $tok = Get-GitHubToken; if (-not $tok) { throw "Pas de jeton GitHub : renseigne-le dans Paramètres." }
    $h = @{ Authorization = "Bearer $tok"; 'User-Agent' = 'TuneManager'; Accept = 'application/vnd.github+json' }
    $r = Invoke-RestMethod "https://api.github.com/repos/$AppRepo/releases/latest" -Headers $h -TimeoutSec 15
    $asset = $r.assets | Where-Object { $_.name -like '*Setup*.exe' } | Select-Object -First 1
    [pscustomobject]@{ Version = ($r.tag_name -replace '^v', ''); Notes = $r.body; AssetUrl = $asset.url; Published = ([datetime]$r.published_at).ToLocalTime() }
}
function Test-NewerVersion([string]$a, [string]$b) { try { return ([version]$a -gt [version]$b) } catch { return $a -ne $b } }
function Get-AppUpdate {
    if ($env:TM_NOELEVATE -and -not $env:TM_UPDTEST) { return $null }
    $installed = $false; try { $installed = (Resolve-Path $PSScriptRoot).Path.TrimEnd('\') -eq $AppDir.TrimEnd('\') } catch {}
    if (-not $installed -and -not $env:TM_UPDTEST) { return $null }
    try {
        $rel = Get-GitHubRelease
        if ($rel.AssetUrl -and (Test-NewerVersion $rel.Version $AppVer)) {
            return [pscustomobject]@{ Source = 'github'; Version = $rel.Version; AssetUrl = $rel.AssetUrl; Notes = $rel.Notes; New = $rel.Published }
        }
    } catch { $script:ghUpdError = $_.Exception.Message }
    try {
        $k = Get-ItemProperty $AppUninst -ErrorAction Stop
        if ($k.SetupPath -and (Test-Path $k.SetupPath)) {
            $f = Get-Item $k.SetupPath; $old = [long]$k.SetupStamp
            if ($f.LastWriteTimeUtc.Ticks -gt $old + [TimeSpan]::TicksPerSecond) {
                return [pscustomobject]@{ Source = 'local'; Version = ''; Path = $f.FullName; New = $f.LastWriteTime; Old = ([datetime]::new($old, 'Utc')).ToLocalTime() }
            }
        }
    } catch {}
    $null
}
function Show-AppUpdate([bool]$manual = $false) {
    $u = Get-AppUpdate
    if (-not $u) { if ($manual) { Set-Status $(if ($script:ghUpdError) { "Vérification GitHub impossible : $($script:ghUpdError)" } else { "Tune Manager est à jour (version $AppVer)." }) ([bool]$script:ghUpdError) }; return }
    $script:appUpdate = $u
    $notes = if ($u.Notes) { "`n`nNouveautés :`n" + (($u.Notes -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 6) -join "`n") } else { '' }
    $ui.UpdText.Text = if ($u.Source -eq 'github') {
        "La version $($u.Version) est disponible (tu as la $AppVer).$notes`n`nLa mise à jour prend quelques secondes : Tune Manager se ferme puis se relance tout seul. Tes profils et tes EQ sont conservés."
    } else {
        "Une version plus récente est prête (compilée le $($u.New.ToString('dd/MM/yyyy à HH:mm'))). Ta version date du $($u.Old.ToString('dd/MM/yyyy à HH:mm')).`n`nLa mise à jour prend quelques secondes : Tune Manager se ferme puis se relance tout seul. Tes profils et tes EQ sont conservés."
    }
    $ui.UpdOverlay.Visibility = 'Visible'
}
$ui.UpdLater.Add_Click({ $ui.UpdOverlay.Visibility = 'Collapsed' })
$ui.UpdNow.Add_Click({
    try {
        $u = $script:appUpdate; $exe = $u.Path
        if ($u.Source -eq 'github') {
            $ui.UpdText.Text = "Téléchargement de la version $($u.Version)..."; $win.Cursor = 'Wait'; Pump
            $exe = Join-Path $env:TEMP "TuneManagerSetup-$($u.Version).exe"
            $h = @{ Authorization = "Bearer $(Get-GitHubToken)"; 'User-Agent' = 'TuneManager'; Accept = 'application/octet-stream' }
            Invoke-WebRequest $u.AssetUrl -Headers $h -OutFile $exe -UseBasicParsing -TimeoutSec 300
            if ((Get-Item $exe).Length -lt 100KB) { throw "Téléchargement incomplet." }
            Unblock-File $exe -ErrorAction SilentlyContinue
        }
        Start-Process $exe '/update'
        $script:quitting = $true; $win.Close()
    } catch { $win.Cursor = $null; $ui.UpdOverlay.Visibility = 'Collapsed'; Set-Status "Mise à jour impossible : $($_.Exception.Message)" $true }
})
# Parametres : jeton GitHub et verification manuelle
$ui.AppVerText.Text = "Version installée : $AppVer$(if ($AppRepo) { "  ·  dépôt $AppRepo" })"
$ui.GhTokenState.Text = if (Test-Path $GhTokF) { 'Jeton enregistré (chiffré pour ton compte Windows).' } elseif (Get-Command gh.exe -ErrorAction SilentlyContinue) { 'Jeton fourni par GitHub CLI (gh).' } else { 'Aucun jeton : colle un jeton GitHub en lecture seule.' }
$ui.BtnGhSave.Add_Click({
    try { Save-GitHubToken $ui.GhToken.Password.Trim(); $ui.GhToken.Clear(); $ui.GhTokenState.Text = if (Test-Path $GhTokF) { 'Jeton enregistré (chiffré pour ton compte Windows).' } else { 'Jeton supprimé.' } }
    catch { $ui.GhTokenState.Text = "Erreur : $($_.Exception.Message)" }
})
$ui.BtnAppUpd.Add_Click({ $win.Cursor = 'Wait'; Pump; try { Show-AppUpdate $true } finally { $win.Cursor = $null } })
$ui.ChkStartup.IsChecked = Test-StartupTask
$ui.ChkStartup.Add_Click({ try { Register-StartupTask ([bool]$ui.ChkStartup.IsChecked) } catch { LogTo $ui.UpLog "Erreur démarrage avec Windows : $($_.Exception.Message)"; $ui.ChkStartup.IsChecked = Test-StartupTask } })
$ui.ChkCloseTray.IsChecked = [bool](Get-UiPref 'CloseToTray' $true)
$ui.ChkCloseTray.Add_Click({ Set-UiPref 'CloseToTray' ([bool]$ui.ChkCloseTray.IsChecked) })
$ui.ChkAuto.IsChecked = Test-UpdateTask
$ui.ChkAuto.Add_Click({ try { Register-UpdateTask ([bool]$ui.ChkAuto.IsChecked) } catch { LogTo $ui.UpLog "Erreur tache planifiee : $($_.Exception.Message)" } })

# ---------------------------------------------------------------- Demarrage
$win.Add_ContentRendered({
    Pump
    try { Load-Presets } catch {}
    Update-Side
    try { Show-Diag } catch {}
    $new = $false; try { $new = Check-Updates } catch {}
    if (-not (Test-Path "C:\Program Files\EqualizerAPO\EqualizerAPO.dll")) { Show-Page 0 }
    elseif ($new) { Show-Page 4 }
    elseif ($script:Tunes.Count -and (Test-Path $TuneF)) { Show-Page 3 }
    else { Show-Page 1 }
    if ($env:TM_SNAPUPD) { $script:appUpdate = [pscustomobject]@{ Path = ''; New = (Get-Date); Old = (Get-Date).AddHours(-1) }; $ui.UpdText.Text = "Une version plus récente est prête (compilée le $((Get-Date).ToString('dd/MM/yyyy à HH:mm'))). Ta version date du $((Get-Date).AddHours(-1).ToString('dd/MM/yyyy à HH:mm')).`n`nLa mise à jour prend quelques secondes : Tune Manager se ferme puis se relance tout seul. Tes profils et tes EQ sont conservés."; $ui.UpdOverlay.Visibility = 'Visible' }
    else { Show-AppUpdate }
})
$ui.Nav3.IsChecked = $true
# Mode demo ($env:TM_DEMO=1) : simule une installation complete pour voir les animations, sans rien installer
if ($env:TM_DEMO) {
    $win.Add_ContentRendered({
        $script:jobKind = 'install'; Show-Page 0; Show-InstallProgress; Set-Dots 0 $false
        $ui.WarnBanner.Visibility = 'Visible'; $ui.InstTitle.Text = 'Installation en cours (d' + [char]0xE9 + 'mo)'; $ui.InstSub.Text = 'Simulation : rien n''est install' + [char]0xE9 + ' ni modifi' + [char]0xE9 + '.'
        $script:demoPct = 0.0
        $script:demoTimer = New-Object Windows.Threading.DispatcherTimer; $script:demoTimer.Interval = [TimeSpan]::FromMilliseconds(250)
        $script:demoTimer.Add_Tick({ try {
            $script:demoPct = [Math]::Min(100.0, $script:demoPct + 0.45)
            $stp = [Math]::Min(10, [int][Math]::Floor($script:demoPct / 10) + 1); $done = $script:demoPct -ge 100
            $p = @{ Pct = [int]$script:demoPct; Msg = $(if ($done) { 'Termine (demo)' } else { "$($StepNames[$stp - 1]) (demo)" }); Step = $stp; Done = $false; Error = $null; Log = @("Demo : aucune modification n'est faite sur le PC.") }
            $ui.CurTask.Text = $p.Msg; Set-Bar $p.Pct; Set-Dots $stp $done ((($script:demoPct - 10 * ($stp - 1)) * 10))
            if ($ui.InstLog.Text -ne $p.Log[0]) { $ui.InstLog.Text = $p.Log[0] }
            if ($done) { $script:demoTimer.Stop(); $ui.WarnBanner.Visibility = 'Collapsed'; $ui.InstTitle.Text = 'Installation termin' + [char]0xE9 + 'e (d' + [char]0xE9 + 'mo)' }
        } catch { $script:demoTimer.Stop(); "$($_.InvocationInfo.ScriptLineNumber): $_" | Out-File (Join-Path $env:PUBLIC 'tm-demo-error.txt') } })
        $script:demoTimer.Start()
    })
}
if ($env:TM_SNAP) {
    $snapT = New-Object Windows.Threading.DispatcherTimer; $snapT.Interval = [TimeSpan]::FromSeconds(7)
    $snapT.Add_Tick({ $snapT.Stop(); $rtb = New-Object Windows.Media.Imaging.RenderTargetBitmap ([int]$win.ActualWidth), ([int]$win.ActualHeight), 96, 96, ([Windows.Media.PixelFormats]::Pbgra32)
        $rtb.Render($win); $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder; $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($rtb))
        $fs = [IO.File]::Create($env:TM_SNAP); $enc.Save($fs); $fs.Close(); $script:quitting = $true; $win.Close() })
    $win.Add_ContentRendered({ $snapT.Start() })
    if ($env:TM_SNAPPAGE) { $win.Add_ContentRendered({ Show-Page ([int]$env:TM_SNAPPAGE) }) }
    if ($env:TM_SNAPWIZ -eq 'game') { $win.Add_ContentRendered({ Show-Page 3; Show-GameSettings }) }
    elseif ($env:TM_SNAPWIZ -eq 'edit') { $win.Add_ContentRendered({ Show-Page 3; Open-Wizard ($script:Profiles | Select-Object -First 1) }) }
    elseif ($env:TM_SNAPWIZ) { $win.Add_ContentRendered({ Show-Page 3; Open-Wizard $null; if ($env:TM_SNAPWIZ -match 'q=(.+)') { $ui.WzSearch.Text = $Matches[1] }; if ($env:TM_SNAPWIZ -match '^\d') { $script:wz.Phone = 'Kiwi Ears Astral'; Wz-Step ([int]$env:TM_SNAPWIZ.Substring(0,1)) } }) }
}
# Boucle de l'application : la fenetre peut etre cachee (zone de notification) sans quitter
$app = [Windows.Application]::Current; if (-not $app) { $app = New-Object Windows.Application }
$app.ShutdownMode = 'OnExplicitShutdown'
$win.Add_Closed({ $app.Shutdown() })
if ($Tray) { $win.ShowInTaskbar = $false; $win.WindowState = 'Minimized'; $win.Add_ContentRendered({ if ($Tray -and -not $script:trayShown) { $script:trayShown = $true; $win.Hide(); $win.WindowState = 'Normal' } }) }
$win.Show()
[void]$app.Run()
