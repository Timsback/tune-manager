// Tune Manager Setup.exe : installeur graphique de Tune Manager.
// Contient TuneManager.ps1, TuneManager.exe et l'icone (ressources integrees).
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Markup;
using System.Windows.Media.Imaging;
using Microsoft.Win32;

[assembly: AssemblyTitle("Tune Manager Setup")]
[assembly: AssemblyProduct("Tune Manager")]
[assembly: AssemblyDescription("Installation de Tune Manager")]
[assembly: AssemblyVersion("2.0.0.0")]
[assembly: AssemblyFileVersion("2.0.0.0")]

public static class SetupApp {
    static string Version {
        get {
            try { using (var s = Assembly.GetExecutingAssembly().GetManifestResourceStream("version.txt")) using (var r = new StreamReader(s)) return r.ReadToEnd().Trim(); }
            catch { return "2.0.0"; }
        }
    }
    static readonly string AppDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Tune Manager");
    const string UninstKey = @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\TuneManager";
    const string StartTask = "TuneManager - demarrage";
    static Window win;
    static int step = 1;

    [STAThread]
    public static void Main(string[] args) {
        // /update : mise a jour silencieuse lancee par Tune Manager (memes options, puis relance)
        if (args.Length >= 1 && args[0].ToLowerInvariant() == "/update") {
            bool cd, cs; CurrentOptions(out cd, out cs);
            try {
                Install(cd, cs, delegate (string t, double v) { });
                Process.Start(new ProcessStartInfo(Path.Combine(AppDir, "TuneManager.exe")) { UseShellExecute = true, WorkingDirectory = AppDir });
            } catch (Exception ex) {
                MessageBox.Show("Mise à jour impossible :\n" + ex.Message, "Tune Manager", MessageBoxButton.OK, MessageBoxImage.Error);
            }
            return;
        }
        var app = new Application();
        win = (Window)XamlReader.Parse(Xaml);
        try {
            var ico = Assembly.GetExecutingAssembly().GetManifestResourceStream("TuneManager.ico");
            if (ico != null) win.Icon = BitmapFrame.Create(ico);
        } catch { }
        El<TextBlock>("Path").Text = AppDir;
        bool already = File.Exists(Path.Combine(AppDir, "TuneManager.ps1"));
        El<Grid>("Title").MouseLeftButtonDown += delegate { win.DragMove(); };
        El<Button>("BClose").Click += delegate { win.Close(); };
        El<Button>("BCancel").Click += delegate { win.Close(); };
        El<Button>("BCancel0").Click += delegate { win.Close(); };
        // Deja installe : un seul ecran, Desinstaller ou Reparer (memes options qu'avant)
        El<Button>("BRepair").Click += delegate {
            bool cd, cs; CurrentOptions(out cd, out cs);
            El<TextBlock>("S3Title").Text = "Réparation...";
            El<TextBlock>("S4Title").Text = "Tune Manager est réparé";
            Show(3); RunInstall(cd, cs);
        };
        El<Button>("BUninstall").Click += delegate {
            try {
                Process.Start(new ProcessStartInfo(Path.Combine(AppDir, "TuneManager.exe"), "/uninstall") { UseShellExecute = true, WorkingDirectory = AppDir });
                win.Close();
            } catch (Exception ex) {
                MessageBox.Show(win, "Désinstallation impossible :\n" + ex.Message, "Tune Manager Setup", MessageBoxButton.OK, MessageBoxImage.Error);
            }
        };
        El<Button>("BNext").Click += delegate { Show(2); };
        El<Button>("BBack").Click += delegate { Show(1); };
        El<Button>("BInstall").Click += delegate { Show(3); RunInstall(El<CheckBox>("CDesk").IsChecked == true, El<CheckBox>("CStart").IsChecked == true); };
        El<Button>("BFinish").Click += delegate {
            if (El<CheckBox>("CLaunch").IsChecked == true) {
                try { Process.Start(new ProcessStartInfo(Path.Combine(AppDir, "TuneManager.exe")) { UseShellExecute = true, WorkingDirectory = AppDir }); } catch { }
            }
            win.Close();
        };
        bool installed = already && File.Exists(Path.Combine(AppDir, "TuneManager.exe"));
        Show(installed ? 0 : 1);
        // /snap <png> <etape> : capture de l'ecran pour verifier le rendu (developpement)
        if (args.Length >= 3 && args[0] == "/snap") {
            int st = int.Parse(args[2]); string png = args[1];
            win.ContentRendered += delegate {
                Show(st); if (st == 3) Status("Copie des fichiers...", 40);
                var tm = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromMilliseconds(800) };
                tm.Tick += delegate {
                    tm.Stop();
                    var rtb = new RenderTargetBitmap((int)win.ActualWidth, (int)win.ActualHeight, 96, 96, System.Windows.Media.PixelFormats.Pbgra32);
                    rtb.Render(win); var enc = new PngBitmapEncoder(); enc.Frames.Add(BitmapFrame.Create(rtb));
                    using (var f = File.Create(png)) enc.Save(f);
                    win.Close();
                };
                tm.Start();
            };
        }
        app.Run(win);
    }

    static T El<T>(string n) where T : class { return win.FindName(n) as T; }

    static void Show(int s) {
        step = s;
        El<Grid>("S0").Visibility = s == 0 ? Visibility.Visible : Visibility.Collapsed;
        El<StackPanel>("F0").Visibility = s == 0 ? Visibility.Visible : Visibility.Collapsed;
        El<StackPanel>("Steps").Visibility = s == 0 ? Visibility.Hidden : Visibility.Visible;
        El<Grid>("S1").Visibility = s == 1 ? Visibility.Visible : Visibility.Collapsed;
        El<Grid>("S2").Visibility = s == 2 ? Visibility.Visible : Visibility.Collapsed;
        El<Grid>("S3").Visibility = s == 3 ? Visibility.Visible : Visibility.Collapsed;
        El<Grid>("S4").Visibility = s == 4 ? Visibility.Visible : Visibility.Collapsed;
        El<StackPanel>("F1").Visibility = s == 1 ? Visibility.Visible : Visibility.Collapsed;
        El<StackPanel>("F2").Visibility = s == 2 ? Visibility.Visible : Visibility.Collapsed;
        El<StackPanel>("F4").Visibility = s == 4 ? Visibility.Visible : Visibility.Collapsed;
        El<Button>("BClose").IsEnabled = s != 3;
        for (int i = 1; i <= 4; i++) {
            var d = El<System.Windows.Shapes.Ellipse>("D" + i);
            d.Fill = (System.Windows.Media.Brush)new System.Windows.Media.BrushConverter().ConvertFromString(i <= s ? "#FF5236" : "#3A2420");
        }
    }

    static void Status(string t, double p) {
        win.Dispatcher.Invoke(new Action(delegate { El<TextBlock>("PStatus").Text = t; El<ProgressBar>("PBar").Value = p; }));
    }

    // Options de l'installation existante : raccourci bureau present, tache de demarrage presente
    static void CurrentOptions(out bool desk, out bool start) {
        desk = File.Exists(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonDesktopDirectory), "Tune Manager.lnk"));
        start = false;
        try { var p = Process.Start(new ProcessStartInfo("schtasks.exe", "/Query /TN \"" + StartTask + "\"") { UseShellExecute = false, CreateNoWindow = true }); p.WaitForExit(15000); start = p.ExitCode == 0; } catch { }
    }

    static void RunInstall(bool desk, bool start) {
        bool repair = El<TextBlock>("S3Title").Text.StartsWith("Répar");
        var t = new Thread(delegate () {
            try {
                Install(desk, start, Status);
                Thread.Sleep(400);
                win.Dispatcher.Invoke(new Action(delegate { Show(4); }));
            } catch (Exception ex) {
                win.Dispatcher.Invoke(new Action(delegate {
                    MessageBox.Show(win, (repair ? "Réparation impossible :\n" : "Installation impossible :\n") + ex.Message, "Tune Manager Setup", MessageBoxButton.OK, MessageBoxImage.Error);
                    Show(repair ? 0 : 2);
                }));
            }
        });
        t.IsBackground = true; t.Start();
    }

    static void Install(bool desk, bool start, Action<string, double> Status) {
                Status("Fermeture de Tune Manager s'il est ouvert...", 5);
                StopRunning();
                Status("Copie des fichiers...", 20);
                Directory.CreateDirectory(AppDir);
                Extract("TuneManager.ps1"); Thread.Sleep(150);
                Extract("TuneManager.exe"); Thread.Sleep(150);
                Extract("TuneManager.ico"); Extract("README.md"); Extract("version.txt"); Extract("repo.txt");
                Status("Création des raccourcis...", 55);
                string exe = Path.Combine(AppDir, "TuneManager.exe");
                string common = Environment.GetFolderPath(Environment.SpecialFolder.CommonPrograms);
                Shortcut(Path.Combine(common, "Tune Manager.lnk"), exe);
                string pubDesk = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonDesktopDirectory), "Tune Manager.lnk");
                if (desk) Shortcut(pubDesk, exe); else if (File.Exists(pubDesk)) File.Delete(pubDesk);
                // ancien raccourci personnel (version de developpement)
                string old = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), "Tune Manager.lnk");
                if (File.Exists(old)) File.Delete(old);
                Status("Enregistrement dans les applications installées...", 75);
                using (var k = Registry.LocalMachine.CreateSubKey(UninstKey)) {
                    k.SetValue("DisplayName", "Tune Manager");
                    k.SetValue("DisplayVersion", Version);
                    k.SetValue("Publisher", "Tune Manager");
                    k.SetValue("DisplayIcon", exe + ",0");
                    k.SetValue("InstallLocation", AppDir);
                    k.SetValue("UninstallString", "\"" + exe + "\" /uninstall");
                    k.SetValue("Comments", "Installation et gestion de la chaîne audio ArtTuneDB (Equalizer APO)");
                    k.SetValue("NoModify", 1, RegistryValueKind.DWord);
                    k.SetValue("NoRepair", 1, RegistryValueKind.DWord);
                    k.SetValue("EstimatedSize", DirSizeKb(AppDir), RegistryValueKind.DWord);
                    // Source des mises a jour : cet installeur et sa date de compilation
                    string me = Assembly.GetExecutingAssembly().Location;
                    k.SetValue("SetupPath", me);
                    k.SetValue("SetupStamp", File.GetLastWriteTimeUtc(me).Ticks.ToString());
                }
                Status("Démarrage avec Windows...", 88);
                if (start) Run("schtasks.exe", "/Create /F /TN \"" + StartTask + "\" /TR \"\\\"" + exe + "\\\" -Tray\" /SC ONLOGON /RL HIGHEST /DELAY 0000:20");
                else Run("schtasks.exe", "/Delete /F /TN \"" + StartTask + "\"");
                Status("Terminé", 100);
    }

    static void Extract(string name) {
        using (var s = Assembly.GetExecutingAssembly().GetManifestResourceStream(name)) {
            if (s == null) return;
            string dst = Path.Combine(AppDir, name);
            using (var f = File.Create(dst)) s.CopyTo(f);
        }
    }
    static void StopRunning() {
        try {
            var q = new System.Management.ManagementObjectSearcher("SELECT ProcessId, CommandLine FROM Win32_Process WHERE Name='powershell.exe'");
            foreach (System.Management.ManagementObject o in q.Get()) {
                var cl = o["CommandLine"] as string;
                if (cl != null && cl.IndexOf("TuneManager.ps1", StringComparison.OrdinalIgnoreCase) >= 0 && cl.IndexOf("-RunInstall", StringComparison.OrdinalIgnoreCase) < 0 && cl.IndexOf("-RunUninstall", StringComparison.OrdinalIgnoreCase) < 0) {
                    try { Process.GetProcessById(Convert.ToInt32(o["ProcessId"])).Kill(); } catch { }
                }
            }
        } catch { }
    }
    static void Shortcut(string lnk, string exe) {
        Type t = Type.GetTypeFromProgID("WScript.Shell");
        object sh = Activator.CreateInstance(t);
        object sc = t.InvokeMember("CreateShortcut", BindingFlags.InvokeMethod, null, sh, new object[] { lnk });
        Type st = sc.GetType();
        st.InvokeMember("TargetPath", BindingFlags.SetProperty, null, sc, new object[] { exe });
        st.InvokeMember("WorkingDirectory", BindingFlags.SetProperty, null, sc, new object[] { AppDir });
        st.InvokeMember("IconLocation", BindingFlags.SetProperty, null, sc, new object[] { exe + ",0" });
        st.InvokeMember("Description", BindingFlags.SetProperty, null, sc, new object[] { "Tune Manager - chaîne audio ArtTuneDB" });
        st.InvokeMember("Save", BindingFlags.InvokeMethod, null, sc, null);
    }
    static void Run(string f, string a) {
        var p = Process.Start(new ProcessStartInfo(f, a) { UseShellExecute = false, CreateNoWindow = true });
        p.WaitForExit(20000);
    }
    static int DirSizeKb(string d) { long n = 0; foreach (var f in Directory.GetFiles(d)) n += new FileInfo(f).Length; return (int)(n / 1024); }

    const string Xaml = @"
