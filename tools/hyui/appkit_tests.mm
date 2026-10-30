#include "native_runtime.hpp"
#include <QCoreApplication>
#include <QFile>
#include <QFileInfo>
#include <QTemporaryDir>
#include <QElapsedTimer>
#include <QThread>
#include <iostream>
#include <stdexcept>
#import <AppKit/AppKit.h>

namespace {
void require(bool condition, const char* message) {
    if (!condition) { throw std::runtime_error(message); }
}
NSView* find(NSView* root, NSString* identifier) {
    if ([root.identifier isEqualToString:identifier]) { return root; }
    for (NSView* child in root.subviews) { if (NSView* result = find(child, identifier)) { return result; } }
    return nil;
}
NSRect rect(NSView* root, NSString* identifier) {
    NSView* view = find(root, identifier);
    require(view != nil, "missing sample control");
    NSView* document = find(root, @"projectName").enclosingScrollView.documentView;
    return [view convertRect:view.bounds toView:document];
}
void checkSiblings(NSView* root) {
    if (root.hidden) { return; }
    // Every content group uses a flipped document view. Its visible siblings
    // must stay in bounds and must not intersect, including below the viewport.
    if ([NSStringFromClass(root.class) isEqualToString:@"HYLayoutView"]) {
        NSArray<NSView*>* children = root.subviews;
        for (NSUInteger i = 0; i < children.count; ++i) {
            NSView* child = children[i]; if (child.hidden || [child.identifier isEqualToString:@"hyuiPanelBorder"]) { continue; }
            require(NSMinX(child.frame) >= -1 && NSMaxX(child.frame) <= root.bounds.size.width + 1, "control exceeds parent width");
            if (!(NSMinY(child.frame) >= -1 && NSMaxY(child.frame) <= root.bounds.size.height + 1)) {
                std::cerr << "parent " << (root.identifier.UTF8String ?: "unnamed") << " " << NSStringFromRect(root.bounds).UTF8String << " child " << (child.identifier.UTF8String ?: "unnamed") << " " << NSStringFromRect(child.frame).UTF8String << '\n';
                throw std::runtime_error("control exceeds parent height");
            }
            for (NSUInteger j = i + 1; j < children.count; ++j) {
                if (!children[j].hidden && ![children[j].identifier isEqualToString:@"hyuiPanelBorder"]) { require(!NSIntersectsRect(child.frame, children[j].frame), "overlapping sibling controls"); }
            }
        }
    }
    for (NSView* child in root.subviews) { checkSiblings(child); }
}
}
int main(int argc, char** argv) {
    QCoreApplication app(argc, argv);
    @autoreleasepool {
        try {
            require(argc == 3, "expected Studio.hyui and compiler paths");
            QTemporaryDir temporary; QProcess compiler;
            compiler.start(QString::fromUtf8(argv[2]), {"build", QFileInfo(QString::fromUtf8(argv[1])).absoluteDir().filePath("Studio.hyproj"), "-o", temporary.filePath("backend"), "--ui-backend", "--hide-progress", "--hide-log", "--hide-spinner"});
            require(compiler.waitForFinished(120000) && compiler.exitCode() == 0, "cannot build sample backend");
            QFile file(QString::fromUtf8(argv[1])); require(file.open(QIODevice::ReadOnly), "cannot open sample");
            hyui::Document document; require(document.parse(file.readAll()), "cannot parse sample");
            document.sourcePath = QFileInfo(file).absoluteFilePath();
            hyui::Bridge bridge(document, temporary.filePath("backend"), QFileInfo(file).absolutePath());
            auto view = hyui::createAppKitView(document, bridge);
            auto show = [&](int width) {
                view->present(width, 900); view->pump();
                NSView* root = NSApp.windows.firstObject.contentView;
                require(root != nil, "missing native window"); checkSiblings(root); return root;
            };
            require(bridge.apply("HYUI\tSET\tsummary\ttext\t" + QByteArray("A longer summary with enough words to exercise wrapping across responsive column widths. ").repeated(8) + "\n"), "cannot seed wrapping text");
            NSView* wide = show(1120);
            NSRect settings = rect(wide, @"projectName"), workspace = rect(wide, @"summary");
            CGFloat wideSummaryHeight = rect(wide, @"summary").size.height;
            require(NSMinX(workspace) > NSMaxX(settings), "wide panels must be side by side");
            require(rect(wide, @"notes").size.height == 70, "text area height must be preserved");
            NSView* narrow = show(360);
            NSRect narrowSettings = rect(narrow, @"projectName"), narrowWorkspace = rect(narrow, @"summary");
            require(NSMinY(narrowWorkspace) > NSMaxY(narrowSettings), "narrow panels must stack");
            require(rect(narrow, @"summary").size.height > wideSummaryHeight, "narrow text must wrap");
            NSScrollView* scroll = (NSScrollView*)find(narrow, @"projectName").enclosingScrollView;
            require(scroll.documentView.frame.size.height > scroll.contentSize.height, "narrow document must scroll");
            require(NSMinY(rect(narrow, @"workers")) > NSMaxY(rect(narrow, @"target")), "nested rows must reflow");
            require(bridge.apply("HYUI\tSET\tstatus\ttext\tA long status message that wraps over multiple lines after a backend event, while preserving space for every control below it.\n"), "cannot update status");
            view->pump(); checkSiblings(narrow);
            show(800); show(1120); show(360); show(1120);
            require(bridge.apply("HYUI\tSET\tquality\tvisible\tfalse\n"), "cannot hide slider");
            view->pump(); checkSiblings(NSApp.windows.firstObject.contentView);
            require(bridge.apply("HYUI\tSET\tpages\tvalue\t1\n"), "cannot select gallery"); view->pump();
            show(360); show(1120);
            NSView* gallery = NSApp.windows.firstObject.contentView; checkSiblings(gallery);
            require([(NSImageView*)find(gallery, @"logo") image] != nil, "bundled image did not load");
            auto finish = [&] { QElapsedTimer timeout; timeout.start(); while (bridge.busy() && timeout.elapsed() < 5000) { app.processEvents(); view->pump(); QThread::msleep(1); } require(!bridge.busy() && bridge.error().isEmpty(), "sample event failed"); };
            NSView* radio = find(gallery, @"channel"); require(radio.subviews.count == 3, "radio choices missing");
            [(NSButton*)radio.subviews[1] performClick:nil]; finish();
            require(bridge.state()["channel.value"].toInt() == 1 && bridge.state()["channelText.text"].toString() == "Preview channel selected.", "radio event failed");
            NSScrollView* list = (NSScrollView*)find(gallery, @"templates"); NSTableView* table = (NSTableView*)list.documentView;
            [table selectRowIndexes:[NSIndexSet indexSetWithIndex:2] byExtendingSelection:NO]; finish();
            require(bridge.state()["selectionText.text"].toString() == "Template index: 2", "list event failed");
            NSScrollView* projects = (NSScrollView*)find(gallery, @"projects");
            [(NSTableView*)projects.documentView selectRowIndexes:[NSIndexSet indexSetWithIndex:1] byExtendingSelection:NO]; finish();
            require(bridge.state()["selectionText.text"].toString() == "Project index: 1", "table event failed");
            [(NSButton*)find(gallery, @"showDialog") performClick:nil]; finish(); app.processEvents(); view->pump();
            NSWindow* window = NSApp.windows.firstObject;
            if (!window.attachedSheet) { for (NSWindow* candidate in NSApp.windows) { if (candidate.attachedSheet) { window = candidate; break; } } }
            require(window.attachedSheet != nil, "native confirmation sheet did not open");
            [window endSheet:window.attachedSheet returnCode:NSAlertFirstButtonReturn];
            for (int i = 0; i < 100; ++i) { app.processEvents(); view->pump(); QThread::msleep(2); } finish();
            require(!bridge.state()["confirmation.open"].toBool() && bridge.state()["dialogResult.text"].toString().startsWith("Confirmed."), "dialog result event failed");
            NSSegmentedControl* tabs = (NSSegmentedControl*)find(gallery, @"pages").subviews.firstObject;
            tabs.selectedSegment = 0; [tabs sendAction:tabs.action to:tabs.target]; finish();
            require(bridge.state()["pages.value"].toInt() == 0, "tab selection event failed");
            tabs.selectedSegment = 1; [tabs sendAction:tabs.action to:tabs.target]; finish();
            require(bridge.state()["pages.value"].toInt() == 1, "tab return event failed");
            NSMenuItem* menu = [NSApp.mainMenu itemAtIndex:1]; NSMenuItem* workspaceItem = [menu.submenu itemAtIndex:0];
            [workspaceItem.target performSelector:workspaceItem.action withObject:workspaceItem]; finish();
            require(bridge.state()["pages.value"].toInt() == 0, "menu event failed");
            std::cout << "AppKit layout passed: wide/narrow panels, wrapping, bounds, non-overlap, scrolling, resize, backend updates, hidden controls, menus, tabs, list/table/radio events, images, native dialog responses\n";
            return 0;
        } catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
    }
}
