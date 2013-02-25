//
//  AppDelegate.m
//  MouseFollowsFocus
//
//  Caveats:
//  - We won't be able to get an NSWindow for the key (active) window since it's not in our address space.
//    Instead there's a lot of manual checking and guesswork to determine the key window once we have the
//    "running" (frontmost) app.
//  - It appears there's no means of tracking window focus changes within an application from the outside.
//  - screen numbers may change -- need to "register a callback (CGDisplayRegisterReconfigurationCallback) and examine the changes that occur (kCGDisplayAddFlag, kCGDisplayRemoveFlag, etc)"
//
//  TODO:
//  - lots of refactoring.
//  - implement menu toggles (check marks)
//  - launch at system startup http://cocoatutorial.grapewave.com/tag/lssharedfilelist-h/
//  - FIXME: launching an application on a separate display doesn't appear to trigger a focus change
//    - to reproduce: focus on display 2, start an app that opens on display 1
//    - cause: both "launch" and "active" notifications get triggered before the app window is created
//  - FIXME: similar problem when closing an application.
//    - this may result in the mouse cursor moving to a different display, depending on the previously focused app.
//    - not sure how to remedy this. Mouse movement is unexpected; but it does reflect actual input focus change.
//
//  Created by mongo on 18/02/2013.
//  Copyright (c) 2013 martind. All rights reserved.
//

#import "AppDelegate.h"

@implementation AppDelegate

@synthesize isActive;
NSAttributedString *menuTitleActive = nil;
NSAttributedString *menuTitleInactive = nil;

NSScreen *curScreen = nil;
NSMutableDictionary *mousePosForScreen;


- (id)init {
    if (self = [super init]) {
        mousePosForScreen = [[NSMutableDictionary alloc] init];
        curScreen = [NSScreen mainScreen];
        isActive = TRUE;
        menuTitleActive = [[NSMutableAttributedString alloc] initWithString:@"M" attributes:@{NSForegroundColorAttributeName:[NSColor blackColor], NSFontAttributeName:[NSFont systemFontOfSize:14.0]}];
        menuTitleInactive = [[NSMutableAttributedString alloc] initWithString:@"M" attributes:@{NSForegroundColorAttributeName:[NSColor grayColor], NSFontAttributeName:[NSFont systemFontOfSize:14.0]}];
    }
    return self;
}

- (IBAction)toggleIsActive:(id)pId
{
    isActive = !isActive;
    [self updateIsActiveDisplay];
}

- (void)updateIsActiveDisplay
{
    [isActiveMenuItem setState:(isActive ? NSOnState : NSOffState)];
    [statusItem setAttributedTitle:(isActive ? menuTitleActive : menuTitleInactive)];
    //    [statusItem setTitle:@"M"];
    //    - (void)setImage:(NSImage *)image
    //    -(void)setAlternateImage:(NSImage *)image
}

//- (IBAction)toggleStartOnStartup:(id)pId
//{
//    
//}

- (IBAction)about:(id)pId
{
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/dekstop/MouseFollowsFocus"]];
}

- (IBAction)quit:(id)pId
{
    [NSApp performSelector:@selector(terminate:) withObject:nil afterDelay:0.0];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Status bar / tray icon
    statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    [statusItem setMenu:statusMenu];
    [statusItem setHighlightMode:YES];
    [self updateIsActiveDisplay];
    
    // Get display setup
    uint32_t numDisplays = 4;
    CGDirectDisplayID displays[numDisplays];
    CGError error = CGGetOnlineDisplayList(4, displays, &numDisplays);
    if (error != kCGErrorSuccess) {
        NSLog(@"Error retrieving display list: %d", error);
        return;
    }
    
    NSLog(@"Found %d displays", numDisplays);
    
    // Register display change notifications
    CGDisplayRegisterReconfigurationCallback(DisplayReconfigurationCallBack, nil);
    // CGDisplayRemoveReconfigurationCallback
    
    // Register app activation notification observer
    NSNotificationCenter * center = [[NSWorkspace sharedWorkspace]notificationCenter];

    [center addObserver:self selector:@selector(notificationHandler:) name:NSWorkspaceDidLaunchApplicationNotification object:nil ];
    [center addObserver:self selector:@selector(notificationHandler:) name:NSWorkspaceDidActivateApplicationNotification object:nil ];
    [center addObserver:self selector:@selector(notificationHandler:) name:NSWorkspaceDidUnhideApplicationNotification object:nil ];
    // [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)notificationHandler:(NSNotification *)notification
{
    if (!isActive) {
        return;
    }
    NSLog(@"*** Notification: %@ ***", [notification name]);

    NSRunningApplication *app = [[notification userInfo] objectForKey:@"NSWorkspaceApplicationKey"];
//    NSLog(@"App: %@", app);

    // Ignore our own app notifications during launch -- we don't have an app window.
    if ([[app bundleIdentifier] isEqualTo:[[NSBundle mainBundle] bundleIdentifier]]) {
        return;
    }
    
    NSDictionary *window = [self getFrontWindowForApp: app];
//    NSLog(@"Window: %@", window);
    if (window==nil) {
        // Was this a notification for a window-less app?
        NSLog(@"Could not determine which window has focus.");
        return;
    }

    // Determine active display.
    NSScreen *newScreen = [self getScreenForWindow:window];
    if (newScreen==nil) {
        NSLog(@"Could not determine current display.");
        return;
    }

    // Move mouse
    NSLog(@"Switched to window %@ on display %@",
          [window objectForKey:@"kCGWindowName"],
          [self getIdForScreen:newScreen]);

    [self moveMouseToWindow:window onScreen:newScreen];
}

- (NSDictionary*)getFrontWindowForApp:(NSRunningApplication *)app
{
    // http://stackoverflow.com/questions/13426488/notification-of-active-document-change-on-os-x
    CFArrayRef windowList = CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements, kCGNullWindowID);
    NSMutableArray *data = [(__bridge NSArray *) windowList mutableCopy];
    
    for (NSMutableDictionary *theDict in data) {
        id pid = [theDict objectForKey:(id)kCGWindowOwnerPID];
        if ([pid intValue] == [app processIdentifier]) {
//            NSLog(@"%@", theDict);
            id layer = [theDict objectForKey:(id)kCGWindowLayer];
            if ([layer intValue] == 0) {
                // The first entry is the front-facing one
                return theDict;
            }
        }
    }
    return nil;
}

