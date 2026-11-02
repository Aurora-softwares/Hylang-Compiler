using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.WindowsRuntime;
using System.Text;
using System.Text.Json;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Automation.Provider;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Foundation;
using Windows.ApplicationModel.DataTransfer;
using Windows.Graphics.Imaging;
using Windows.Storage;

namespace Hydrogen.Native;

// Runs inside the actual WinUI application and uses native controls/automation
// peers. It is enabled only by the explicit --ui-test launch argument in CI.
public sealed partial class NativeWindow
{
    delegate bool WindowVisitor(nint window, nint data);
    [DllImport("user32.dll")] static extern bool EnumWindows(WindowVisitor callback, nint data);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(nint window, out uint processId);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(nint window, StringBuilder name, int length);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(nint window);
    [DllImport("user32.dll")] static extern bool PostMessage(nint window, uint message, nint wParam, nint lParam);
    static nint NativePickerWindow() {
        nint found = 0;
        EnumWindows((window, _) => {
            GetWindowThreadProcessId(window, out uint processId);
            if (processId != Environment.ProcessId || !IsWindowVisible(window)) return true;
            var name = new StringBuilder(64);
            if (GetClassName(window, name, name.Capacity) > 0 && name.ToString() == "#32770") { found = window; return false; }
            return true;
        }, 0);
        return found;
    }
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
        AutomationPeer peer = element is MenuFlyoutItem item ? new MenuFlyoutItemAutomationPeer(item) :
            element is AppBarButton command ? new AppBarButtonAutomationPeer(command) : new ButtonAutomationPeer((Button)element);
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
        var toolbar = controls["studioToolbar"] as CommandBar;
        Check(toolbar != null && toolbar.Visibility == Visibility.Visible && toolbar.PrimaryCommands.Count == 2 &&
              ReferenceEquals(toolbar.PrimaryCommands[0], controls["toolbarWorkspace"]), "Native WinUI toolbar is missing");
        Apply("HYUI\tSET\tstudioToolbar\tenabled\tfalse\n");
        Check(!toolbar.IsEnabled, "Disabled toolbar left commands active");
        Apply("HYUI\tSET\tstudioToolbar\tenabled\ttrue\n");
        Invoke(controls["toolbarWorkspace"]); await Idle(); Check(values["pages.value"] == "0", "Toolbar workspace command did not reach Hydrogen");
        Invoke(controls["toolbarControls"]); await Idle(); Check(values["pages.value"] == "1", "Toolbar gallery command did not reach Hydrogen");
        Invoke(controls["showPopover"]); await Idle();
        var tip = popovers["templateTip"].Flyout;
        Check(tip.IsOpen && tip.Content is TextBlock, "Native WinUI flyout did not open");
        Apply("HYUI\tSET\ttemplateTip\ttext\tUpdated template tip\n");
        Check(((TextBlock)tip.Content).Text == "Updated template tip", "Native flyout text did not update");
        tip.Hide(); await Until(() => values["selectionText.text"] == "Template tip dismissed.", "Flyout dismissal did not reach Hydrogen"); await Idle();
        var context = controls["templates"].ContextFlyout as MenuFlyout;
        Check(context != null && context.Items.Count == 1 && ReferenceEquals(context.Items[0], controls["inspectTemplate"]), "Native WinUI context menu is missing");
        context.ShowAt(controls["templates"]); await Task.Delay(100); context.Hide();
        Invoke(controls["inspectTemplate"]); await Idle();
        Check(values["selectionText.text"] == "Inspect template index: 2", "Context menu command did not reach Hydrogen");
        Invoke(controls["copyPreview"]); await Idle();
        Check(await Clipboard.GetContent().GetTextAsync() == "Inspect template index: 2", "Native Windows clipboard write failed");
        Invoke(controls["pastePreview"]);
        await Until(() => values["selectionText.text"] == "Clipboard: Inspect template index: 2", "Native Windows clipboard read did not reach Hydrogen"); await Idle();
        ((ListView)controls["projects"]).SelectedIndex = 1; await Idle(); Check(values["selectionText.text"] == "Project index: 1", "Table event did not reach Hydrogen");
        Check(controls["templateSearch"] is AutoSuggestBox, "SearchInput must use a WinUI AutoSuggestBox");
        var search = (AutoSuggestBox)controls["templateSearch"];
        Check(search.Visibility == Visibility.Visible && ToolTipService.GetToolTip(search)?.ToString() == "Enter a template search term", "Native search visibility or tooltip failed");
        search.Text = "café";
        await Until(() => values["selectionText.text"].Normalize(System.Text.NormalizationForm.FormC) == "Template search: café", "SearchInput event did not reach Hydrogen; text=" + search.Text + ", state=" + values["templateSearch.text"]);
        await Idle();
        Check(controls["templatePassword"] is PasswordBox, "PasswordInput must use a WinUI PasswordBox");
        var password = (PasswordBox)controls["templatePassword"];
        Check(password.Visibility == Visibility.Visible, "Hydrogen did not reveal PasswordInput");
        password.Password = "gallery-pass";
        await Idle(); Check(values["selectionText.text"] == "Private code length: 12", "PasswordInput change event failed");
        Dispatch("CheckPassword", "templatePassword"); await Idle();
        Check(values["selectionText.text"] == "Private code accepted.", "PasswordInput event did not reach Hydrogen");
        Check(!values.ContainsKey("templatePassword.text") && !values.ContainsKey("templatePassword.value"), "Password leaked into UI state");
        Apply("HYUI\tSET\ttemplatePassword\tenabled\tfalse\nHYUI\tSET\ttemplatePassword\tvisible\tfalse\n");
        Check(!password.IsEnabled && password.Visibility == Visibility.Collapsed, "PasswordInput did not apply disabled and hidden state");
        Apply("HYUI\tSET\ttemplatePassword\tenabled\ttrue\nHYUI\tSET\ttemplatePassword\tvisible\ttrue\n");
        foreach (string id in new[] { "openDocument", "saveDocument", "chooseFolder" })
            Check(controls[id] is Button && controls[id].Visibility == Visibility.Visible, "FilePicker must expose a native WinUI button");
        Check(Attr(nodes["openDocument"], "mode") == "open" && Attr(nodes["saveDocument"], "mode") == "save" && Attr(nodes["chooseFolder"], "mode") == "folder", "FilePicker modes are missing");
        values["openDocument.path"] = @"C:\Aurora Notes\café.txt";
        Dispatch("PickedDocument", "openDocument"); await Idle();
        Check(values["selectionText.text"] == @"Open: C:\Aurora Notes\café.txt", "Selected file path did not reach Hydrogen");
        Invoke(controls["openDocument"]);
        await Until(() => NativePickerWindow() != 0 || errors.Text != "", "Native Windows file picker did not open");
        nint nativePicker = NativePickerWindow(); Check(nativePicker != 0, "Native Windows file dialog was not found");
        Check(PostMessage(nativePicker, 0x0010, 0, 0), "Cannot close native Windows file picker");
        await Until(() => !activePickers.Contains("openDocument"), "Native file picker did not complete cancellation"); await Idle();
        Check(values["selectionText.text"] == "File selection cancelled.", "Native Windows file picker cancellation did not reach Hydrogen");
        Check(ToolTipService.GetToolTip(controls["save"])?.ToString() == "Write the current plan to the chosen path", "Native button tooltip is missing");
        Check(controls["templateDetails"] is ScrollViewer, "ScrollView must use a WinUI ScrollViewer");
        var details = (ScrollViewer)controls["templateDetails"];
        Root.UpdateLayout();
        Check(details.Visibility == Visibility.Visible && details.ScrollableHeight > 0, "ScrollView must reveal overflowing content");
        Check(ToolTipService.GetToolTip(details)?.ToString() == "Scroll through template details", "Native ScrollView tooltip is missing");
        Apply("HYUI\tSET\ttemplateDetails\tenabled\tfalse\n"); Check(!((Button)controls["scrollAction"]).IsEnabled, "Disabled ScrollView must disable descendants");
        Apply("HYUI\tSET\ttemplateDetails\tenabled\ttrue\n"); Invoke(controls["scrollAction"]); await Idle();
        Check(values["selectionText.text"] == "Template chosen from scroll view.", "ScrollView child action did not reach Hydrogen");
        Invoke(controls["showDialog"]); await Until(() => dialogs.ContainsKey("confirmation") && dialogs["confirmation"].ActualWidth > 0, "Native dialog failed to open");
        await Task.Delay(200); var dialog = dialogs["confirmation"];
        await Capture(dialog, Path.Combine(output, "dialog-confirm.png")); shots.Add("dialog-confirm.png");
        var primary = DialogButton(dialog, "Continue"); Check(primary != null, "Dialog primary button is missing"); Invoke(primary!);
        await Until(() => values["dialogResult.text"].StartsWith("Confirmed."), "Dialog result did not reach Hydrogen"); await Idle();
        Invoke(controls["showWorkspace"]); await Idle(); Check(tabs.SelectedIndex == 0, "Menu failed to select workspace");
        var workspaceShortcut = controls["showWorkspace"].KeyboardAccelerators.Single();
        var galleryShortcut = controls["showControls"].KeyboardAccelerators.Single();
        Check(workspaceShortcut.Key == Windows.System.VirtualKey.Number1 && galleryShortcut.Key == Windows.System.VirtualKey.Number2 &&
              workspaceShortcut.Modifiers == Windows.System.VirtualKeyModifiers.Control, "Native WinUI menu accelerators are missing");
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
        string originalBackend = backend;
        backend = Path.Combine(Environment.SystemDirectory, "PING.EXE");
        Task<string> inFlight = Run(new[] { "-n", "30", "127.0.0.1" });
        await Task.Delay(200);
        Check(!inFlight.IsCompleted, "Backend cancellation test did not start a live process");
        DisposeNative();
        Check(lifetime.IsCancellationRequested && timers.Values.All(timer => !timer.IsEnabled) && pending.Count == 0,
            "Native window disposal left a backend process, timer or queued event active");
        try { await inFlight; throw new InvalidOperationException("Disposed window did not cancel its backend process"); }
        catch (OperationCanceledException) { }
        backend = originalBackend;
        await File.WriteAllTextAsync(Path.Combine(output, "report.json"), JsonSerializer.Serialize(new { passed = true, platform = "windows", screenshots = shots, captures, state = values }, new JsonSerializerOptions { WriteIndented = true }));
    }
}
