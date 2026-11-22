// TuneManager.exe : lance l'interface Tune Manager (TuneManager.ps1 a cote de l'exe), sans console.
//   TuneManager.exe            -> interface
//   TuneManager.exe -Tray      -> demarre cache dans la zone de notification
//   TuneManager.exe /uninstall -> desinstallation (appelee par Parametres > Applications)
using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

[assembly: System.Reflection.AssemblyTitle("Tune Manager")]
[assembly: System.Reflection.AssemblyProduct("Tune Manager")]
[assembly: System.Reflection.AssemblyDescription("Tune Manager - chaine audio ArtTuneDB")]
[assembly: System.Reflection.AssemblyVersion("2.0.0.0")]
[assembly: System.Reflection.AssemblyFileVersion("2.0.0.0")]

static class Launcher {
    [STAThread]
    static int Main(string[] args) {
        string dir = AppDomain.CurrentDomain.BaseDirectory;
        string ps1 = Path.Combine(dir, "TuneManager.ps1");
        if (!File.Exists(ps1)) {
            MessageBox.Show("TuneManager.ps1 est introuvable a cote de TuneManager.exe.\nReinstalle Tune Manager.", "Tune Manager", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        string extra = "";
        foreach (string a in args) {
            string l = a.ToLowerInvariant();
            if (l == "/uninstall" || l == "-removeapp") extra += " -RemoveApp";
            else if (l == "-tray" || l == "/tray") extra += " -Tray";
        }
        string ps = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe");
        var psi = new ProcessStartInfo(ps, "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + ps1 + "\"" + extra);
        psi.UseShellExecute = false; psi.CreateNoWindow = true; psi.WorkingDirectory = dir;
        Process.Start(psi);
        return 0;
    }
}
