#include "native_runtime.hpp"
#include <QCoreApplication>
#include <QTimer>
#include <QMap>
#include <QPointer>
#include <cmath>
#import <AppKit/AppKit.h>

// All interactive elements in this renderer are AppKit objects. AppKit owns
// window decorations, control drawing, accessibility, focus and system themes.
@interface HYLayoutView : NSView
@end
@implementation HYLayoutView
- (BOOL)isFlipped { return YES; }
@end

@interface HYAction : NSObject<NSTextFieldDelegate, NSTextViewDelegate, NSWindowDelegate, NSTableViewDelegate, NSTableViewDataSource, NSToolbarDelegate, NSPopoverDelegate, NSSplitViewDelegate> {
@public
    std::function<void(id)> callback;
    NSArray* tableRows;
    NSArray<NSString*>* toolbarIdentifiers;
    NSDictionary<NSString*, NSButton*>* toolbarButtons;
}
- (void)fire:(id)sender;
@end
@implementation HYAction
- (void)fire:(id)sender { if (callback) { callback(sender); } }
- (void)controlTextDidChange:(NSNotification*)note { [self fire:note.object]; }
- (void)textDidChange:(NSNotification*)note { [self fire:note.object]; }
- (NSInteger)numberOfRowsInTableView:(NSTableView*)table { return tableRows.count; }
- (NSView*)tableView:(NSTableView*)table viewForTableColumn:(NSTableColumn*)column row:(NSInteger)row {
    return [NSTextField labelWithString:tableRows[row][column.identifier.integerValue]];
}
- (void)tableViewSelectionDidChange:(NSNotification*)note { [self fire:note.object]; }
- (BOOL)windowShouldClose:(NSWindow*)window { QCoreApplication::quit(); return YES; }
- (void)popoverDidClose:(NSNotification*)note { [self fire:note.object]; }
- (void)splitViewDidResizeSubviews:(NSNotification*)note { [self fire:note.object]; }
- (NSArray<NSString*>*)toolbarAllowedItemIdentifiers:(NSToolbar*)toolbar { return toolbarIdentifiers; }
- (NSArray<NSString*>*)toolbarDefaultItemIdentifiers:(NSToolbar*)toolbar { return toolbarIdentifiers; }
- (NSToolbarItem*)toolbar:(NSToolbar*)toolbar itemForItemIdentifier:(NSToolbarItemIdentifier)identifier willBeInsertedIntoToolbar:(BOOL)flag {
    NSButton* button = toolbarButtons[identifier];
    if (!button) { return nil; }
    NSToolbarItem* item = [[[NSToolbarItem alloc] initWithItemIdentifier:identifier] autorelease];
    item.label = button.title; item.paletteLabel = button.title; item.view = button;
    return item;
}
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
    QObject signalScope;
    NSWindow* window;
    NSMutableArray* retained = [NSMutableArray new];
    QMap<QString, Item> items;
    QMap<NSView*, Layout> layouts;
    QMap<NSView*, NSView*> scrollContents;
    QMap<NSView*, NSBox*> panelBorders;
    QMap<NSView*, const Node*> nodes;
    NSView* body;
    NSScrollView* scroll;
    QVector<QTimer*> timers;
    QMap<QString, NSMenuItem*> menuItems;
    QVector<const Node*> dialogs;
    QMap<QString, NSAlert*> alerts;
    QMap<QString, NSPopover*> popovers;
    QMap<QString, NSTextField*> popoverLabels;
    QMap<QString, NSView*> popoverContents;
    QMap<QString, NSView*> popoverFrames;
    bool applying = false;
    bool disposing = false;
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
        if (tag == "SplitView") {
            CGFloat height = node->attributes.value("height", "260").toInt();
            NSSplitView* split = (NSSplitView*)view;
            [split setFrameSize:NSMakeSize(width, height)];
            if (split.subviews.count == 2) {
                const CGFloat maxDivider = qMax<CGFloat>(0, width - split.dividerThickness);
                const CGFloat target = qBound<CGFloat>(0, bridge.state().value(node->id + ".value").toInt(), maxDivider);
                [split setPosition:target ofDividerAtIndex:0];
                [split adjustSubviews];
                for (NSView* pane in split.subviews) {
                    CGFloat paneWidth = qMax<CGFloat>(1, pane.frame.size.width);
                    arrange(pane, paneWidth);
                    [pane setFrameSize:NSMakeSize(paneWidth, height)];
                }
            }
            return height;
        }
        if (tag == "ScrollView") {
            CGFloat height = node->attributes.value("height", "200").toInt();
            [view setFrameSize:NSMakeSize(width, height)];
            NSScrollView* area = (NSScrollView*)view;
            NSView* contents = scrollContents.value(view);
            CGFloat innerWidth = qMax<CGFloat>(1, area.contentSize.width);
            CGFloat contentHeight = arrange(contents, innerWidth);
            [contents setFrameOrigin:NSZeroPoint];
            [area.documentView setFrameSize:NSMakeSize(innerWidth, qMax(height, contentHeight))];
            return height;
        }
        CGFloat height = 26;
        if ([view isKindOfClass:NSTextField.class] && ![(NSTextField*)view isEditable]) {
            NSTextField* label = (NSTextField*)view;
            NSRect bounds = [label.stringValue boundingRectWithSize:NSMakeSize(qMax<CGFloat>(1, width - 4), CGFLOAT_MAX)
                options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                attributes:@{NSFontAttributeName:label.font}];
            height = label.stringValue.length ? std::ceil(bounds.size.height) + 4 : 0;
        } else if (tag == "TextArea") { height = node->attributes.value("height", "100").toInt(); }
        else if (tag == "Button" || tag == "ToggleButton" || tag == "Select") { height = 32; }
        else if (tag == "Switch") { height = 28; }
        else if (tag == "Spinner") { height = 20; }
        else if (tag == "ProgressBar") { height = 8; }
        else if (tag == "Separator") { height = 1; }
        else if (tag == "ListBox" || tag == "Table") { height = node->attributes.value("height", "160").toInt(); }
        else if (tag == "Image") { height = node->attributes.value("height", "72").toInt(); }
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
        if (applying || bridge.isApplying() || (event == "onChange" && bridge.state().value(node.id + '.' + property) == value)) { return; }
        bridge.store(node.id, property, value);
        if (node.attributes.contains(event)) { bridge.dispatch(node.attributes[event], node.id); }
    }
    NSMenuItem* makeMenuItem(const Node& entry) {
        const QString shortcut = entry.attributes.value("shortcut");
        NSString* key = shortcut.isEmpty() ? @"" : text(shortcut.right(1).toLower());
        NSMenuItem* item = [[[NSMenuItem alloc] initWithTitle:text(entry.attributes.value("text")) action:@selector(fire:) keyEquivalent:key] autorelease];
        if (!shortcut.isEmpty()) { item.keyEquivalentModifierMask = NSEventModifierFlagCommand | (shortcut.contains("+Shift+") ? NSEventModifierFlagShift : 0); }
        item.target = action([this, &entry](id) { if (entry.attributes.contains("checked")) { bridge.store(entry.id, "checked", !bridge.state().value(entry.id + ".checked").toBool()); update(); } if (entry.attributes.contains("onClick")) { bridge.dispatch(entry.attributes["onClick"], entry.id); } });
        menuItems.insert(entry.id, item);
        return item;
    }
    void buildMenu(const Node& node) {
        NSMenu* bar = [[[NSMenu alloc] init] autorelease]; bar.autoenablesItems = NO;
        NSMenuItem* application = [[[NSMenuItem alloc] initWithTitle:@"Hydrogen" action:nil keyEquivalent:@""] autorelease];
        NSMenu* appMenu = [[[NSMenu alloc] initWithTitle:@"Hydrogen"] autorelease];
        [appMenu addItemWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"]; application.submenu = appMenu; [bar addItem:application];
        for (const Node& menu : node.children) {
            NSMenuItem* heading = [[[NSMenuItem alloc] initWithTitle:text(menu.attributes.value("text")) action:nil keyEquivalent:@""] autorelease];
            NSMenu* submenu = [[[NSMenu alloc] initWithTitle:heading.title] autorelease]; submenu.autoenablesItems = NO;
            for (const Node& entry : menu.children) { [submenu addItem:makeMenuItem(entry)]; }
            heading.submenu = submenu; [bar addItem:heading]; menuItems.insert(menu.id, heading);
        }
        NSApp.mainMenu = bar;
    }
    void attachContextMenus() {
        for (const Node& node : doc.window.children) {
            if (node.tag != "ContextMenu") { continue; }
            NSMenu* menu = [[[NSMenu alloc] initWithTitle:@""] autorelease]; menu.autoenablesItems = NO;
            for (const Node& entry : node.children) { [menu addItem:makeMenuItem(entry)]; }
            Item target = items.value(node.attributes.value("target"));
            target.view.menu = menu;
            if ([target.control isKindOfClass:NSView.class]) { [(NSView*)target.control setMenu:menu]; }
        }
    }
    void attachPopovers() {
        for (const Node& node : doc.window.children) {
            if (node.tag != "Popover") { continue; }
            NSPopover* popover = [[[NSPopover alloc] init] autorelease];
            popover.behavior = NSPopoverBehaviorTransient;
            NSViewController* controller = [[[NSViewController alloc] init] autorelease];
            NSView* frame = [[[HYLayoutView alloc] initWithFrame:NSMakeRect(0, 0, 300, 72)] autorelease];
            frame.identifier = text(node.id);
            NSView* contents = stack();
            layouts[contents].gap = 8;
            [frame addSubview:contents];
            NSTextField* label = [NSTextField wrappingLabelWithString:text(node.attributes.value("text"))];
            add(contents,label);
            // Popovers host the same native AppKit controls as normal panels,
            // including independently dispatched Hydrogen event handlers.
            for(const Node& child:node.children)add(contents,build(child));
            controller.view = frame; popover.contentViewController = controller;
            popover.delegate = action([this, &node](id) {
                if (!bridge.state().value(node.id + ".open").toBool()) { return; }
                bridge.store(node.id, "open", false);
                if (node.attributes.contains("onClose")) { bridge.dispatch(node.attributes["onClose"], node.id); }
            });
            [retained addObject:popover]; popovers.insert(node.id, popover);
            popoverLabels.insert(node.id, label);
            popoverContents.insert(node.id, contents);
            popoverFrames.insert(node.id, frame);
        }
    }
    void updateDialogs() {
        for (const Node* node : dialogs) {
            const bool open = bridge.state().value(node->id + ".open").toBool();
            if (!open && alerts.contains(node->id)) { [window endSheet:alerts[node->id].window returnCode:NSModalResponseCancel]; }
            if (!open || !alerts.isEmpty()) { continue; }
            NSAlert* alert = [[[NSAlert alloc] init] autorelease]; [retained addObject:alert]; alerts.insert(node->id, alert);
            alert.messageText = text(node->attributes.value("title", "Hydrogen"));
            alert.informativeText = text(bridge.state().value(node->id + ".text").toString());
            for (const QString& button : node->attributes.value("buttons", "OK").split('|')) { [alert addButtonWithTitle:text(button)]; }
            QPointer<QObject> alive(&signalScope);
            QTimer::singleShot(0, &signalScope, [this, node, alert, alive] {
                [alert beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
                    if (!alive || disposing) { return; }
                    alerts.remove(node->id);
                    if (!bridge.state().value(node->id + ".open").toBool()) { updateDialogs(); return; }
                    bridge.store(node->id, "open", false);
                    int count = node->attributes.value("buttons", "OK").split('|').size();
                    handleEvent(*node, "value", response >= NSAlertFirstButtonReturn ? int(response - NSAlertFirstButtonReturn) : count - 1, "onClose"); updateDialogs();
                }];
            });
        }
    }
    NSView* build(const Node& node) {
        const auto& a = node.attributes; QString tag = node.tag;
        if (tag == "State") { return nil; }
        if (tag == "MenuBar") { buildMenu(node); return nil; }
        if (tag == "Toolbar") {
            NSMutableArray<NSString*>* identifiers = [NSMutableArray array];
            NSMutableDictionary<NSString*, NSButton*>* buttons = [NSMutableDictionary dictionary];
            for (const Node& child : node.children) {
                NSButton* button = (NSButton*)build(child);
                button.title = text(child.attributes.value("text"));
                NSString* identifier = text(child.id);
                [identifiers addObject:identifier]; buttons[identifier] = button;
            }
            HYAction* delegate = action(nullptr);
            delegate->toolbarIdentifiers = identifiers; delegate->toolbarButtons = buttons;
            [retained addObject:identifiers]; [retained addObject:buttons];
            NSToolbar* toolbar = [[[NSToolbar alloc] initWithIdentifier:@"HydrogenToolbar"] autorelease];
            toolbar.delegate = delegate; toolbar.allowsUserCustomization = NO;
            window.toolbar = toolbar;
            return nil;
        }
        if (tag == "ContextMenu") { return nil; }
        if (tag == "Popover") { return nil; }
        if (tag == "Clipboard") { return nil; }
        if (tag == "Dialog") { dialogs.append(&node); return nil; }
        if (tag == "Timer") {
            QTimer* timer = new QTimer(&bridge); timer->setObjectName(node.id); timer->setInterval(a.value("interval", "1000").toInt());
            QObject::connect(timer, &QTimer::timeout, &signalScope, [this, &node] { bridge.dispatch(node.attributes["onTick"], node.id); }); timers.append(timer); return nil;
        }
        NSView* view = nil; id control = nil; id extra = nil;
        if (tag == "SplitView") {
            NSSplitView* split = [[[NSSplitView alloc] init] autorelease];
            split.vertical = YES;
            split.dividerStyle = NSSplitViewDividerStyleThin;
            for (const Node& pane : node.children) { NSView* child = build(pane); if (child) { [split addSubview:child]; } }
            split.delegate = action([this, &node](id sender) {
                NSSplitView* pane = (NSSplitView*)sender;
                if (pane.subviews.count == 2 && pane.bounds.size.width > 0) {
                    handleEvent(node, "value", int(std::round(pane.subviews[0].frame.size.width)), "onChange");
                }
            });
            view = split; control = split;
        } else if (tag == "Tabs") {
            view = stack(); NSSegmentedControl* tabs = [[[NSSegmentedControl alloc] init] autorelease];
            tabs.segmentCount = node.children.size(); tabs.segmentDistribution = NSSegmentDistributionFill;
            tabs.trackingMode = NSSegmentSwitchTrackingSelectOne; int index = 0;
            for (const Node& page : node.children) { [tabs setLabel:text(page.attributes.value("title")) forSegment:index++]; }
            tabs.target = action([this, &node](id sender) { handleEvent(node, "value", int([(NSSegmentedControl*)sender selectedSegment]), "onChange"); update(); }); tabs.action = @selector(fire:);
            add(view, tabs); for (const Node& page : node.children) { add(view, build(page)); }
            control = tabs;
        } else if (tag == "RadioGroup") {
            view = stack();
            int index = 0;
            for (const QString& label : a.value("items").split('|')) {
                NSButton* radio = [NSButton radioButtonWithTitle:text(label) target:nil action:@selector(fire:)]; radio.tag = index++;
                radio.target = action([this, &node](id sender) { handleEvent(node, "value", int([(NSButton*)sender tag]), "onChange"); }); add(view, radio);
            }
        } else if (tag == "ListBox" || tag == "Table") {
            NSTableView* table = [[[NSTableView alloc] init] autorelease]; table.allowsEmptySelection = NO; table.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
            QStringList headings = tag == "Table" ? a.value("columns").split('|') : QStringList{""};
            int index = 0; for (const QString& heading : headings) {
                NSTableColumn* column = [[[NSTableColumn alloc] initWithIdentifier:text(QString::number(index++))] autorelease]; column.title = text(heading); [table addTableColumn:column];
            }
            if (tag == "ListBox") { table.headerView = nil; }
            NSMutableArray* rows = [NSMutableArray array];
            for (const QString& row : a.value(tag == "Table" ? "rows" : "items").split(tag == "Table" ? '\n' : '|')) {
                NSMutableArray* cells = [NSMutableArray array]; for (const QString& cell : (tag == "Table" ? row.split('|') : QStringList{row})) { [cells addObject:text(cell)]; } [rows addObject:cells];
            }
            [retained addObject:rows]; HYAction* delegate = action([this, &node](id sender) {
                NSInteger selection = [(NSTableView*)sender selectedRow]; if (selection >= 0) { handleEvent(node, "value", int(selection), "onChange"); }
            }); delegate->tableRows = rows; table.delegate = delegate; table.dataSource = delegate;
            NSScrollView* area = [[[NSScrollView alloc] init] autorelease]; area.documentView = table; area.hasVerticalScroller = YES; area.hasHorizontalScroller = YES;
            area.borderType = NSBezelBorder; view = area; control = table;
        } else if (tag == "Image") {
            NSImageView* image = [[[NSImageView alloc] init] autorelease]; image.image = [[[NSImage alloc] initWithContentsOfFile:text(doc.resourcePath(a.value("source")))] autorelease];
            if (!image.image) { throw std::runtime_error("cannot decode image asset"); }
            image.imageScaling = NSImageScaleProportionallyUpOrDown; view = image;
        } else if (tag == "ScrollView") {
            NSView* contents = stack(); layouts[contents].gap = a.value("gap", "12").toInt();
            for (const auto& child : node.children) { add(contents, build(child)); }
            NSView* documentView = [[[HYLayoutView alloc] init] autorelease]; [documentView addSubview:contents];
            NSScrollView* area = [[[NSScrollView alloc] init] autorelease]; area.documentView = documentView;
            area.hasVerticalScroller = YES; area.autohidesScrollers = YES;
            scrollContents.insert(area, contents); view = area; control = area;
        } else if (tag == "ColumnPanel" || tag == "RowPanel" || tag == "GridPanel" || tag == "Panel" || tag == "Tab") {
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
        } else if (tag == "Label" || tag == "ValidationMessage" || tag == "StatusBar") {
            NSTextField* label = [NSTextField wrappingLabelWithString:@""]; label.maximumNumberOfLines = 0;
            if (tag == "StatusBar") { label.font = [NSFont systemFontOfSize:11]; label.textColor = NSColor.secondaryLabelColor; }
            if (a.value("tone") == "muted") { label.textColor = NSColor.secondaryLabelColor; }
            if (a.value("tone") == "accent") { label.textColor = NSColor.controlAccentColor; }
            if (tag == "ValidationMessage") {
                QString severity = a.value("severity", "error");
                label.textColor = severity == "warning" ? NSColor.systemOrangeColor :
                    severity == "success" ? NSColor.systemGreenColor :
                    severity == "info" ? NSColor.controlAccentColor : NSColor.systemRedColor;
            }
            if (a.value("role") == "title") { label.font = [NSFont boldSystemFontOfSize:28]; }
            else if (a.value("role") == "heading") { label.font = [NSFont boldSystemFontOfSize:15]; }
            else if (a.value("role") == "caption") { label.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium]; }
            view = label; control = label;
        } else if (tag == "FilePicker") {
            NSButton* button = [NSButton buttonWithTitle:@"" target:nil action:@selector(fire:)];
            button.bezelStyle = NSBezelStyleRounded;
            button.target = action([this, &node](id) {
                const QString mode = node.attributes.value("mode");
                NSSavePanel* panel = mode == "save" ? [NSSavePanel savePanel] : [NSOpenPanel openPanel];
                if (mode != "save") {
                    NSOpenPanel* open = (NSOpenPanel*)panel;
                    open.canChooseFiles = mode == "open";
                    open.canChooseDirectories = mode == "folder";
                    open.allowsMultipleSelection = NO;
                }
                panel.title = text(node.attributes.value("text"));
                [retained addObject:panel];
                QPointer<QObject> alive(&signalScope);
                [panel beginSheetModalForWindow:window completionHandler:^(NSModalResponse response) {
                    if (!alive || disposing) { return; }
                    if (response == NSModalResponseOK && panel.URL.path) {
                        handleEvent(node, "path", string(panel.URL.path), "onPick");
                    } else if (node.attributes.contains("onCancel")) {
                        bridge.dispatch(node.attributes["onCancel"], node.id);
                    }
                    [retained removeObject:panel];
                }];
            }); view = button; control = button;
        } else if (tag == "Button" || tag == "ToolButton" || tag == "CheckBox" || tag == "Switch" || tag == "ToggleButton") {
            if (tag == "Switch") {
                NSSwitch* toggle = [[[NSSwitch alloc] init] autorelease];
                HYAction* target = action([this, &node](id sender) { handleEvent(node, "checked", [(NSSwitch*)sender state] == NSControlStateValueOn, "onChange"); });
                toggle.target = target; toggle.action = @selector(fire:); control = toggle;
                NSView* row = stack(); layouts[row].tag = "Inline";
                add(row, toggle); add(row, [NSTextField labelWithString:text(a.value("text"))]); view = row;
            } else {
                NSButton* button = [NSButton buttonWithTitle:@"" target:nil action:@selector(fire:)];
                if (tag == "CheckBox") { [button setButtonType:NSButtonTypeSwitch]; }
                else if (tag == "ToggleButton") { [button setButtonType:NSButtonTypePushOnPushOff]; button.bezelStyle = NSBezelStyleRounded; }
                else { button.bezelStyle = NSBezelStyleRounded; if (a.value("primary") == "true") { button.keyEquivalent = @"\r"; } }
                button.target = action([this, &node, tag](id sender) {
                    if (tag == "CheckBox" || tag == "ToggleButton") { handleEvent(node, "checked", [(NSButton*)sender state] == NSControlStateValueOn, "onChange"); }
                    else if (node.attributes.contains("onClick")) { bridge.dispatch(node.attributes["onClick"], node.id); }
                }); view = button; control = button;
            }
        } else if (tag == "Input" || tag == "SearchInput" || tag == "PasswordInput" || tag == "NumberInput") {
            NSTextField* input = tag == "SearchInput" ? (NSTextField*)[[[NSSearchField alloc] init] autorelease] : tag == "PasswordInput" ? (NSTextField*)[[[NSSecureTextField alloc] init] autorelease] : [[[NSTextField alloc] init] autorelease]; input.placeholderString = text(a.value("placeholder"));
            input.delegate = action([this, &node, tag](id sender) {
                if (tag == "PasswordInput") {
                    if (!bridge.storeSecret(node.id, string([(NSTextField*)sender stringValue]))) { return; }
                    if (node.attributes.contains("onChange")) { bridge.dispatch(node.attributes["onChange"], node.id); }
                } else {
                    handleEvent(node, tag == "NumberInput" ? "value" : "text", tag == "NumberInput" ? QVariant(int([(NSTextField*)sender intValue])) : QVariant(string([(NSTextField*)sender stringValue])), "onChange");
                }
            });
            input.target = action([this, &node, input](id) {
                if (node.attributes.contains("onSubmit")) {
                    if (node.tag == "PasswordInput" && !bridge.storeSecret(node.id, string(input.stringValue))) { return; }
                    bridge.dispatch(node.attributes["onSubmit"], node.id);
                }
            }); input.action = @selector(fire:);
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
            if (a.contains("tooltip")) { view.toolTip = text(a["tooltip"]); }
            view.identifier = text(node.id); nodes.insert(view, &node); [retained addObject:view]; if (control) { [retained addObject:control]; } items[node.id] = {view, control, extra, &node};
        }
        return view;
    }
    void update() {
        applying = true; auto state = bridge.state();
        for (auto it = menuItems.cbegin(); it != menuItems.cend(); ++it) {
            it.value().title = text(state.value(it.key() + ".text").toString());
            it.value().enabled = state.value(it.key() + ".enabled").toBool(); it.value().hidden = !state.value(it.key() + ".visible").toBool();
            it.value().state = state.value(it.key() + ".checked").toBool() ? NSControlStateValueOn : NSControlStateValueOff;
        }
        for (auto it = items.cbegin(); it != items.cend(); ++it) {
            Item c = it.value(); auto value = [&](QString p) { return state.value(it.key() + '.' + p); }; QString tag = c.node->tag;
            if (tag != "Tab") { c.view.hidden = !value("visible").toBool(); }
            bool enabled = value("enabled").toBool();
            if (tag == "ToolButton") {
                for (const Node& parent : doc.window.children) { if (parent.tag == "Toolbar") { enabled = enabled && state.value(parent.id + ".enabled").toBool(); break; } }
            }
            if ([c.control respondsToSelector:@selector(setEnabled:)]) { [c.control setEnabled:enabled]; }
            if (tag == "Label" || tag == "ValidationMessage" || tag == "StatusBar" || tag == "Input" || tag == "SearchInput") { if (string([c.control stringValue]) != value("text").toString()) { [c.control setStringValue:text(value("text").toString())]; } }
            if (tag == "TextArea") { if (string([(NSTextView*)c.control string]) != value("text").toString()) { [(NSTextView*)c.control setString:text(value("text").toString())]; } }
            if (tag == "Button" || tag == "ToolButton" || tag == "ToggleButton" || tag == "FilePicker" || tag == "CheckBox") { [(NSButton*)c.control setTitle:text(value("text").toString())]; }
            if (tag == "CheckBox" || tag == "ToggleButton" || tag == "Switch") { [c.control setState:value("checked").toBool() ? NSControlStateValueOn : NSControlStateValueOff]; }
            if (tag == "SplitView" && c.view.bounds.size.width > 0) {
                NSSplitView* split = (NSSplitView*)c.view;
                CGFloat target = qBound<CGFloat>(0, value("value").toInt(),
                    qMax<CGFloat>(0, split.bounds.size.width - split.dividerThickness));
                if (split.subviews.count == 2 && std::abs(split.subviews[0].frame.size.width - target) > 1) {
                    [split setPosition:target ofDividerAtIndex:0];
                }
            }
            if (tag == "Tabs") {
                [(NSSegmentedControl*)c.control setSelectedSegment:value("value").toInt()]; int index = 0;
                for (const Node& page : c.node->children) { items[page.id].view.hidden = index++ != value("value").toInt() || !state.value(page.id + ".visible").toBool(); }
            }
            if (tag == "ListBox" || tag == "Table") { [(NSTableView*)c.control selectRowIndexes:[NSIndexSet indexSetWithIndex:value("value").toUInt()] byExtendingSelection:NO]; }
            if (tag == "RadioGroup") { for (NSButton* button in layouts[c.view].children) { button.enabled = value("enabled").toBool(); button.state = button.tag == value("value").toInt() ? NSControlStateValueOn : NSControlStateValueOff; } }
            if (tag == "Select") { [(NSPopUpButton*)c.control selectItemAtIndex:value("value").toInt()]; }
            if (tag == "Slider" || tag == "NumberInput" || tag == "ProgressBar") { [c.control setDoubleValue:value("value").toDouble()]; if (c.extra) { [c.extra setDoubleValue:value("value").toDouble()]; } }
            if (tag == "Spinner" || tag == "ProgressBar") { NSProgressIndicator* p = c.control; p.indeterminate = tag == "Spinner" || value("indeterminate").toBool(); if ((tag == "Spinner" && value("running").toBool()) || (tag == "ProgressBar" && p.indeterminate)) { [p startAnimation:nil]; } else { [p stopAnimation:nil]; } }
        }
        for (auto it = items.cbegin(); it != items.cend(); ++it) {
            if (it.value().node->tag != "ScrollView" || state.value(it.key() + ".enabled").toBool()) { continue; }
            for (const Item& child : items) {
                if ([child.view isDescendantOf:it.value().view] && [child.control respondsToSelector:@selector(setEnabled:)]) { [child.control setEnabled:NO]; }
            }
        }
        for (QTimer* timer : timers) { bool running = state.value(timer->objectName() + ".running").toBool(); if (running && !timer->isActive()) { timer->start(); } if (!running) { timer->stop(); } }
        for (auto it = popovers.cbegin(); it != popovers.cend(); ++it) {
            NSPopover* popover = it.value();
            NSString* labelText = text(state.value(it.key() + ".text").toString());
            NSTextField* label = popoverLabels[it.key()];
            label.stringValue = labelText;
            label.hidden = labelText.length == 0;
            NSView* contents = popoverContents[it.key()];
            NSView* frame = popoverFrames[it.key()];
            CGFloat contentHeight = qMax<CGFloat>(48,arrange(contents,276));
            [contents setFrame:NSMakeRect(12,12,276,contentHeight)];
            [frame setFrameSize:NSMakeSize(300,contentHeight+24)];
            popover.contentSize = NSMakeSize(300,contentHeight+24);
            bool open = state.value(it.key() + ".open").toBool();
            if (!open && popover.shown) { [popover close]; }
            if (open && !popover.shown && window.isVisible) {
                const Node* node = nullptr;
                for (const Node& child : doc.window.children) { if (child.id == it.key()) { node = &child; break; } }
                NSView* target = items.value(node->attributes.value("target")).view;
                [popover showRelativeToRect:target.bounds ofView:target preferredEdge:NSMaxYEdge];
            }
        }
        for (const Node& node : doc.window.children) {
            if (node.tag == "Toolbar") {
                bool visible = state.value(node.id + ".visible").toBool();
                if (window.toolbar.visible != visible) {
                    NSSize contentSize = window.contentView.bounds.size;
                    window.toolbar.visible = visible;
                    [window setContentSize:contentSize];
                }
                for (NSToolbarItem* item in window.toolbar.items) {
                    item.label = text(state.value(string(item.itemIdentifier) + ".text").toString());
                }
                break;
            }
        }
        applying = false; layoutDirty = true; updateDialogs();
    }
