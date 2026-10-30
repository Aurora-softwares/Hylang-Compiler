using System.Diagnostics;
using System.Globalization;
using System.Text.Json;
using System.Xml;
using System.Xml.Linq;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;

namespace Hydrogen.Native;

public partial class App : Application
{
    private Window? window;
    public App() { InitializeComponent(); }
    protected override async void OnLaunched(LaunchActivatedEventArgs args)
    {
        try { window = await NativeWindow.Create(Environment.GetCommandLineArgs().Skip(1).ToArray()); window.Activate(); }
        catch (Exception error) {
            window = new Window { Title = "Hydrogen application", Content = new TextBlock { Text = error.Message, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(24) } };
            window.Activate();
        }
    }
}

// These are Microsoft.UI.Xaml objects, with Microsoft's shared WinUI runtime
// resources. No Qt styling, HTML rendering, or custom title-bar painting is used.
public sealed class NativeWindow : Window
{
    readonly Dictionary<string, XElement> nodes = new();
    readonly Dictionary<string, FrameworkElement> controls = new();
    readonly Dictionary<string, string> values = new();
    readonly Dictionary<string, DispatcherTimer> timers = new();
    readonly List<Action> layouts = new();
    readonly Queue<(string Handler, string Sender)> pending = new();
    readonly TextBlock errors = new() { TextWrapping = TextWrapping.Wrap };
    readonly Dictionary<string, ContentDialog> dialogs = new();
    string backend = "", directory = "", documentDirectory = "";
    bool applying, busy;
    static string Attr(XElement n, string key, string fallback = "") => (string?)n.Attribute(key) ?? fallback;
    static int Number(XElement n, string key, int fallback) => int.TryParse(Attr(n, key), out int result) ? result : fallback;
    static bool Allowed(XElement node, string property) => property switch {
        "enabled" or "visible" => node.Name.LocalName is not ("Window" or "State" or "Timer"),
        "text" => node.Name.LocalName is "Label" or "Input" or "TextArea" or "Button" or "CheckBox" or "Switch" or "Menu" or "MenuItem" or "Dialog",
        "value" => node.Name.LocalName is "State" or "Select" or "Slider" or "NumberInput" or "ProgressBar" or "Tabs" or "ListBox" or "Table" or "RadioGroup" or "Dialog",
        "checked" => node.Name.LocalName is "CheckBox" or "Switch" or "MenuItem",
        "running" => node.Name.LocalName is "Spinner" or "Timer",
        "open" => node.Name.LocalName == "Dialog",
        "indeterminate" => node.Name.LocalName == "ProgressBar",
        _ => false
    };
    static string Encode(string text) => text.Replace("%", "%25").Replace("\t", "%09").Replace("\r", "%0D").Replace("\n", "%0A");
    static string Decode(string text) => text.Replace("%09", "\t").Replace("%0D", "\r").Replace("%0A", "\n").Replace("%25", "%");
    static string Resource(string root, string relative) {
        string path = Path.GetFullPath(relative, root);
        if (Path.IsPathRooted(relative) || !path.StartsWith(Path.GetFullPath(root) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("Invalid application resource path");
        return path;
    }
    public static async Task<NativeWindow> Create(string[] args)
    {
        var options = new Dictionary<string, string>();
        for (int i = 0; i + 1 < args.Length; i += 2) options[args[i]] = args[i + 1];
        var app = new NativeWindow(); string view;
        if (options.TryGetValue("--bundle", out string? root)) {
            app.directory = Path.GetFullPath(root);
            using var manifest = JsonDocument.Parse(File.ReadAllText(Path.Combine(root, "__hyui_app.json")));
            if (manifest.RootElement.GetProperty("format").GetInt32() != 1) throw new InvalidDataException("Unsupported app bundle");
            app.backend = Resource(root, manifest.RootElement.GetProperty("backend").GetString()!);
            view = Resource(root, manifest.RootElement.GetProperty("document").GetString()!);
        } else {
            app.backend = Path.GetFullPath(options["--backend"]); app.directory = Path.GetDirectoryName(app.backend)!;
            view = Path.GetFullPath(options["--document"]);
        }
        var settings = new XmlReaderSettings { DtdProcessing = DtdProcessing.Prohibit, XmlResolver = null, MaxCharactersInDocument = 1024 * 1024 };
        using var reader = XmlReader.Create(view, settings);
        XElement document = XDocument.Load(reader).Root ?? throw new InvalidDataException("Missing Window");
        if (document.Name != "Window" || Attr(document, "version") != "1") throw new InvalidDataException("Unsupported HYUI document");
        app.documentDirectory = Path.GetDirectoryName(view)!;
        app.nodes[Attr(document, "id", "window")] = document;
        app.Title = Attr(document, "title", "Hydrogen");
        var body = new StackPanel { Spacing = 20, Padding = new Thickness(Number(document, "padding", 24)) };
        foreach (var child in document.Elements()) { var widget = app.Build(child); if (widget != null) body.Children.Add(widget); }
        body.Children.Add(app.errors);
        var scroll = new ScrollViewer { Content = body, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        app.Content = scroll; scroll.Loaded += (_, _) => app.ShowDialogs();
        body.SizeChanged += (_, _) => { foreach (var layout in app.layouts) layout(); };
        // Preserve the platform's complete caption bar and native system menu.
        app.ExtendsContentIntoTitleBar = false;
        var area = Microsoft.UI.Windowing.DisplayArea.GetFromWindowId(app.AppWindow.Id, Microsoft.UI.Windowing.DisplayAreaFallback.Primary).WorkArea;
        app.AppWindow.Resize(new Windows.Graphics.SizeInt32(Math.Min(Number(document, "width", 1100), area.Width - 32), Math.Min(Number(document, "height", 820), area.Height - 64)));
        app.AppWindow.Changed += (_, changed) => {
            if (!changed.DidPositionChange) return;
            var screen = Microsoft.UI.Windowing.DisplayArea.GetFromWindowId(app.AppWindow.Id, Microsoft.UI.Windowing.DisplayAreaFallback.Nearest).WorkArea;
            if (app.AppWindow.Size.Width > screen.Width || app.AppWindow.Size.Height > screen.Height) app.AppWindow.Resize(new Windows.Graphics.SizeInt32(Math.Min(app.AppWindow.Size.Width, screen.Width - 32), Math.Min(app.AppWindow.Size.Height, screen.Height - 64)));
        };
        if (options.TryGetValue("--initial-state", out string? stateFile)) {
            var initial = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(File.ReadAllText(stateFile))!;
            foreach (var pair in initial) app.values[pair.Key] = pair.Value.ValueKind == JsonValueKind.True ? "true" : pair.Value.ValueKind == JsonValueKind.False ? "false" : pair.Value.ToString();
            app.Apply("");
        } else app.Apply(await app.Run(Array.Empty<string>()));
        if (document.Attribute("onLoad") != null) app.Dispatch(Attr(document, "onLoad"), Attr(document, "id"));
        return app;
    }
    FrameworkElement? Build(XElement node)
    {
        string tag = node.Name.LocalName, id = Attr(node, "id", "_hyui" + nodes.Count);
        if (nodes.Count > 512 || node.Ancestors().Count() > 32 || nodes.ContainsKey(id)) throw new InvalidDataException("Duplicate control or excessive document size");
        nodes[id] = node;
        foreach (string prop in new[] { "text", "value", "checked", "running", "indeterminate", "enabled", "visible", "open" }) values[id + "." + prop] = Attr(node, prop, prop is "enabled" or "visible" ? "true" : prop == "value" ? "0" : prop == "text" ? "" : prop == "running" && tag == "Spinner" ? "true" : "false");
        FrameworkElement? element;
        void Changed(string property, string value, string action = "onChange") { if (applying || (property == "value" && value == "-1") || values.GetValueOrDefault(id + "." + property) == value) return; values[id + "." + property] = value; if (node.Attribute(action) != null) Dispatch(Attr(node, action), id); }
        if (tag is "State" or "Dialog") return null;
        if (tag == "Timer") {
            var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(Math.Max(100, Number(node, "interval", 1000))) };
            timer.Tick += (_, _) => Dispatch(Attr(node, "onTick"), id); timers[id] = timer; return null;
        }
        if (tag == "MenuBar") {
            var bar = new MenuBar(); foreach (var child in node.Elements()) bar.Items.Add((MenuBarItem)Build(child)!); element = bar;
        } else if (tag == "Menu") {
            var menu = new MenuBarItem { Title = Attr(node, "text") }; foreach (var child in node.Elements()) menu.Items.Add((MenuFlyoutItemBase)Build(child)!); element = menu;
        } else if (tag == "MenuItem") {
            if (node.Attribute("checked") != null) {
                var item = new ToggleMenuFlyoutItem { Text = Attr(node, "text"), IsChecked = Attr(node, "checked") == "true" };
                item.Click += (_, _) => { if (!applying) { values[id + ".checked"] = item.IsChecked ? "true" : "false"; Dispatch(Attr(node, "onClick"), id); } }; element = item;
            } else { var item = new MenuFlyoutItem { Text = Attr(node, "text") }; item.Click += (_, _) => Dispatch(Attr(node, "onClick"), id); element = item; }
        } else if (tag == "Tabs") {
            var tabs = new TabView { IsAddTabButtonVisible = false, CanDragTabs = false, CanReorderTabs = false };
            foreach (var page in node.Elements()) tabs.TabItems.Add(new TabViewItem { Header = Attr(page, "title"), IsClosable = false, Content = Build(page) });
            tabs.SelectionChanged += (_, _) => Changed("value", tabs.SelectedIndex.ToString()); element = tabs;
        } else if (tag == "RadioGroup") {
            var group = new RadioButtons { ItemsSource = Attr(node, "items").Split('|'), SelectedIndex = Number(node, "value", 0) };
            group.SelectionChanged += (_, _) => Changed("value", group.SelectedIndex.ToString()); element = group;
        } else if (tag is "ListBox" or "Table") {
            var list = new ListView { Height = Number(node, "height", 160), SelectionMode = ListViewSelectionMode.Single };
            if (tag == "ListBox") list.ItemsSource = Attr(node, "items").Split('|');
            else {
                string[] columns = Attr(node, "columns").Split('|');
                Grid Row(string[] cells, bool header) {
                    var grid = new Grid { ColumnSpacing = 16, HorizontalAlignment = HorizontalAlignment.Stretch };
                    for (int i = 0; i < columns.Length; i++) { grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) }); var label = new TextBlock { Text = cells[i], TextWrapping = TextWrapping.Wrap, FontWeight = header ? Windows.UI.Text.FontWeights.SemiBold : Windows.UI.Text.FontWeights.Normal }; Grid.SetColumn(label, i); grid.Children.Add(label); }
                    return grid;
                }
                list.Header = Row(columns, true); foreach (string row in Attr(node, "rows").Split('\n')) list.Items.Add(Row(row.Split('|'), false));
                list.ItemContainerStyle = new Style(typeof(ListViewItem)); list.ItemContainerStyle.Setters.Add(new Setter(Control.HorizontalContentAlignmentProperty, HorizontalAlignment.Stretch));
            }
            list.SelectionChanged += (_, _) => { if (list.SelectedIndex >= 0) Changed("value", list.SelectedIndex.ToString()); else list.SelectedIndex = int.Parse(values.GetValueOrDefault(id + ".value", "0")); }; element = list;
        } else if (tag == "Image") {
            element = new Image { Source = new Microsoft.UI.Xaml.Media.Imaging.BitmapImage(new Uri(Resource(documentDirectory, Attr(node, "source")))), Height = Number(node, "height", 72), Stretch = Microsoft.UI.Xaml.Media.Stretch.Uniform };
        } else if (tag is "Panel" or "ColumnPanel" or "RowPanel" or "GridPanel" or "Tab") {
            var panel = new StackPanel { Spacing = Number(node, "gap", 12) };
            if (tag == "Panel" && node.Attribute("title") != null) panel.Children.Add(new TextBlock { Text = Attr(node, "title"), Style = (Style)Application.Current.Resources["SubtitleTextBlockStyle"] });
            foreach (var child in node.Elements()) { var control = Build(child); if (control != null) panel.Children.Add(control); }
            if (tag is "RowPanel" or "GridPanel") {
                var grid = new Grid { ColumnSpacing = Number(node, "gap", 16), RowSpacing = Number(node, "gap", 16) };
                var children = panel.Children.ToList(); panel.Children.Clear(); foreach (var child in children) grid.Children.Add(child);
                void Reflow() {
                    int columns = tag == "RowPanel" ? (grid.ActualWidth < Number(node, "breakpoint", 700) ? 1 : Math.Max(1, children.Count)) : Math.Max(1, Math.Min(Number(node, "columns", 3), (int)(grid.ActualWidth / Number(node, "minItemWidth", 240))));
                    if (grid.ColumnDefinitions.Count == columns) return;
                    grid.ColumnDefinitions.Clear(); grid.RowDefinitions.Clear();
                    for (int i = 0; i < columns; i++) grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                    for (int i = 0; i < (children.Count + columns - 1) / columns; i++) grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
                    for (int i = 0; i < children.Count; i++) { Grid.SetColumn(children[i], i % columns); Grid.SetRow(children[i], i / columns); }
                }
                grid.SizeChanged += (_, _) => Reflow(); layouts.Add(Reflow); element = grid;
            } else {
                element = tag == "Panel" ? new Border { Child = panel, Padding = new Thickness(Number(node, "padding", 20)), BorderThickness = new Thickness(1), Background = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["CardBackgroundFillColorDefaultBrush"], BorderBrush = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["CardStrokeColorDefaultBrush"] } : panel;
            }
        } else if (tag == "Label") {
            var label = new TextBlock { Text = Attr(node, "text"), TextWrapping = TextWrapping.Wrap };
            string role = Attr(node, "role"); if (role is "title" or "heading" or "caption") label.Style = (Style)Application.Current.Resources[role == "title" ? "TitleTextBlockStyle" : role == "heading" ? "SubtitleTextBlockStyle" : "CaptionTextBlockStyle"];
            element = label;
        } else if (tag == "Button") {
            var button = new Button { Content = Attr(node, "text") }; if (Attr(node, "primary") == "true") button.Style = (Style)Application.Current.Resources["AccentButtonStyle"];
            button.Click += (_, _) => Dispatch(Attr(node, "onClick"), id); element = button;
        } else if (tag is "Input" or "TextArea") {
            var input = new TextBox { Text = Attr(node, "text"), PlaceholderText = Attr(node, "placeholder"), AcceptsReturn = tag == "TextArea", TextWrapping = tag == "TextArea" ? TextWrapping.Wrap : TextWrapping.NoWrap };
            if (tag == "TextArea") input.MinHeight = Number(node, "height", 100);
            input.TextChanged += (_, _) => Changed("text", input.Text);
            input.KeyDown += (_, e) => { if (e.Key == Windows.System.VirtualKey.Enter && node.Attribute("onSubmit") != null) Dispatch(Attr(node, "onSubmit"), id); }; element = input;
        } else if (tag == "CheckBox") {
            var check = new CheckBox { Content = Attr(node, "text"), IsChecked = Attr(node, "checked") == "true" };
            check.Checked += (_, _) => Changed("checked", "true"); check.Unchecked += (_, _) => Changed("checked", "false"); element = check;
        } else if (tag == "Switch") {
            var toggle = new ToggleSwitch { Header = Attr(node, "text"), IsOn = Attr(node, "checked") == "true" };
            toggle.Toggled += (_, _) => Changed("checked", toggle.IsOn ? "true" : "false"); element = toggle;
        } else if (tag == "Select") {
            var select = new ComboBox { ItemsSource = Attr(node, "items").Split('|'), SelectedIndex = Number(node, "value", 0) };
            select.SelectionChanged += (_, _) => Changed("value", select.SelectedIndex.ToString()); element = select;
        } else if (tag == "Slider") {
            var slider = new Slider { Minimum = Number(node, "minimum", 0), Maximum = Number(node, "maximum", 100), Value = Number(node, "value", 0), StepFrequency = 1 };
            slider.ValueChanged += (_, _) => Changed("value", ((int)slider.Value).ToString()); element = slider;
        } else if (tag == "NumberInput") {
            var number = new NumberBox { Minimum = Number(node, "minimum", 0), Maximum = Number(node, "maximum", 100), Value = Number(node, "value", 0), SpinButtonPlacementMode = NumberBoxSpinButtonPlacementMode.Inline };
            number.ValueChanged += (_, _) => { if (!double.IsNaN(number.Value)) Changed("value", ((int)number.Value).ToString()); }; element = number;
        } else if (tag == "ProgressBar") element = new ProgressBar { Minimum = Number(node, "minimum", 0), Maximum = Number(node, "maximum", 100), Value = Number(node, "value", 0) };
        else if (tag == "Spinner") element = new ProgressRing { IsActive = Attr(node, "running", "true") == "true" };
        else if (tag == "Separator") element = new Border { Height = 1, Background = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources["DividerStrokeColorDefaultBrush"] };
        else if (tag == "Spacer") element = new Grid { Height = Number(node, "height", 12) };
        else throw new InvalidDataException("Unsupported native control " + tag);
        controls[id] = element;
        if (node.Attribute("accessibleName") != null) Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(element, Attr(node, "accessibleName"));
        element.Visibility = Attr(node, "visible", "true") == "true" ? Visibility.Visible : Visibility.Collapsed;
        if (element is Control enabled) enabled.IsEnabled = Attr(node, "enabled", "true") == "true";
        return element;
    }
    async Task<string> Run(IEnumerable<string> arguments)
    {
        using var process = new Process { StartInfo = new ProcessStartInfo(backend) { WorkingDirectory = directory, UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true, CreateNoWindow = true } };
        foreach (string arg in arguments) process.StartInfo.ArgumentList.Add(arg);
        process.Start(); using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(10));
        try {
            var outputTask = ReadBounded(process.StandardOutput, 1024 * 1024, timeout.Token);
            var errorsTask = ReadBounded(process.StandardError, 65536, timeout.Token);
            await process.WaitForExitAsync(timeout.Token); string output = await outputTask, error = await errorsTask;
            if (process.ExitCode != 0) throw new InvalidOperationException("Hydrogen handler failed: " + error); return output;
        } catch { if (!process.HasExited) process.Kill(true); throw; }
    }
    static async Task<string> ReadBounded(StreamReader stream, int limit, CancellationToken token) {
        var result = new System.Text.StringBuilder(); char[] buffer = new char[4096]; int count;
        while ((count = await stream.ReadAsync(buffer.AsMemory(), token)) != 0) { result.Append(buffer, 0, count); if (result.Length > limit) throw new InvalidDataException("Backend output limit exceeded"); } return result.ToString();
    }
    async void Dispatch(string handler, string sender)
    {
        if (handler == "" || !nodes.TryGetValue(sender, out var node) || !node.Attributes().Any(a => a.Name.LocalName.StartsWith("on") && a.Value == handler)) return;
        if (pending.Contains((handler, sender))) return;
        if (pending.Count >= 32) { errors.Text = "Too many queued events"; return; }
        pending.Enqueue((handler, sender)); if (busy) return; busy = true;
        try { while (pending.Count > 0) {
            var next = pending.Dequeue(); var arguments = new List<string> { "--hyui-event", next.Handler, next.Sender };
            if (nodes[next.Sender].Name == "Timer" && values.GetValueOrDefault(next.Sender + ".running") != "true") continue;
            foreach (var pair in nodes) {
                string property = pair.Value.Name.LocalName is "State" or "Select" or "NumberInput" or "ProgressBar" or "Slider" or "Tabs" or "ListBox" or "Table" or "RadioGroup" or "Dialog" ? "value" : pair.Value.Name.LocalName is "CheckBox" or "Switch" or "MenuItem" ? "checked" : "text";
                arguments.Add(pair.Key); arguments.Add(values.GetValueOrDefault(pair.Key + "." + property, ""));
            }
            if (arguments.Sum(a => a.Length) > 24000) throw new InvalidOperationException("Value snapshot too large");
            Apply(await Run(arguments));
        } } catch (Exception error) { errors.Text = error.Message; } finally { busy = false; }
    }
    async void ShowDialogs() {
        if (Content is not FrameworkElement root || root.XamlRoot == null) return;
        foreach (var pair in nodes.Where(p => p.Value.Name.LocalName == "Dialog")) {
            string id = pair.Key;
            if (values.GetValueOrDefault(id + ".open") != "true") { if (dialogs.TryGetValue(id, out var active)) active.Hide(); continue; }
            if (dialogs.ContainsKey(id) || dialogs.Count != 0) continue;
            string[] buttons = Attr(pair.Value, "buttons", "OK").Split('|');
            var dialog = new ContentDialog { Title = Attr(pair.Value, "title", "Hydrogen"), Content = values[id + ".text"], CloseButtonText = buttons[^1], XamlRoot = root.XamlRoot };
            if (buttons.Length > 1) dialog.PrimaryButtonText = buttons[0];
            if (buttons.Length > 2) dialog.SecondaryButtonText = buttons[1];
            dialogs[id] = dialog;
            try {
                var result = await dialog.ShowAsync(); dialogs.Remove(id);
                if (values[id + ".open"] != "true") continue;
                values[id + ".open"] = "false";
                values[id + ".value"] = (result == ContentDialogResult.Primary ? 0 : result == ContentDialogResult.Secondary ? 1 : buttons.Length - 1).ToString();
                Dispatch(Attr(pair.Value, "onClose"), id);
            } catch (Exception error) { dialogs.Remove(id); values[id + ".open"] = "false"; errors.Text = error.Message; }
        }
    }
    void Apply(string output)
    {
        var updates = new Dictionary<string, string>(values);
        foreach (string line in output.Split('\n')) {
            string[] parts = line.TrimEnd('\r').Split('\t'); if (parts.Length == 0 || parts[0] != "HYUI") continue;
            if (parts.Length == 3 && parts[1] == "OPEN") continue;
            if (parts.Length != 5 || parts[1] != "SET" || !nodes.ContainsKey(Decode(parts[2]))) throw new InvalidDataException("Invalid Hydrogen response");
            string id = Decode(parts[2]), prop = Decode(parts[3]), value = Decode(parts[4]);
            if (!Allowed(nodes[id], prop)) throw new InvalidDataException("Unknown control property");
            if (prop is "checked" or "running" or "indeterminate" or "enabled" or "visible" or "open") { if (value != "true" && value != "false") throw new InvalidDataException("Invalid boolean"); }
            if (prop == "value" && nodes[id].Name != "State") {
                var n = nodes[id]; string tag = n.Name.LocalName;
                int maximum = tag is "Select" or "ListBox" or "RadioGroup" ? Attr(n, "items").Split('|').Length - 1 : tag == "Tabs" ? n.Elements().Count() - 1 : tag == "Table" ? Attr(n, "rows").Split('\n').Length - 1 : tag == "Dialog" ? Attr(n, "buttons", "OK").Split('|').Length - 1 : Number(n, "maximum", 100);
                if (!int.TryParse(value, NumberStyles.None, CultureInfo.InvariantCulture, out int number) || number < Number(n, "minimum", 0) || number > maximum) throw new InvalidDataException("Value outside range");
            }
            updates[id + "." + prop] = value;
        }
        applying = true; values.Clear(); foreach (var item in updates) values[item.Key] = item.Value;
        foreach (var item in controls) {
            string Value(string p) => values.GetValueOrDefault(item.Key + "." + p, "");
            item.Value.Visibility = Value("visible") == "true" ? Visibility.Visible : Visibility.Collapsed;
            if (item.Value is Control control) control.IsEnabled = Value("enabled") == "true";
            switch (item.Value) {
                case MenuBarItem menu: menu.Title = Value("text"); break;
                case ToggleMenuFlyoutItem menu: menu.Text = Value("text"); menu.IsChecked = Value("checked") == "true"; break;
                case MenuFlyoutItem menu: menu.Text = Value("text"); break;
                case TabView tabs: tabs.SelectedIndex = int.Parse(Value("value")); break;
                case RadioButtons group: group.SelectedIndex = int.Parse(Value("value")); break;
                case ListView list: list.SelectedIndex = int.Parse(Value("value")); break;
                case TextBlock label: label.Text = Value("text"); break;
                case TextBox input: if (input.Text != Value("text")) input.Text = Value("text"); break;
                case CheckBox check: check.IsChecked = Value("checked") == "true"; check.Content = Value("text"); break;
                case Button button: button.Content = Value("text"); break;
                case ToggleSwitch toggle: toggle.IsOn = Value("checked") == "true"; break;
                case ComboBox select: select.SelectedIndex = int.Parse(Value("value")); break;
                case Slider slider: slider.Value = double.Parse(Value("value"), CultureInfo.InvariantCulture); break;
                case NumberBox number: number.Value = double.Parse(Value("value"), CultureInfo.InvariantCulture); break;
                case ProgressBar progress: progress.Value = double.Parse(Value("value"), CultureInfo.InvariantCulture); progress.IsIndeterminate = Value("indeterminate") == "true"; break;
                case ProgressRing ring: ring.IsActive = Value("running") == "true"; break;
            }
        }
        foreach (var timer in timers) { if (values[timer.Key + ".running"] == "true") timer.Value.Start(); else timer.Value.Stop(); }
        applying = false; errors.Text = ""; ShowDialogs();
    }
}
