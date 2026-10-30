#include "native_runtime.hpp"
#include <QCoreApplication>
#include <QTimer>
#include <QMap>
#import <AppKit/AppKit.h>

// All interactive elements in this renderer are AppKit objects. AppKit owns
// window decorations, control drawing, accessibility, focus and system themes.
@interface HYAction : NSObject<NSTextFieldDelegate, NSTextViewDelegate, NSWindowDelegate> {
@public
    std::function<void(id)> callback;
}
- (void)fire:(id)sender;
@end
@implementation HYAction
- (void)fire:(id)sender { if (callback) { callback(sender); } }
- (void)controlTextDidChange:(NSNotification*)note { [self fire:note.object]; }
- (void)textDidChange:(NSNotification*)note { [self fire:note.object]; }
- (BOOL)windowShouldClose:(NSWindow*)window { QCoreApplication::quit(); return YES; }
@end

namespace hyui {
namespace {
NSString* text(const QString& value) { return [NSString stringWithUTF8String:value.toUtf8().constData()]; }
QString string(NSString* value) { return QString::fromUtf8(value.UTF8String ?: ""); }
struct Item { NSView* view; id control; id extra; const Node* node; };
struct Layout { NSStackView* stack; const Node* node; NSMutableArray* children; int columns = 0; };
class AppKitView : public NativeView {
    const Document& doc;
    Bridge& bridge;
    NSWindow* window;
    NSMutableArray* retained = [NSMutableArray new];
    QMap<QString, Item> items;
    QVector<Layout> layouts;
    QVector<QTimer*> timers;
    bool applying = false;
    NSTextField* error;
    HYAction* action(std::function<void(id)> fn) {
        HYAction* target = [[[HYAction alloc] init] autorelease]; target->callback = std::move(fn); [retained addObject:target]; return target;
    }
    NSStackView* stack() {
        NSStackView* result = [NSStackView stackViewWithViews:@[]]; result.orientation = NSUserInterfaceLayoutOrientationVertical;
        result.alignment = NSLayoutAttributeLeading; result.spacing = 12; return result;
    }
    void add(NSStackView* parent, NSView* view) {
        if (!view) { return; }
        [parent addArrangedSubview:view]; view.translatesAutoresizingMaskIntoConstraints = NO;
        [view.widthAnchor constraintLessThanOrEqualToAnchor:parent.widthAnchor].active = YES;
        [view setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    }
    void handleEvent(const Node& node, QString property, QVariant value, QString event) {
        if (applying || bridge.isApplying()) { return; }
        bridge.store(node.id, property, value);
        if (node.attributes.contains(event)) { bridge.dispatch(node.attributes[event], node.id); }
    }
    NSView* build(const Node& node) {
        const auto& a = node.attributes; QString tag = node.tag;
        if (tag == "State") { return nil; }
        if (tag == "Timer") {
            QTimer* timer = new QTimer(&bridge); timer->setObjectName(node.id); timer->setInterval(a.value("interval", "1000").toInt());
            QObject::connect(timer, &QTimer::timeout, &bridge, [this, &node] { bridge.dispatch(node.attributes["onTick"], node.id); }); timers.append(timer); return nil;
        }
        NSView* view = nil; id control = nil; id extra = nil;
        if (tag == "ColumnPanel" || tag == "RowPanel" || tag == "GridPanel" || tag == "Panel") {
            NSStackView* contents = stack(); contents.spacing = a.value("gap", "12").toInt();
            NSMutableArray* children = [NSMutableArray array];
            for (const auto& child : node.children) { NSView* v = build(child); if (v) { [children addObject:v]; add(contents, v); } }
            view = contents;
            if (tag == "Panel") {
                NSBox* panel = [[[NSBox alloc] init] autorelease]; panel.title = text(a.value("title"));
                panel.contentViewMargins = NSMakeSize(a.value("padding", "20").toInt(), a.value("padding", "20").toInt());
                panel.contentView = contents; view = panel;
            }
            if (tag == "RowPanel" || tag == "GridPanel") { [retained addObject:children]; layouts.append({contents, &node, children, 0}); }
        } else if (tag == "Label") {
            NSTextField* label = [NSTextField wrappingLabelWithString:@""]; label.maximumNumberOfLines = 0;
            if (a.value("tone") == "muted") { label.textColor = NSColor.secondaryLabelColor; }
            if (a.value("tone") == "accent") { label.textColor = NSColor.controlAccentColor; }
            if (a.value("role") == "title" || a.value("role") == "heading") { label.font = [NSFont boldSystemFontOfSize:[NSFont systemFontSizeForControlSize:NSControlSizeLarge]]; }
            view = label; control = label;
        } else if (tag == "Button" || tag == "CheckBox" || tag == "Switch") {
            if (tag == "Switch") {
                NSSwitch* toggle = [[[NSSwitch alloc] init] autorelease];
                HYAction* target = action([this, &node](id sender) { handleEvent(node, "checked", [(NSSwitch*)sender state] == NSControlStateValueOn, "onChange"); });
                toggle.target = target; toggle.action = @selector(fire:); control = toggle;
                NSStackView* row = stack(); row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
                add(row, toggle); add(row, [NSTextField labelWithString:text(a.value("text"))]); view = row;
            } else {
                NSButton* button = [NSButton buttonWithTitle:@"" target:nil action:@selector(fire:)];
                if (tag == "CheckBox") { [button setButtonType:NSButtonTypeSwitch]; }
                else { button.bezelStyle = NSBezelStyleRounded; if (a.value("primary") == "true") { button.keyEquivalent = @"\r"; } }
                button.target = action([this, &node, tag](id sender) {
                    if (tag == "CheckBox") { handleEvent(node, "checked", [(NSButton*)sender state] == NSControlStateValueOn, "onChange"); }
                    else if (node.attributes.contains("onClick")) { bridge.dispatch(node.attributes["onClick"], node.id); }
                }); view = button; control = button;
            }
        } else if (tag == "Input" || tag == "NumberInput") {
            NSTextField* input = [[[NSTextField alloc] init] autorelease]; input.placeholderString = text(a.value("placeholder"));
            input.delegate = action([this, &node, tag](id sender) { handleEvent(node, tag == "NumberInput" ? "value" : "text", tag == "NumberInput" ? QVariant(int([(NSTextField*)sender intValue])) : QVariant(string([(NSTextField*)sender stringValue])), "onChange"); });
            input.target = action([this, &node](id) { if (node.attributes.contains("onSubmit")) { bridge.dispatch(node.attributes["onSubmit"], node.id); } }); input.action = @selector(fire:);
            view = input; control = input;
            if (tag == "NumberInput") {
                NSStepper* stepper = [[[NSStepper alloc] init] autorelease]; stepper.minValue = a.value("minimum", "0").toInt(); stepper.maxValue = a.value("maximum", "100").toInt(); stepper.increment = 1;
                stepper.target = action([this, &node, input](id sender) { input.intValue = int([(NSStepper*)sender doubleValue]); handleEvent(node, "value", int(input.intValue), "onChange"); }); stepper.action = @selector(fire:);
                NSStackView* row = stack(); row.orientation = NSUserInterfaceLayoutOrientationHorizontal; add(row, input); add(row, stepper); view = row; extra = stepper;
            }
        } else if (tag == "TextArea") {
            NSTextView* input = [[[NSTextView alloc] init] autorelease]; input.richText = NO; input.font = [NSFont systemFontOfSize:NSFont.systemFontSize];
            input.delegate = action([this, &node](id sender) { handleEvent(node, "text", string([(NSTextView*)sender string]), "onChange"); });
            NSScrollView* scroll = [[[NSScrollView alloc] init] autorelease]; scroll.documentView = input; scroll.hasVerticalScroller = YES;
            [scroll.heightAnchor constraintEqualToConstant:a.value("height", "100").toInt()].active = YES; view = scroll; control = input;
        } else if (tag == "Select") {
            NSPopUpButton* select = [[[NSPopUpButton alloc] init] autorelease];
            for (const auto& option : a.value("items").split('|')) { [select addItemWithTitle:text(option)]; }
            select.target = action([this, &node](id sender) { handleEvent(node, "value", int([(NSPopUpButton*)sender indexOfSelectedItem]), "onChange"); }); select.action = @selector(fire:); view = select; control = select;
        } else if (tag == "Slider") {
            NSSlider* slider = [[[NSSlider alloc] init] autorelease]; slider.minValue = a.value("minimum", "0").toInt(); slider.maxValue = a.value("maximum", "100").toInt();
            slider.target = action([this, &node](id sender) { handleEvent(node, "value", int([(NSSlider*)sender doubleValue]), "onChange"); }); slider.action = @selector(fire:); view = slider; control = slider;
        } else if (tag == "Spinner" || tag == "ProgressBar") {
            NSProgressIndicator* progress = [[[NSProgressIndicator alloc] init] autorelease]; progress.style = tag == "Spinner" ? NSProgressIndicatorStyleSpinning : NSProgressIndicatorStyleBar;
            progress.minValue = a.value("minimum", "0").toInt(); progress.maxValue = a.value("maximum", "100").toInt(); progress.displayedWhenStopped = YES; view = progress; control = progress;
        } else if (tag == "Separator") {
            NSBox* line = [[[NSBox alloc] init] autorelease]; line.boxType = NSBoxSeparator; view = line;
        } else { view = [[[NSView alloc] init] autorelease]; [view.heightAnchor constraintEqualToConstant:a.value("height", "12").toInt()].active = YES; }
        if (view) {
            if (a.contains("accessibleName")) { [view setAccessibilityLabel:text(a["accessibleName"])]; }
            [retained addObject:view]; if (control) { [retained addObject:control]; } items[node.id] = {view, control, extra, &node};
        }
        return view;
    }
    void update() {
        applying = true; auto state = bridge.state();
        for (auto it = items.cbegin(); it != items.cend(); ++it) {
            Item c = it.value(); auto value = [&](QString p) { return state.value(it.key() + '.' + p); }; QString tag = c.node->tag;
            c.view.hidden = !value("visible").toBool(); if ([c.control respondsToSelector:@selector(setEnabled:)]) { [c.control setEnabled:value("enabled").toBool()]; }
            if (tag == "Label" || tag == "Input") { if (string([c.control stringValue]) != value("text").toString()) { [c.control setStringValue:text(value("text").toString())]; } }
            if (tag == "TextArea") { if (string([(NSTextView*)c.control string]) != value("text").toString()) { [(NSTextView*)c.control setString:text(value("text").toString())]; } }
            if (tag == "Button" || tag == "CheckBox") { [(NSButton*)c.control setTitle:text(value("text").toString())]; }
            if (tag == "CheckBox" || tag == "Switch") { [c.control setState:value("checked").toBool() ? NSControlStateValueOn : NSControlStateValueOff]; }
            if (tag == "Select") { [(NSPopUpButton*)c.control selectItemAtIndex:value("value").toInt()]; }
            if (tag == "Slider" || tag == "NumberInput" || tag == "ProgressBar") { [c.control setDoubleValue:value("value").toDouble()]; if (c.extra) { [c.extra setDoubleValue:value("value").toDouble()]; } }
            if (tag == "Spinner" || tag == "ProgressBar") { NSProgressIndicator* p = c.control; p.indeterminate = tag == "Spinner" || value("indeterminate").toBool(); if ((tag == "Spinner" && value("running").toBool()) || (tag == "ProgressBar" && p.indeterminate)) { [p startAnimation:nil]; } else { [p stopAnimation:nil]; } }
        }
        for (QTimer* timer : timers) { bool running = state.value(timer->objectName() + ".running").toBool(); if (running && !timer->isActive()) { timer->start(); } if (!running) { timer->stop(); } }
        applying = false;
    }
public:
    AppKitView(const Document& document, Bridge& backend) : doc(document), bridge(backend) {
        [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1100, 820) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
        window.title = text(doc.window.attributes.value("title", "Hydrogen")); window.delegate = action({});
        QString theme = doc.window.attributes.value("theme", "system");
        if (theme != "system") { window.appearance = [NSAppearance appearanceNamed:theme == "dark" ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua]; }
        NSStackView* body = stack(); body.edgeInsets = NSEdgeInsetsMake(24, 24, 24, 24);
        for (const auto& node : doc.window.children) { add(body, build(node)); }
        error = [NSTextField wrappingLabelWithString:@""]; add(body, error);
        NSScrollView* scroll = [[[NSScrollView alloc] init] autorelease]; scroll.hasVerticalScroller = YES; scroll.documentView = body;
        body.translatesAutoresizingMaskIntoConstraints = NO;
        [body.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor].active = YES;
        NSView* content = scroll;
        if (doc.window.attributes.value("material", "auto") != "solid" && !NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceTransparency) {
            Class glassClass = NSClassFromString(@"NSGlassEffectView");
            if (glassClass) { NSView* glass = [[[glassClass alloc] init] autorelease]; [glass setValue:scroll forKey:@"contentView"]; content = glass; }
            else { NSVisualEffectView* material = [[[NSVisualEffectView alloc] init] autorelease]; material.material = NSVisualEffectMaterialWindowBackground; material.blendingMode = NSVisualEffectBlendingModeBehindWindow; [material addSubview:scroll]; content = material; }
            window.opaque = NO; window.backgroundColor = NSColor.clearColor;
        }
        content.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable; scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        window.contentView = content;
        QObject::connect(&bridge, &Bridge::changed, &bridge, [this] { update(); });
        QObject::connect(&bridge, &Bridge::errorChanged, &bridge, [this] { error.stringValue = text(bridge.error()); }); update();
    }
    void present(int width, int height) override {
        NSRect area = NSScreen.mainScreen.visibleFrame; [window setContentSize:NSMakeSize(qMin(width, int(area.size.width - 32)), qMin(height, int(area.size.height - 64)))];
        [window center]; [window makeKeyAndOrderFront:nil]; [NSApp finishLaunching]; [NSApp activateIgnoringOtherApps:YES];
    }
    void pump() override {
        NSEvent* event;
        while ((event = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:NSDate.distantPast inMode:NSDefaultRunLoopMode dequeue:YES])) { [NSApp sendEvent:event]; }
        for (auto& layout : layouts) {
            int columns = layout.node->tag == "RowPanel" ? (layout.stack.bounds.size.width < layout.node->attributes.value("breakpoint", "700").toInt() ? 1 : int(layout.children.count)) :
                qMax(1, qMin(layout.node->attributes.value("columns", "3").toInt(), int(layout.stack.bounds.size.width / layout.node->attributes.value("minItemWidth", "240").toInt())));
            if (columns == layout.columns) { continue; } layout.columns = columns;
            for (NSView* old in [[layout.stack.arrangedSubviews copy] autorelease]) { [layout.stack removeArrangedSubview:old]; [old removeFromSuperview]; }
            NSStackView* row = nil; int index = 0;
            for (NSView* child in layout.children) { if (index++ % columns == 0) { row = stack(); row.orientation = NSUserInterfaceLayoutOrientationHorizontal; add(layout.stack, row); } [child removeFromSuperview]; add(row, child); }
        }
        [NSApp updateWindows];
    }
    bool screenshot(const QString& path) override {
        NSView* view = window.contentView; NSBitmapImageRep* image = [view bitmapImageRepForCachingDisplayInRect:view.bounds]; [view cacheDisplayInRect:view.bounds toBitmapImageRep:image];
        return [[image representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:text(path) atomically:YES];
    }
};
}
int appkitMain(int argc, char** argv) {
    @autoreleasepool { return nativeMain(argc, argv, [](const Document& doc, Bridge& bridge) { return std::make_unique<AppKitView>(doc, bridge); }); }
}
}