public:
    AppKitView(const Document& document, Bridge& backend) : doc(document), bridge(backend) {
        [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1100, 820) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
        window.releasedWhenClosed = NO;
        window.title = text(doc.window.attributes.value("title", "Hydrogen")); window.delegate = action({});
        QString theme = doc.window.attributes.value("theme", "system");
        if (theme != "system") { window.appearance = [NSAppearance appearanceNamed:theme == "dark" ? NSAppearanceNameDarkAqua : NSAppearanceNameAqua]; }
        body = stack();
        for (const auto& node : doc.window.children) { add(body, build(node)); }
        attachContextMenus();
        attachPopovers();
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
        QObject::connect(&bridge, &Bridge::changed, &signalScope, [this] { update(); });
        QObject::connect(&bridge, &Bridge::errorChanged, &signalScope, [this] { error.stringValue = text(bridge.error()); layoutDirty = true; }); update();
        QObject::connect(&bridge, &Bridge::clipboardRequested, &signalScope, [this](const QString& id, const QString& operation, const QString& value) {
            NSPasteboard* pasteboard = NSPasteboard.generalPasteboard;
            if (operation == "WRITE") { [pasteboard clearContents]; [pasteboard setString:text(value) forType:NSPasteboardTypeString]; return; }
            const QString contents = string([pasteboard stringForType:NSPasteboardTypeString]);
            for (const Node& node : doc.window.children) {
                if (node.id == id && bridge.storeClipboardText(id, contents)) { bridge.dispatch(node.attributes.value("onRead"), id); break; }
            }
        });
    }
    ~AppKitView() override {
        disposing = true;
        QObject::disconnect(&bridge, nullptr, &signalScope, nullptr);
        for (QTimer* timer : timers) { timer->stop(); }
        for (NSPopover* popover : popovers) { popover.delegate = nil; [popover close]; }
        for (NSAlert* alert : alerts) { if (window.attachedSheet == alert.window) { [window endSheet:alert.window returnCode:NSModalResponseCancel]; } }
        window.delegate = nil;
        window.toolbar.delegate = nil;
        NSApp.mainMenu = nil;
        [window close]; [window release]; window = nil;
        [retained release]; retained = nil;
    }
    void present(int width, int height) override {
        NSRect area = NSScreen.mainScreen.visibleFrame; [window setContentSize:NSMakeSize(qMin(width, int(area.size.width - 32)), qMin(height, int(area.size.height - 64)))];
        layoutDocument(); [scroll.contentView scrollToPoint:NSZeroPoint];
        [window center]; [window makeKeyAndOrderFront:nil]; [NSApp finishLaunching]; [NSApp activateIgnoringOtherApps:YES];
        update();
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
