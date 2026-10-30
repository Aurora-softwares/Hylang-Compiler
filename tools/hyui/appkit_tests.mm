#include "native_runtime.hpp"
#include <QCoreApplication>
#include <QFile>
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
            require(argc == 2, "expected Studio.hyui path");
            QFile file(QString::fromUtf8(argv[1])); require(file.open(QIODevice::ReadOnly), "cannot open sample");
            hyui::Document document; require(document.parse(file.readAll()), "cannot parse sample");
            hyui::Bridge bridge(document, {}, {});
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
            std::cout << "AppKit layout passed: wide/narrow panels, wrapping, bounds, non-overlap, scrolling, resize, backend updates, hidden controls\n";
            return 0;
        } catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
    }
}
