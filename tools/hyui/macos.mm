#include <QQuickWindow>
#import <AppKit/AppKit.h>

// Resolve the macOS 26 class at runtime so older macOS SDKs/hosts retain
// NSVisualEffectView vibrancy. Only public AppKit properties are used.
void hyuiApplyMacMaterial(QWindow* window, bool glass) {
    if (!glass || NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceTransparency) { return; }
    NSView* content = reinterpret_cast<NSView*>(window->winId());
    NSWindow* native = content.window;
    if (!native) { return; }
    NSView* effect = nil;
    Class glassClass = NSClassFromString(@"NSGlassEffectView");
    if (glassClass) {
        effect = [[glassClass alloc] initWithFrame:content.bounds];
        [effect setValue:@14.0 forKey:@"cornerRadius"];
    } else {
        NSVisualEffectView* vibrancy = [[NSVisualEffectView alloc] initWithFrame:content.bounds];
        vibrancy.material = NSVisualEffectMaterialUnderWindowBackground;
        vibrancy.blendingMode = NSVisualEffectBlendingModeBehindWindow;
        vibrancy.state = NSVisualEffectStateFollowsWindowActiveState;
        effect = vibrancy;
    }
    effect.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [content addSubview:effect positioned:NSWindowBelow relativeTo:nil];
    [effect release];
    native.opaque = NO;
    native.backgroundColor = NSColor.clearColor;
    if (auto* quick = qobject_cast<QQuickWindow*>(window)) { quick->setColor(Qt::transparent); }
}
