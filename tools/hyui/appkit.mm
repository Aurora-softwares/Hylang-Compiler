#include "native_runtime.hpp"
#include <QCoreApplication>
#include <QTimer>
#include <QMap>
#include <cmath>
#import <AppKit/AppKit.h>

// All interactive elements in this renderer are AppKit objects. AppKit owns
// window decorations, control drawing, accessibility, focus and system themes.
@interface HYLayoutView : NSView
@end
@implementation HYLayoutView
- (BOOL)isFlipped { return YES; }
@end

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
struct Layout {
    NSMutableArray* children;
    QString tag = "ColumnPanel";
    int gap = 12;
    int breakpoint = 700;
    int columns = 3;
    int minItemWidth = 240;
};
class AppKitView : public NativeView {
    const Document& doc;
    Bridge& bridge;
    NSWindow* window;
    NSMutableArray* retained = [NSMutableArray new];
    QMap<QString, Item> items;
    QMap<NSView*, Layout> layouts;
    QMap<NSView*, NSBox*> panelBorders;
    QMap<NSView*, const Node*> nodes;
    NSView* body;
    NSScrollView* scroll;
    QVector<QTimer*> timers;
    bool applying = false;
    bool layoutDirty = true;
    NSSize viewportSize = NSZeroSize;
    NSTextField* error;
    HYAction* action(std::function<void(id)> fn) {
        HYAction* target = [[[HYAction alloc] init] autorelease]; target->callback = std::move(fn); [retained addObject:target]; return target;
    }
    NSView* stack() {
        NSView* result = [[[HYLayoutView alloc] init] autorelease];
        NSMutableArray* children = [NSMutableArray array]; [retained addObject:children];
        layouts.insert(result, {children});
        return result;
    }
    void add(NSView* parent, NSView* view) {
        if (!view) { return; }
        [parent addSubview:view]; [layouts[parent].children addObject:view];
    }
    // Measure wrapped text at its actual column width before placing siblings.
    // The document grows vertically inside the scroll view; it never compresses
    // panels to the viewport height or reparents controls during responsive reflow.
    CGFloat arrange(NSView* view, CGFloat width) {
        width = qMax<CGFloat>(1, width);
        if (view.hidden) { return 0; }
        if (layouts.contains(view)) {
            const Layout& layout = layouts[view];
            QVector<NSView*> children;
            for (NSView* child in layout.children) { if (!child.hidden) { children.append(child); } }
            const Node* containerNode = nodes.value(view, nullptr);
            CGFloat padding = layout.tag == "Panel" ? containerNode->attributes.value("padding", "20").toInt() : 0;
            CGFloat innerWidth = qMax<CGFloat>(1, width - 2 * padding);
            int columns = 1;
            if (layout.tag == "Inline" || (layout.tag == "RowPanel" && innerWidth >= layout.breakpoint)) { columns = qMax(1, int(children.size())); }
            if (layout.tag == "GridPanel") { columns = qMax(1, qMin(layout.columns, int((innerWidth + layout.gap) / (layout.minItemWidth + layout.gap)))); }
            CGFloat y = padding;
            for (int start = 0; start < children.size(); start += columns) {
                int count = qMin(columns, int(children.size()) - start);
                CGFloat available = qMax<CGFloat>(1, innerWidth - layout.gap * (count - 1));
                QVector<CGFloat> weights;
                CGFloat total = 0;
                for (int i = 0; i < count; ++i) {
                    const Node* node = nodes.value(children[start + i], nullptr);
                    CGFloat weight = node ? node->attributes.value("preferredWidth", "240").toDouble() : 240;
                    weights.append(qMax<CGFloat>(1, weight)); total += weights.last();
                }
                CGFloat x = padding, rowHeight = 0;
                for (int i = 0; i < count; ++i) {
                    NSView* child = children[start + i];
                    CGFloat childWidth = available * weights[i] / total;
                    if (layout.tag == "Inline" && count == 2) {
                        bool stepper = [children[1] isKindOfClass:NSStepper.class];
                        CGFloat fixed = stepper ? 20 : 40;
                        childWidth = (stepper ? i == 1 : i == 0) ? fixed : qMax<CGFloat>(1, available - fixed);
                    } else if (count == 2 && nodes.value(children[0]) && nodes.value(children[0])->tag == "Spinner") {
                        childWidth = i == 0 ? 20 : qMax<CGFloat>(1, available - 20);
                    }
                    CGFloat height = arrange(child, childWidth);
                    [child setFrame:NSMakeRect(x, y, childWidth, height)];
                    rowHeight = qMax(rowHeight, height); x += childWidth + layout.gap;
                }
                y += rowHeight + (start + count < children.size() ? layout.gap : 0);
            }
            y += padding;
            [view setFrameSize:NSMakeSize(width, y)];
            if (panelBorders.contains(view)) { [panelBorders[view] setFrame:view.bounds]; }
            return y;
        }
        const Node* node = nodes.value(view, nullptr);
        QString tag = node ? node->tag : "Label";
        CGFloat height = 26;
        if ([view isKindOfClass:NSTextField.class] && ![(NSTextField*)view isEditable]) {
            NSTextField* label = (NSTextField*)view;
            NSRect bounds = [label.stringValue boundingRectWithSize:NSMakeSize(qMax<CGFloat>(1, width - 4), CGFLOAT_MAX)
                options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                attributes:@{NSFontAttributeName:label.font}];
            height = label.stringValue.length ? std::ceil(bounds.size.height) + 4 : 0;
        } else if (tag == "TextArea") { height = node->attributes.value("height", "100").toInt(); }
        else if (tag == "Button" || tag == "Select") { height = 32; }
        else if (tag == "Switch") { height = 28; }
        else if (tag == "Spinner") { height = 20; }
        else if (tag == "ProgressBar") { height = 8; }
        else if (tag == "Separator") { height = 1; }
        else if (tag == "Spacer") { height = node->attributes.value("height", "12").toInt(); }
        [view setFrameSize:NSMakeSize(width, height)];
        if (tag == "TextArea") {
            NSScrollView* area = (NSScrollView*)view;
            [area.documentView setFrameSize:NSMakeSize(area.contentSize.width, qMax(height, area.documentView.frame.size.height))];
            [(NSTextView*)area.documentView textContainer].containerSize = NSMakeSize(area.contentSize.width, CGFLOAT_MAX);
        }
        return height;
    }
    void layoutDocument() {
        if (!layoutDirty && NSEqualSizes(viewportSize, scroll.contentSize)) { return; }
        layoutDirty = false; viewportSize = scroll.contentSize;
        CGFloat width = qMax<CGFloat>(1, scroll.contentSize.width - 48);
        CGFloat height = arrange(body, width);
        [body setFrame:NSMakeRect(24, 24, width, height)];
        [scroll.documentView setFrameSize:NSMakeSize(scroll.contentSize.width, qMax(scroll.contentSize.height, height + 48))];
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
            NSView* contents = stack();
            layouts[contents].tag = tag; layouts[contents].gap = a.value("gap", "12").toInt();
            layouts[contents].breakpoint = a.value("breakpoint", "700").toInt();
            layouts[contents].columns = a.value("columns", "3").toInt();
            layouts[contents].minItemWidth = a.value("minItemWidth", "240").toInt();
            if (tag == "Panel") {
                NSBox* border = [[[NSBox alloc] init] autorelease]; border.titlePosition = NSNoTitle;
                border.identifier = @"hyuiPanelBorder"; [contents addSubview:border]; panelBorders.insert(contents, border);
                if (!a.value("title").isEmpty()) {
                    NSTextField* title = [NSTextField labelWithString:text(a.value("title"))];
                    title.font = [NSFont boldSystemFontOfSize:12]; add(contents, title);
                }
            }
            for (const auto& child : node.children) { add(contents, build(child)); }
            view = contents;
        } else if (tag == "Label") {
            NSTextField* label = [NSTextField wrappingLabelWithString:@""]; label.maximumNumberOfLines = 0;
            if (a.value("tone") == "muted") { label.textColor = NSColor.secondaryLabelColor; }
            if (a.value("tone") == "accent") { label.textColor = NSColor.controlAccentColor; }
            if (a.value("role") == "title") { label.font = [NSFont boldSystemFontOfSize:28]; }
            else if (a.value("role") == "heading") { label.font = [NSFont boldSystemFontOfSize:15]; }
            else if (a.value("role") == "caption") { label.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium]; }
            view = label; control = label;
        } else if (tag == "Button" || tag == "CheckBox" || tag == "Switch") {
            if (tag == "Switch") {
                NSSwitch* toggle = [[[NSSwitch alloc] init] autorelease];
                HYAction* target = action([this, &node](id sender) { handleEvent(node, "checked", [(NSSwitch*)sender state] == NSControlStateValueOn, "onChange"); });
                toggle.target = target; toggle.action = @selector(fire:); control = toggle;
                NSView* row = stack(); layouts[row].tag = "Inline";
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
                NSView* row = stack(); layouts[row].tag = "Inline"; add(row, input); add(row, stepper); view = row; extra = stepper;
            }
        } else if (tag == "TextArea") {
            NSTextView* input = [[[NSTextView alloc] init] autorelease]; input.richText = NO; input.font = [NSFont systemFontOfSize:NSFont.systemFontSize];
            input.delegate = action([this, &node](id sender) { handleEvent(node, "text", string([(NSTextView*)sender string]), "onChange"); });
            NSScrollView* scroll = [[[NSScrollView alloc] init] autorelease]; scroll.documentView = input; scroll.hasVerticalScroller = YES;
            input.verticallyResizable = YES; input.horizontallyResizable = NO; input.textContainer.widthTracksTextView = YES; view = scroll; control = input;
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
        } else { view = [[[NSView alloc] init] autorelease]; }
        if (view) {
            if (a.contains("accessibleName")) { [view setAccessibilityLabel:text(a["accessibleName"])]; }
            view.identifier = text(node.id); nodes.insert(view, &node); [retained addObject:view]; if (control) { [retained addObject:control]; } items[node.id] = {view, control, extra, &node};
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
        applying = false; layoutDirty = true;
    }
