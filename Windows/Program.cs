using System;
using System.Drawing;
using System.IO;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

internal static class Program
{
    private const string Host = "studyflow-planner.example";

    [STAThread]
    private static void Main()
    {
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        var window = new Form
        {
            Text = "StudyFlow Planner",
            Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath),
            Size = new Size(1200, 850),
            MinimumSize = new Size(520, 550),
            StartPosition = FormStartPosition.CenterScreen
        };
        var view = new WebView2 { Dock = DockStyle.Fill };
        window.Controls.Add(view);
        window.Shown += async (_, __) =>
        {
            try
            {
                var storage = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "StudyFlow Planner", "WebView2");
                var environment = await CoreWebView2Environment.CreateAsync(userDataFolder: storage);
                await view.EnsureCoreWebView2Async(environment);
                var web = view.CoreWebView2;
                web.Settings.AreHostObjectsAllowed = false;
                web.Settings.IsWebMessageEnabled = false;
                web.NewWindowRequested += (_, request) => request.Handled = true;
                web.NavigationStarting += (_, navigation) =>
                {
                    navigation.Cancel = !Uri.TryCreate(navigation.Uri, UriKind.Absolute, out var uri)
                        || uri.Scheme != Uri.UriSchemeHttps || uri.Host != Host;
                };
                web.SetVirtualHostNameToFolderMapping(Host, Path.Combine(AppContext.BaseDirectory, "Web"),
                    CoreWebView2HostResourceAccessKind.Deny);
                web.Navigate("https://" + Host + "/index.html");
            }
            catch (WebView2RuntimeNotFoundException)
            {
                MessageBox.Show(window, "Install Microsoft Edge WebView2 Runtime, then reopen StudyFlow Planner.",
                    window.Text, MessageBoxButtons.OK, MessageBoxIcon.Information);
                window.Close();
            }
            catch (Exception error)
            {
                MessageBox.Show(window, error.Message, window.Text, MessageBoxButtons.OK, MessageBoxIcon.Error);
                window.Close();
            }
        };
        Application.Run(window);
    }
}