<Window xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'
        Title='Tune Manager Setup' Width='760' Height='500' WindowStyle='None' AllowsTransparency='True' Background='Transparent'
        ResizeMode='NoResize' WindowStartupLocation='CenterScreen' FontFamily='Segoe UI Variable Display, Segoe UI' Foreground='#F5EFEE'>
  <Window.Resources>
    <LinearGradientBrush x:Key='Accent' StartPoint='0,0' EndPoint='1,1'><GradientStop Color='#FF6A45' Offset='0'/><GradientStop Color='#E23A22' Offset='1'/></LinearGradientBrush>
    <Style x:Key='Primary' TargetType='Button'>
      <Setter Property='Foreground' Value='White'/><Setter Property='FontSize' Value='15'/><Setter Property='FontWeight' Value='SemiBold'/>
      <Setter Property='Height' Value='46'/><Setter Property='Padding' Value='30,0'/><Setter Property='Cursor' Value='Hand'/>
      <Setter Property='Template'><Setter.Value><ControlTemplate TargetType='Button'>
        <Border x:Name='b' CornerRadius='15' Background='{StaticResource Accent}' Padding='{TemplateBinding Padding}'>
          <Border.Effect><DropShadowEffect Color='#FF4A2E' BlurRadius='26' ShadowDepth='0' Opacity='0.55'/></Border.Effect>
          <ContentPresenter HorizontalAlignment='Center' VerticalAlignment='Center'/></Border>
        <ControlTemplate.Triggers><Trigger Property='IsMouseOver' Value='True'><Setter TargetName='b' Property='Opacity' Value='0.9'/></Trigger></ControlTemplate.Triggers>
      </ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style x:Key='Ghost' TargetType='Button'>
      <Setter Property='Foreground' Value='#F5EFEE'/><Setter Property='FontSize' Value='14'/><Setter Property='FontWeight' Value='SemiBold'/>
      <Setter Property='Height' Value='46'/><Setter Property='Padding' Value='24,0'/><Setter Property='Cursor' Value='Hand'/>
      <Setter Property='Template'><Setter.Value><ControlTemplate TargetType='Button'>
        <Border x:Name='b' CornerRadius='15' Background='#1C1110' BorderBrush='#3A2420' BorderThickness='1' Padding='{TemplateBinding Padding}'>
          <ContentPresenter HorizontalAlignment='Center' VerticalAlignment='Center'/></Border>
        <ControlTemplate.Triggers><Trigger Property='IsMouseOver' Value='True'><Setter TargetName='b' Property='BorderBrush' Value='#FF5236'/></Trigger></ControlTemplate.Triggers>
      </ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style TargetType='CheckBox'>
      <Setter Property='Foreground' Value='#E6D9D6'/><Setter Property='FontSize' Value='14'/><Setter Property='Cursor' Value='Hand'/><Setter Property='Margin' Value='0,0,0,14'/>
      <Setter Property='Template'><Setter.Value><ControlTemplate TargetType='CheckBox'>
        <StackPanel Orientation='Horizontal' Background='Transparent'>
          <Border x:Name='box' Width='24' Height='24' CornerRadius='7' Background='#1C1110' BorderBrush='#3A2420' BorderThickness='1'>
            <Path x:Name='tick' Data='M 5,12 L 10,17 L 19,7' Stroke='White' StrokeThickness='2.5' Visibility='Collapsed' StrokeStartLineCap='Round' StrokeEndLineCap='Round'/>
          </Border>
          <ContentPresenter Margin='12,0,0,0' VerticalAlignment='Center'/>
        </StackPanel>
        <ControlTemplate.Triggers>
          <Trigger Property='IsChecked' Value='True'><Setter TargetName='box' Property='Background' Value='{StaticResource Accent}'/><Setter TargetName='box' Property='BorderBrush' Value='#FF5236'/><Setter TargetName='tick' Property='Visibility' Value='Visible'/></Trigger>
        </ControlTemplate.Triggers>
      </ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style x:Key='Sub' TargetType='TextBlock'><Setter Property='Foreground' Value='#A89995'/><Setter Property='FontSize' Value='14'/><Setter Property='TextWrapping' Value='Wrap'/><Setter Property='LineHeight' Value='21'/></Style>
    <Style x:Key='Item' TargetType='TextBlock'><Setter Property='TextWrapping' Value='Wrap'/><Setter Property='Foreground' Value='#E6D9D6'/><Setter Property='FontSize' Value='14'/><Setter Property='Margin' Value='0,0,0,10'/></Style>
  </Window.Resources>
  <Border CornerRadius='22' BorderBrush='#2E1C19' BorderThickness='1'>
    <Border.Background>
      <RadialGradientBrush Center='0.2,1.1' GradientOrigin='0.2,1.1' RadiusX='0.9' RadiusY='1'>
        <GradientStop Color='#3A0F08' Offset='0'/><GradientStop Color='#120807' Offset='0.55'/><GradientStop Color='#0A0606' Offset='1'/>
      </RadialGradientBrush>
    </Border.Background>
    <Grid>
      <Grid.ColumnDefinitions><ColumnDefinition Width='250'/><ColumnDefinition/></Grid.ColumnDefinitions>
      <Grid.RowDefinitions><RowDefinition Height='52'/><RowDefinition/><RowDefinition Height='Auto'/></Grid.RowDefinitions>
      <Grid x:Name='Title' Grid.ColumnSpan='2' Background='Transparent'>
        <StackPanel Orientation='Horizontal' VerticalAlignment='Center' Margin='26,0,0,0'>
          <Border Width='12' Height='12' CornerRadius='4' Background='{StaticResource Accent}'><Border.Effect><DropShadowEffect Color='#FF4A2E' BlurRadius='14' ShadowDepth='0'/></Border.Effect></Border>
          <TextBlock Text='TUNE MANAGER  ·  INSTALLATION' Margin='12,0,0,0' FontSize='12' FontWeight='Bold' Foreground='#D9CCC9'/>
        </StackPanel>
        <Button x:Name='BClose' Content='✕' HorizontalAlignment='Right' Margin='0,0,14,0' Width='40' Height='32' Background='Transparent' Foreground='#9C8D8A' BorderThickness='0' Cursor='Hand'/>
      </Grid>
      <!-- etapes -->
      <StackPanel Grid.Row='1' Grid.RowSpan='2' Margin='30,18,10,30'>
        <TextBlock Text='Tune' FontSize='38' FontWeight='Bold' Margin='0,0,0,-12'/>
        <TextBlock Text='Manager' FontSize='38' FontWeight='Bold' Foreground='#FF6A45'/>
        <TextBlock Text='Chaîne audio ArtTuneDB' Style='{StaticResource Sub}' Margin='0,6,0,34'/>
        <StackPanel x:Name='Steps'>
        <StackPanel Orientation='Horizontal' Margin='0,0,0,16'><Ellipse x:Name='D1' Width='10' Height='10' Margin='0,0,12,0'/><TextBlock Text='Bienvenue' FontSize='14' Foreground='#D9CCC9'/></StackPanel>
        <StackPanel Orientation='Horizontal' Margin='0,0,0,16'><Ellipse x:Name='D2' Width='10' Height='10' Margin='0,0,12,0'/><TextBlock Text='Options' FontSize='14' Foreground='#D9CCC9'/></StackPanel>
        <StackPanel Orientation='Horizontal' Margin='0,0,0,16'><Ellipse x:Name='D3' Width='10' Height='10' Margin='0,0,12,0'/><TextBlock Text='Installation' FontSize='14' Foreground='#D9CCC9'/></StackPanel>
        <StackPanel Orientation='Horizontal'><Ellipse x:Name='D4' Width='10' Height='10' Margin='0,0,12,0'/><TextBlock Text='Terminé' FontSize='14' Foreground='#D9CCC9'/></StackPanel>
        </StackPanel>
      </StackPanel>
      <Border Grid.Row='1' Grid.Column='1' Margin='0,10,30,0' CornerRadius='20' Background='#CC150C0B' BorderBrush='#2E1C19' BorderThickness='1' Padding='32,28'>
        <Grid>
          <Grid x:Name='S0' Visibility='Collapsed'>
            <StackPanel>
              <TextBlock Text='Tune Manager est déjà installé' FontSize='28' FontWeight='Bold' Margin='0,0,0,10' TextWrapping='Wrap'/>
              <TextBlock Style='{StaticResource Sub}' Margin='0,0,0,22' Text='Les mises à jour se font automatiquement depuis Tune Manager. Ici, tu peux le désinstaller ou le réparer.'/>
              <TextBlock Style='{StaticResource Item}' Text='●  Désinstaller : retire Tune Manager et, si tu le choisis, toute la chaîne audio (pilotes, périphériques, restes).'/>
              <TextBlock Style='{StaticResource Item}' Text='●  Réparer : réinstalle les fichiers de Tune Manager en gardant tes options et tes réglages.'/>
            </StackPanel>
          </Grid>
          <Grid x:Name='S1'>
            <StackPanel>
              <TextBlock x:Name='WTitle' Text='Installer Tune Manager' FontSize='28' FontWeight='Bold' Margin='0,0,0,10'/>
              <TextBlock Style='{StaticResource Sub}' Margin='0,0,0,22' Text='Tune Manager installe et règle toute la chaîne audio ArtIsWar gratuite (ArtTuneDB pour Equalizer APO), puis te laisse choisir tes profils en un clic.'/>
              <TextBlock Style='{StaticResource Item}' Text='●  Profils casque + jeu, activés en un clic'/>
              <TextBlock Style='{StaticResource Item}' Text='●  EQ de ton casque créé depuis squig.link'/>
              <TextBlock Style='{StaticResource Item}' Text='●  Chaîne audio installée en un clic, Voicemeeter réglé seul'/>
              <TextBlock Style='{StaticResource Item}' Text='●  Mises à jour de la bibliothèque ArtTuneDB'/>
            </StackPanel>
          </Grid>
          <Grid x:Name='S2' Visibility='Collapsed'>
            <StackPanel>
              <TextBlock Text='Options' FontSize='28' FontWeight='Bold' Margin='0,0,0,16'/>
              <TextBlock Text='Dossier d&apos;installation' FontSize='13' FontWeight='SemiBold' Foreground='#D9CCC9' Margin='0,0,0,8'/>
              <Border CornerRadius='13' Background='#1C1110' BorderBrush='#3A2420' BorderThickness='1' Padding='14,11' Margin='0,0,0,22'>
                <TextBlock x:Name='Path' Foreground='#E6D9D6' FontSize='14'/>
              </Border>
              <CheckBox x:Name='CDesk' Content='Créer un raccourci sur le bureau' IsChecked='True'/>
              <CheckBox x:Name='CStart' Content='Lancer Tune Manager avec Windows (zone de notification)'/>
              <TextBlock Style='{StaticResource Sub}' FontSize='13' Margin='0,8,0,0' Text='La chaîne audio (Equalizer APO, Voicemeeter, VB-CABLE...) s&apos;installe ensuite depuis Tune Manager, en un clic.'/>
            </StackPanel>
          </Grid>
          <Grid x:Name='S3' Visibility='Collapsed'>
            <StackPanel VerticalAlignment='Center'>
              <TextBlock x:Name='S3Title' Text='Installation...' FontSize='28' FontWeight='Bold' Margin='0,0,0,22'/>
              <ProgressBar x:Name='PBar' Height='8' Minimum='0' Maximum='100' Foreground='#FF5236' Background='#2A1915' BorderThickness='0'/>
              <TextBlock x:Name='PStatus' Style='{StaticResource Sub}' Margin='0,14,0,0'/>
            </StackPanel>
          </Grid>
          <Grid x:Name='S4' Visibility='Collapsed'>
            <StackPanel VerticalAlignment='Center'>
              <Border Width='64' Height='64' CornerRadius='20' Background='{StaticResource Accent}' HorizontalAlignment='Left' Margin='0,0,0,20'>
                <Border.Effect><DropShadowEffect Color='#FF4A2E' BlurRadius='30' ShadowDepth='0' Opacity='0.6'/></Border.Effect>
                <Path Data='M 18,33 L 28,43 L 47,22' Stroke='White' StrokeThickness='5' StrokeStartLineCap='Round' StrokeEndLineCap='Round' StrokeLineJoin='Round'/>
              </Border>
              <TextBlock x:Name='S4Title' Text='Tune Manager est installé' FontSize='28' FontWeight='Bold' Margin='0,0,0,10'/>
              <TextBlock Style='{StaticResource Sub}' Margin='0,0,0,24' Text='Au premier lancement, Tune Manager propose d&apos;installer la chaîne audio. Il se désinstalle depuis Paramètres Windows › Applications.'/>
              <CheckBox x:Name='CLaunch' Content='Lancer Tune Manager' IsChecked='True'/>
            </StackPanel>
          </Grid>
        </Grid>
      </Border>
      <Grid Grid.Row='2' Grid.Column='1' Margin='0,18,30,26'>
        <StackPanel x:Name='F0' Orientation='Horizontal' HorizontalAlignment='Right' Visibility='Collapsed'>
          <Button x:Name='BCancel0' Style='{StaticResource Ghost}' Content='Annuler' Margin='0,0,10,0'/>
          <Button x:Name='BRepair' Style='{StaticResource Ghost}' Content='Réparer' Margin='0,0,10,0'/>
          <Button x:Name='BUninstall' Style='{StaticResource Primary}' Content='Désinstaller'/>
        </StackPanel>
        <StackPanel x:Name='F1' Orientation='Horizontal' HorizontalAlignment='Right'>
          <Button x:Name='BCancel' Style='{StaticResource Ghost}' Content='Annuler' Margin='0,0,10,0'/>
          <Button x:Name='BNext' Style='{StaticResource Primary}' Content='Suivant'/>
        </StackPanel>
        <StackPanel x:Name='F2' Orientation='Horizontal' HorizontalAlignment='Right' Visibility='Collapsed'>
          <Button x:Name='BBack' Style='{StaticResource Ghost}' Content='Retour' Margin='0,0,10,0'/>
          <Button x:Name='BInstall' Style='{StaticResource Primary}' Content='Installer'/>
        </StackPanel>
        <StackPanel x:Name='F4' Orientation='Horizontal' HorizontalAlignment='Right' Visibility='Collapsed'>
          <Button x:Name='BFinish' Style='{StaticResource Primary}' Content='Terminer'/>
        </StackPanel>
      </Grid>
    </Grid>
  </Border>
</Window>";
}
