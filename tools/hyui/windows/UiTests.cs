using System.Diagnostics;
using System.Runtime.InteropServices.WindowsRuntime;
using System.Text.Json;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Automation.Provider;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Foundation;
using Windows.Graphics.Imaging;
using Windows.Storage;

namespace Hydrogen.Native;

// Runs inside the actual WinUI application and uses native controls/automation
// peers. It is enabled only by the explicit --ui-test launch argument in CI.
public sealed partial class NativeWindow
{
    static void Check(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
    async Task Until(Func<bool> predicate, string message, int timeout = 8000) {
        var watch = Stopwatch.StartNew();
        while (!predicate() && watch.ElapsedMilliseconds < timeout) await Task.Delay(20);
        Check(predicate(), message + ": " + errors.Text);
    }
    async Task Idle() { await Task.Delay(50); await Until(() => !busy && pending.Count == 0, "Backend event did not finish"); Check(errors.Text == "", errors.Text); }
    FrameworkElement Root => (FrameworkElement)Content;
    Rect Bounds(FrameworkElement view, FrameworkElement? parent = null) => view.TransformToVisual(parent ?? Root).TransformBounds(new Rect(0, 0, view.ActualWidth, view.ActualHeight));
    bool Shown(FrameworkElement element) {
        DependencyObject? current = element;
        while (current != null) { if (current is UIElement e && e.Visibility != Visibility.Visible) return false; if (current == Root) return true; current = VisualTreeHelper.GetParent(current); }
        return false;
    }
    void CheckLayout() {
        foreach (var pair in controls) {
            if (!Shown(pair.Value)) continue;
            string tag = nodes[pair.Key].Name.LocalName;
            IEnumerable<FrameworkElement> children = Array.Empty<FrameworkElement>();
            if (tag is "Panel" or "ColumnPanel" or "RowPanel" or "GridPanel" or "Tab") {
                FrameworkElement container = pair.Value is Border border ? (FrameworkElement)border.Child : pair.Value;
                if (container is Panel panel) children = panel.Children.OfType<FrameworkElement>().Where(Shown);
                var rectangles = children.Select(child => Bounds(child, container)).Where(r => r.Width > 0 && r.Height > 0).ToArray();
                foreach (var rectangle in rectangles) {
                    Check(rectangle.X >= -1 && rectangle.Right <= container.ActualWidth + 1, "Horizontal clipping in " + pair.Key);
                    Check(rectangle.Y >= -1 && rectangle.Bottom <= container.ActualHeight + 1, "Vertical clipping in " + pair.Key);
                }
                for (int i = 0; i < rectangles.Length; i++) for (int j = i + 1; j < rectangles.Length; j++) {
                    Rect overlap = rectangles[i]; overlap.Intersect(rectangles[j]);
                    Check(overlap.IsEmpty || overlap.Width < 1 || overlap.Height < 1, "Overlapping controls in " + pair.Key);
                }
            }
        }
    }
    static void Invoke(FrameworkElement element) {
        AutomationPeer peer = element is MenuFlyoutItem item ? new MenuFlyoutItemAutomationPeer(item) : new ButtonAutomationPeer((Button)element);
        Check(peer.GetPattern(PatternInterface.Invoke) is IInvokeProvider, "Control lacks native Invoke pattern");
        ((IInvokeProvider)peer.GetPattern(PatternInterface.Invoke)).Invoke();
    }
    async Task Capture(UIElement element, string path) {
        var bitmap = new RenderTargetBitmap(); await bitmap.RenderAsync(element);
        Check(bitmap.PixelWidth > 0 && bitmap.PixelHeight > 0, "WinUI produced an empty render target");
        var pixels = await bitmap.GetPixelsAsync();
        var folder = await StorageFolder.GetFolderFromPathAsync(Path.GetDirectoryName(path)!);
        var file = await folder.CreateFileAsync(Path.GetFileName(path), CreationCollisionOption.ReplaceExisting);
        using var stream = await file.OpenAsync(FileAccessMode.ReadWrite);
        var encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.PngEncoderId, stream);
        encoder.SetPixelData(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Premultiplied, (uint)bitmap.PixelWidth, (uint)bitmap.PixelHeight, 96, 96, pixels.ToArray()); await encoder.FlushAsync();
    }
    static Button? DialogButton(DependencyObject root, string label) {
        if (root is Button button && button.Content?.ToString() == label) return button;
        for (int i = 0; i < VisualTreeHelper.GetChildrenCount(root); i++) { var found = DialogButton(VisualTreeHelper.GetChild(root, i), label); if (found != null) return found; }
        return null;
    }
    public async Task RunUiTests(string output) {
        Directory.CreateDirectory(output); Root.RequestedTheme = ElementTheme.Light; ((ScrollViewer)Root).Background = new SolidColorBrush(Microsoft.UI.Colors.White);
        await Until(() => Root.IsLoaded && Root.ActualWidth > 0, "WinUI window did not load");
        var shots = new List<string>(); var captures = new List<object>();
        var tabs = (TabView)controls["pages"];
        foreach (int page in new[] { 0, 1 }) {
            tabs.SelectedIndex = page; await Idle();
            foreach (int width in new[] { 1120, 800, 360 }) {
                AppWindow.Resize(new Windows.Graphics.SizeInt32(width + 16, 640)); Root.Width = width; Root.Height = 600;
                await Task.Delay(250); Root.UpdateLayout(); Check(Root.XamlRoot.Size.Width >= width && Root.XamlRoot.Size.Height >= 600, "Native WinUI viewport is smaller than the fixture"); CheckLayout();
                if (page == 0) {
                    var project = Bounds(controls["projectName"]); var summary = Bounds(controls["summary"]);
                    if (width == 1120) Check(summary.X > project.Right, "Wide workspace panels must be side by side");
                    if (width == 360) {
                        Check(summary.Y > project.Bottom, "Narrow workspace panels must stack");
                        Check(Bounds(controls["workers"]).Y > Bounds(controls["target"]).Bottom, "Nested row failed to stack");
                        Check(((ScrollViewer)Content).ScrollableHeight > 0, "Narrow workspace must scroll");
                    }
                }
                string name = $"{(page == 0 ? "workspace" : "gallery")}-{width}.png";
                await Capture(Root, Path.Combine(output, name)); shots.Add(name);
                var geometry = controls.Where(p => Shown(p.Value) && p.Value.ActualWidth > 0).ToDictionary(p => p.Key, p => new { x = Bounds(p.Value).X, y = Bounds(p.Value).Y, width = p.Value.ActualWidth, height = p.Value.ActualHeight });
                captures.Add(new { name, controls = geometry });
                if ((page == 0 && width == 1120) || (page == 1 && width == 360)) {
                    var scroller = (ScrollViewer)Content; scroller.ChangeView(null, scroller.ScrollableHeight, null, true); await Task.Delay(100);
                    string bottomName = $"{(page == 0 ? "workspace" : "gallery")}-bottom.png";
                    await Capture(Root, Path.Combine(output, bottomName)); shots.Add(bottomName); scroller.ChangeView(null, 0, null, true);
                }
            }
        }
        Root.Width = 1120; AppWindow.Resize(new Windows.Graphics.SizeInt32(1136, 640)); await Task.Delay(200);
        await Until(() => ((BitmapImage)((Image)controls["logo"]).Source).PixelWidth > 0, "Bundled image did not decode");
        ((RadioButtons)controls["channel"]).SelectedIndex = 1; await Idle(); Check(values["channelText.text"] == "Preview channel selected.", "Radio event did not reach Hydrogen");
        ((ListView)controls["templates"]).SelectedIndex = 2; await Idle(); Check(values["selectionText.text"] == "Template index: 2", "List event did not reach Hydrogen");
        ((ListView)controls["projects"]).SelectedIndex = 1; await Idle(); Check(values["selectionText.text"] == "Project index: 1", "Table event did not reach Hydrogen");
        Invoke(controls["showDialog"]); await Until(() => dialogs.ContainsKey("confirmation") && dialogs["confirmation"].ActualWidth > 0, "Native dialog failed to open");
        await Task.Delay(200); var dialog = dialogs["confirmation"];
        await Capture(dialog, Path.Combine(output, "dialog-confirm.png")); shots.Add("dialog-confirm.png");
        var primary = DialogButton(dialog, "Continue"); Check(primary != null, "Dialog primary button is missing"); Invoke(primary!);
        await Until(() => values["dialogResult.text"].StartsWith("Confirmed."), "Dialog result did not reach Hydrogen"); await Idle();
        Invoke(controls["showWorkspace"]); await Idle(); Check(tabs.SelectedIndex == 0, "Menu failed to select workspace");
        ((TextBox)controls["projectName"]).Text = "CI Notes"; await Idle(); Check(values["summary.text"].StartsWith("CI Notes"), "Input event failed");
        ((CheckBox)controls["symbols"]).IsChecked = false; await Idle(); Check(values["summary.text"].Contains("Debug symbols: false"), "Checkbox event failed");
        ((ComboBox)controls["target"]).SelectedIndex = 2; await Idle(); Check(values["summary.text"].Contains("macOS"), "Select event failed");
        ((Slider)controls["quality"]).Value = 55; await Idle(); Check(values["summary.text"].Contains("55%"), "Slider event failed");
        ((ToggleSwitch)controls["notifications"]).IsOn = false; Check(values["notifications.checked"] == "false", "Switch event failed");
        ((NumberBox)controls["workers"]).Value = 8; Check(values["workers.value"] == "8", "Number input event failed");
        ((TextBox)controls["notes"]).Text = "Saved by the native UI CI test."; await Idle();
        Invoke(controls["build"]); await Idle(); Check(values["build.enabled"] == "false" && timers["buildTimer"].IsEnabled, "Build did not start native progress");
        Invoke(controls["cancel"]); await Idle(); Check(values["build.enabled"] == "true" && !timers["buildTimer"].IsEnabled, "Cancel did not stop progress");
        Invoke(controls["build"]); await Until(() => values["progress.value"] == "100", "Native timer did not complete progress"); await Idle();
        Check(((ProgressBar)controls["progress"]).Value == 100 && !((ProgressRing)controls["activity"]).IsActive, "Native progress widgets did not complete");
        Check(((Button)controls["save"]).IsEnabled, "Completion did not enable Save");
        string saved = Path.Combine(output, "saved-plan.txt"); ((TextBox)controls["savePath"]).Text = saved; await Idle(); Check(values["savePath.text"] == saved, "Save path edit did not reach the UI state"); Invoke(controls["save"]); await Idle();
        Check(File.ReadAllText(saved).Contains("Saved by the native UI CI test."), "Native Save did not persist input");
        Root.UpdateLayout(); CheckLayout();
        await File.WriteAllTextAsync(Path.Combine(output, "report.json"), JsonSerializer.Serialize(new { passed = true, platform = "windows", screenshots = shots, captures, state = values }, new JsonSerializerOptions { WriteIndented = true }));
    }
}
