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
//  - implement menu toggles (check marks)
//  - launch at system startup http://cocoatutorial.grapewave.com/tag/lssharedfilelist-h/
//  - FIXME: dragging a window from display 1 to display 2: moves mouse pos. for display 1 off-screen (onto display 2)
//    - when storing: only store updated position if it's within display bounds?
//    - when restoring: if mouse pos outside display bounds: revert to default (centre of window)
//  - FIXME: launching an application on a separate display doesn't appear to trigger a focus change
//    - to reproduce: focus on display 2, start an app that opens on display 1
//    - cause: both "launch" and "active" notifications get triggered before the app window is created
//  - FIXME: similar problem when closing an application.
//    - this may result in the mouse cursor moving to a different display, depending on the previously focused app.
//    - not sure how to remedy this. Mouse movement is unexpected; but it does reflect actual input focus change.
//  - monitor display changes: CGDisplayRegisterReconfigurationCallback, CGDisplayRemoveReconfigurationCallback
//
//  Created by mongo on 18/02/2013.
//  Copyright (c) 2013 martind. All rights reserved.
//

#import "AppDelegate.h"

@implementation AppDelegate

id curScreenId = NULL;
NSMutableDictionary *mousePosForScreen;

- (id)init {
    if (self = [super init]) {
        mousePosForScreen = [[NSMutableDictionary alloc] init];
        curScreenId = [[[NSScreen mainScreen] deviceDescription] objectForKey:@"NSScreenNumber"];
    }
    return self;
}

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
    [statusItem setTitle:@"M"];
//    - (void)setImage:(NSImage *)image
//    -(void)setAlternateImage:(NSImage *)image
    [statusItem setHighlightMode:YES];
    
    // Get display setup
    uint32_t numDisplays = 4;
    CGDirectDisplayID displays[numDisplays];
    CGError error = CGGetOnlineDisplayList(4, displays, &numDisplays);
    if (error != kCGErrorSuccess) {
        NSLog(@"Error retrieving display list: %d", error);
        return;
    }
    
    NSLog(@"Found %d displays", numDisplays);
    
    // Register app activation notification observer
    NSNotificationCenter * center = [[NSWorkspace sharedWorkspace]notificationCenter];

    [center addObserver:self selector:@selector(notificationHandler:) name:NSWorkspaceDidLaunchApplicationNotification object:nil ];
    [center addObserver:self selector:@selector(notificationHandler:) name:NSWorkspaceDidActivateApplicationNotification object:nil ];
    [center addObserver:self selector:@selector(notificationHandler:) name:NSWorkspaceDidUnhideApplicationNotification object:nil ];

    // [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)notificationHandler:(NSNotification *)notification
{
    NSLog(@"Notification: %@", [notification name]);

    NSRunningApplication *app = [[notification userInfo] objectForKey:@"NSWorkspaceApplicationKey"];
//    NSLog(@"App: %@", app);

    // Ignore our own app notifications during launch -- we don't have an app window.
    if ([[app bundleIdentifier] isEqualTo:[[NSBundle mainBundle] bundleIdentifier]]) {
        return;
    }
    
    NSDictionary *window = [self getFrontWindowForApp: app];
//    NSLog(@"Window: %@", window);
    if (window==NULL) {
        // Was this a notification for a window-less app?
        NSLog(@"Could not determine which window has focus.");
        return;
    }

    // Determine active display.
    
    // This does not work reliably:
    // NSScreen *screen = [NSScreen mainScreen];

    // So instead we'll identify the first screen that contains the frontmost window.
    NSEnumerator *screenEnum = [[NSScreen screens] objectEnumerator];
    NSScreen *newScreen;
    while ((newScreen = [screenEnum nextObject]) && ![self screenBoundsOf:newScreen containWindow:window]);
    if (newScreen==NULL) {
        NSLog(@"Could not determine current display.");
        return;
    }
    id newScreenId = [[newScreen deviceDescription] objectForKey:@"NSScreenNumber"];

    // Has active display changed?
    if (newScreenId!=NULL && newScreenId!=curScreenId) {

        NSString *name = [window objectForKey:@"kCGWindowName" ];
        NSLog(@"Switched to window %@ on display %@", name, newScreenId);
    
        // Determine new mouse position
        NSPoint nextMousePos;
        if ([mousePosForScreen objectForKey:newScreenId]) {
            // Retrieve previous mouse pos on that display
            nextMousePos = [[mousePosForScreen objectForKey:newScreenId] pointValue];
        } else {
            // None stored: determine center of new window
            nextMousePos = [self getCenterPointForWindow:window];
        }
//        NSLog(@"Screen bounds: %@", [NSValue valueWithRect:[newScreen frame]]);
//        NSLog(@"New mouse pos: %@", [NSValue valueWithPoint:nextMousePos]);
        
        // Remember current position
        CGPoint curMousePos = CGEventGetLocation(CGEventCreate(NULL));
        [mousePosForScreen setObject:[NSValue valueWithPoint:curMousePos] forKey:curScreenId];

        // Move to new position
        CGError error = CGWarpMouseCursorPosition(nextMousePos);
        if (error != kCGErrorSuccess) {
            NSLog(@"Error setting mouse position: %d", error);
        }
    }
    curScreenId = newScreenId;
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
    return NULL;
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

@end