- (NSScreen*) getScreenForWindow:(NSDictionary *)window
{
    // This does not work reliably:
    // NSScreen *screen = [NSScreen mainScreen];
    
    // So instead we'll identify the first screen that contains the frontmost window.
    NSEnumerator *screenEnum = [[NSScreen screens] objectEnumerator];
    NSScreen *newScreen = nil;
    while ((newScreen = [screenEnum nextObject]) && ![self screenBoundsOf:newScreen containWindow:window]);
    // May return nil
    return newScreen;
}

- (void)moveMouseToWindow:(NSDictionary *)window onScreen:(id)newScreen
{
    // Has active display changed?
    if ([newScreen isEqualTo:curScreen]) {
        NSLog(@"Same screen, aborting");
        return;
    }

    // Determine new mouse position
    NSPoint nextMousePos;
    if ([self hasMousePosForScreen:newScreen]) {
        // Retrieve previous mouse pos on that display
        NSLog(@"Restoring previous mouse pos");
        nextMousePos = [self getMousePosForScreen:newScreen];
    } else {
        // None stored: determine center of new window
        NSLog(@"Calculating new mouse pos from window bounds");
        nextMousePos = [self getCenterPointForWindow:window];
    }
    
    // Remember current position -- but only if mouse hasn't moved off-screen already.
    NSPoint curMousePos = CGEventGetLocation(CGEventCreate(NULL));
    if (NSPointInRect(curMousePos, [curScreen frame])) {
//        NSLog(@"Remembering mouse pos on previous screen %@", [self getIdForScreen:curScreen]);
        [self setMousePos:curMousePos forScreen:curScreen];
    } else {
        // Mouse was manually moved across displays: don't remember position
//        NSLog(@"Discard mouse pos which has moved outside screen %@", [self getIdForScreen:curScreen]);
        [self clearMousePosForScreen:curScreen];
    }
    
    // Move to new screen -- but only if we're not already on it.
    if (!NSPointInRect(curMousePos, [newScreen frame])) {
        CGError error = CGWarpMouseCursorPosition(nextMousePos);
        if (error != kCGErrorSuccess) {
            NSLog(@"Error setting mouse position: %d", error);
        }
    }
    curScreen = newScreen;
}

- (Boolean) screenBoundsOf:(NSScreen*)screen containWindow:(NSDictionary*)window
{
    CGRect bounds;
    CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)[window objectForKey:@"kCGWindowBounds"], &bounds);
    CGRect intersection = CGRectIntersection([screen frame], bounds);
    return intersection.size.height > 0 && intersection.size.width > 0;
}

- (NSPoint) getCenterPointForWindow:(NSDictionary*)window
{
    CGRect bounds;
    CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)[window objectForKey:@"kCGWindowBounds"], &bounds);
    return CGPointMake(bounds.origin.x + (bounds.size.width / 2), bounds.origin.y + (bounds.size.height / 2));
}

- (id) getIdForScreen:(NSScreen*)screen
{
    return [[screen deviceDescription] objectForKey:@"NSScreenNumber"];
}

- (Boolean) hasMousePosForScreen:(NSScreen*)screen
{
    return [mousePosForScreen objectForKey:[self getIdForScreen:screen]] != nil;
}

- (NSPoint) getMousePosForScreen:(NSScreen*)screen
{
    return [[mousePosForScreen objectForKey:[self getIdForScreen:screen]] pointValue];
}

- (void) setMousePos:(NSPoint)mousePos forScreen:(NSScreen*)screen
{
    [mousePosForScreen setObject:[NSValue valueWithPoint:mousePos] forKey:[self getIdForScreen:screen]];
}

- (void) clearMousePosForScreen:(NSScreen*)screen
{
    [mousePosForScreen removeObjectForKey:[self getIdForScreen:screen]];
}

void DisplayReconfigurationCallBack(CGDirectDisplayID display, CGDisplayChangeSummaryFlags flags, void *userInfo)
{
    if (flags & kCGDisplayRemoveFlag) {
        NSLog(@"Removing display %d", display);
//        [self clearMousePosForScreen:display];
        [mousePosForScreen removeObjectForKey:[NSNumber numberWithInteger:display]];
    }
}


@end
