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
//  - monitor display changes: CGDisplayRegisterReconfigurationCallback, CGDisplayRemoveReconfigurationCallback
//
//  Created by mongo on 18/02/2013.
//  Copyright (c) 2013 martind. All rights reserved.
//

#import "AppDelegate.h"

@implementation AppDelegate

id curScreenId = NULL;
NSMutableDictionary *mousePosForScreen;

__attribute__((constructor))
static void initialize_mousePosDict() {
    mousePosForScreen = [[NSMutableDictionary alloc] init];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
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
    [center addObserver:self selector:@selector(notificationHandler:) name:NSWorkspaceDidActivateApplicationNotification object:nil ];
    
    // [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)notificationHandler:(NSNotification *)notification
{
    NSRunningApplication *app = [[notification userInfo] objectForKey:@"NSWorkspaceApplicationKey"];
    
    NSDictionary *window = [self getFrontWindowForApp: app];
    if (window==NULL) {
        NSLog(@"Could not determine which window has focus.");
        return;
    }

    // Determine active display.
    
    // This does not work reliably:
    // NSScreen *screen = [NSScreen mainScreen];

    // So instead we'll identify the first screen that contains the frontmost window.
    NSEnumerator *screenEnum = [[NSScreen screens] objectEnumerator];
    NSScreen *screen;
    while ((screen = [screenEnum nextObject]) && ![self screenBoundsOf:screen containWindow:window]);
    if (screen==NULL) {
        NSLog(@"Could not determine current display.");
        return;
    }
    id newScreenId = [[screen deviceDescription] objectForKey:@"NSScreenNumber"];

    // Has active display changed?
    if (curScreenId==NULL) {
        // First call: pass
    } else if (screen!=NULL && newScreenId!=curScreenId) {

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