public:
    AppKitView(const Document& document, Bridge& backend) : doc(document), bridge(backend) {
        [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1100, 820) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
        window.title = text(doc.window.attributes.value("title", "Hydrogen")); window.delegate = action({});
        QString theme = doc.window.attributes.value("theme", "system");
        if (theme != "system") { window.appearance = [NSAppearance appearanceNamed:theme == "dark" ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua]; }
        body = stack();
        for (const auto& node : doc.window.children) { add(body, build(node)); }
        error = [NSTextField wrappingLabelWithString:@""]; add(body, error);
        scroll = [[[NSScrollView alloc] init] autorelease]; scroll.hasVerticalScroller = YES; scroll.autohidesScrollers = YES;
        NSView* documentView = [[[HYLayoutView alloc] init] autorelease]; [documentView addSubview:body]; scroll.documentView = documentView;
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
        QObject::connect(&bridge, &Bridge::errorChanged, &bridge, [this] { error.stringValue = text(bridge.error()); layoutDirty = true; }); update();
    }
    void present(int width, int height) override {
        NSRect area = NSScreen.mainScreen.visibleFrame; [window setContentSize:NSMakeSize(qMin(width, int(area.size.width - 32)), qMin(height, int(area.size.height - 64)))];
        layoutDocument(); [scroll.contentView scrollToPoint:NSZeroPoint];
        [window center]; [window makeKeyAndOrderFront:nil]; [NSApp finishLaunching]; [NSApp activateIgnoringOtherApps:YES];
    }
    void pump() override {
        NSEvent* event;
        while ((event = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:NSDate.distantPast inMode:NSDefaultRunLoopMode dequeue:YES])) { [NSApp sendEvent:event]; }
        layoutDocument();
        [NSApp updateWindows];
    }
    bool screenshot(const QString& path) override {
        NSView* view = window.contentView; NSBitmapImageRep* image = [view bitmapImageRepForCachingDisplayInRect:view.bounds]; [view cacheDisplayInRect:view.bounds toBitmapImageRep:image];
        return [[image representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:text(path) atomically:YES];
    }
};
}
std::unique_ptr<NativeView> createAppKitView(const Document& doc, Bridge& bridge) {
    return std::make_unique<AppKitView>(doc, bridge);
}
int appkitMain(int argc, char** argv) {
    @autoreleasepool { return nativeMain(argc, argv, createAppKitView); }
}
}
