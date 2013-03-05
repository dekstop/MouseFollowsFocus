//
//  AppDelegate.m
//  MouseFollowsFocus
//
//  Caveats:
//  - We won't be able to get an NSWindow for the key (active) window since it's not in our address space.
//    Instead there's a lot of manual checking and guesswork to determine the key window once we have the
//    "running" (frontmost) app.
//  - It appears there's no means of tracking window focus changes within an application from the outside.
//
//  TODO:
//  - lots of refactoring.
//  - option: "center on active window" vs "remember last position"
//
//  BUGS:
//  - FIXME: launching an application on a separate display doesn't appear to trigger a focus change
//    - to reproduce: focus on display 2, start an app that opens on display 1
//    - cause: both "launch" and "active" notifications get triggered before the app window is created
//  - FIXME: similar problem when closing an application.
//    - this may result in the mouse cursor moving to a different display, depending on the previously focused app.
//    - not sure how to remedy this. Mouse movement is unexpected; but it does reflect actual input focus change.
//  - FIXME: clicking on desktop on non-primary display switches focus to primary display
//
//  Created by mongo on 18/02/2013.
//  Copyright (c) 2013 martind. All rights reserved.
//

#import "AppDelegate.h"
#import "MouseIndicatorWindow.h"
#import <Carbon/Carbon.h>

@implementation AppDelegate

@synthesize isActive;
NSAttributedString *menuTitleActive = nil;
NSAttributedString *menuTitleInactive = nil;
@synthesize isRecording;

NSScreen *curScreen = nil;
NSMutableDictionary *mousePosForScreen;

MouseIndicatorWindow *mouseIndicator;

NSString *logFilePath;
NSDateFormatter *dateFormatter;
NSFileHandle *logFile;

- (id)init {
    if (self = [super init]) {
        mousePosForScreen = [[NSMutableDictionary alloc] init];
        curScreen = [NSScreen mainScreen];

        dateFormatter = [[NSDateFormatter alloc] init];
        [dateFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss"];
        logFilePath = [NSString stringWithFormat:@"%@/Library/Logs/MouseFollowsFocus.log", NSHomeDirectory()];
        logFile = OpenUserLog(logFilePath);

        menuTitleActive = [[NSMutableAttributedString alloc] initWithString:@"M" attributes:@{NSForegroundColorAttributeName:[NSColor blackColor], NSFontAttributeName:[NSFont systemFontOfSize:14.0]}];
        menuTitleInactive = [[NSMutableAttributedString alloc] initWithString:@"M" attributes:@{NSForegroundColorAttributeName:[NSColor grayColor], NSFontAttributeName:[NSFont systemFontOfSize:14.0]}];
    }
    return self;
}

- (IBAction)toggleIsActive:(id)pId
{
    isActive = !isActive;
    [[NSUserDefaults standardUserDefaults] setBool:isActive forKey:@"isActive"];
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

- (IBAction)toggleIsRecording:(id)pId
{
    isRecording = !isRecording;
    [[NSUserDefaults standardUserDefaults] setBool:isRecording forKey:@"isRecording"];
    [self updateIsRecordingDisplay];
}

- (void)updateIsRecordingDisplay
{
    [isRecordingMenuItem setState:(isRecording ? NSOnState : NSOffState)];
}

- (IBAction)openLog:(id)pId
{
    [[NSWorkspace sharedWorkspace] openFile:logFilePath];
}

- (IBAction)toggleLaunchOnStartup:(id)pId
{
    if ([self isLoginItem]) {
        [self removeAsLoginItem];
        [launchOnStartupMenuItem setState:NSOffState];
    } else {
        [self addAsLoginItem];
        [launchOnStartupMenuItem setState:NSOnState];
    }
}

- (IBAction)about:(id)pId
{
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/dekstop/MouseFollowsFocus"]];
}

- (IBAction)quit:(id)pId
{
    [NSApp performSelector:@selector(terminate:) withObject:nil afterDelay:0.0];
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
    SEL action = [menuItem action];
    
    if (action == @selector(toggleIsRecording:)) {
        return (isActive ? YES : NO);
    }
    return YES;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // Lose focus
//    [[NSApplication sharedApplication] hide:nil];
    
    // App preferences
    NSDictionary *appDefaults = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:@"isActive"];
    [[NSUserDefaults standardUserDefaults] registerDefaults:appDefaults];

    isActive = [[NSUserDefaults standardUserDefaults] boolForKey:@"isActive"];
    isRecording = [[NSUserDefaults standardUserDefaults] boolForKey:@"isRecording"];
    [launchOnStartupMenuItem setState:([self isLoginItem] ? NSOnState : NSOffState)];

    mouseIndicator = [[MouseIndicatorWindow alloc] initWithSize:400 color:[NSColor redColor]];

    // Status bar / tray icon
    statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    [statusItem setMenu:statusMenu];
    [statusItem setHighlightMode:YES];
    [self updateIsActiveDisplay];
    [self updateIsRecordingDisplay];
    
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
    
    // Register global event monitors -- may require assistive device access.
    // Note: we monitor key/mouse "up" (clicked) events instead of "down" (pressed) in an attempt to
    // let window focus changes happen _before_ we try to detect them. Depending on the nature of the
    // transition this may still not be sufficient. (E.g. minimising a window takes a fairly long time.)
    [NSEvent addGlobalMonitorForEventsMatchingMask:(NSKeyUpMask | NSLeftMouseUpMask) handler:^(NSEvent *event){
        BOOL doTrigger = FALSE;
        // Check for mouse clicks that may trigger a focus change.
        if ([event type] == NSLeftMouseUp) {
            doTrigger = TRUE;
        }
        // Check for key combinations that may trigger a focus change.
        // Full list: http://support.apple.com/kb/ht1343
        else if ([event type] == NSKeyUp) {
//            NSLog(@"%d %@§§ %@", [event keyCode], [event characters], [event charactersIgnoringModifiers]);
            NSUInteger modifierKeyMask = NSCommandKeyMask | NSShiftKeyMask | NSAlternateKeyMask | NSControlKeyMask | NSFunctionKeyMask;
            NSUInteger modifierFlags = [event modifierFlags] & modifierKeyMask;
            unsigned short keyCode = [event keyCode];
            // Cmd
            if (modifierFlags == NSCommandKeyMask) {
                switch (keyCode) {
                    case kVK_ISO_Section: // '§'
                        // Show mouse indicator (to debug)
                        [mouseIndicator showAt:[self getMousePos] onScreen:curScreen];
                        break;
                    case kVK_LeftArrow:
                    case kVK_RightArrow:
                    case kVK_ANSI_Grave: // '~'
                    case kVK_ANSI_M:
                    case kVK_ANSI_H:
                    case kVK_ANSI_W:
                        doTrigger = TRUE;
                }
            }
            // Cmd+Shift
            else if (modifierFlags == (NSCommandKeyMask | NSShiftKeyMask)) {
                switch (keyCode) {
                    case kVK_ANSI_Grave: // '~'
                        doTrigger = TRUE;
                }
            }
            // Cmd+Opt
            else if (modifierFlags == (NSCommandKeyMask | NSAlternateKeyMask)) {
                switch (keyCode) {
                    case kVK_ANSI_M:
                    case kVK_ANSI_H:
                        doTrigger = TRUE;
                }
            }
            // Ctrl
            else if (modifierFlags == NSControlKeyMask) {
                switch (keyCode) {
                    case kVK_F4:
                        doTrigger = TRUE;
                }
            }
            // Ctrl+Shift
            else if (modifierFlags == (NSControlKeyMask | NSShiftKeyMask)) {
                switch (keyCode) {
                    case kVK_F4:
                        doTrigger = TRUE;
                }
            }
        }
        if (doTrigger) {
            NSDictionary *activeApp = [[NSWorkspace sharedWorkspace] activeApplication];
            [self updateActiveScreenForRunningApp:[activeApp objectForKey:@"NSWorkspaceApplicationKey"]];
        }
    }];
}

- (void)notificationHandler:(NSNotification *)notification
{
//    NSLog(@"*** Notification: %@ ***", [notification name]);
    NSRunningApplication *app = [[notification userInfo] objectForKey:@"NSWorkspaceApplicationKey"];

    // Ignore our own app notifications during launch -- we don't have an app window.
//    if ([[app bundleIdentifier] isEqualTo:[[NSBundle mainBundle] bundleIdentifier]]) {
//        return;
//    }

    [self updateActiveScreenForRunningApp:app];
}

- (void)updateActiveScreenForRunningApp:(NSRunningApplication*)app
{
    if (!isActive) {
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
    [self moveMouseToWindow:window onScreen:newScreen];
    [self recordActiveWindow:window forApplication:app onScreen:newScreen];
}

- (NSDictionary*)getFrontWindowForApp:(NSRunningApplication *)app
{
    // http://stackoverflow.com/questions/13426488/notification-of-active-document-change-on-os-x
    CFArrayRef windowList = CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements, kCGNullWindowID);
    NSMutableArray *data = [(__bridge NSArray *) windowList mutableCopy];
    CFRelease(windowList);
    
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

- (NSScreen*)getScreenForWindow:(NSDictionary *)window
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

- (void)moveMouseToWindow:(NSDictionary *)window onScreen:(NSScreen*)newScreen
{
    // Has active display changed?
    if ([newScreen isEqualTo:curScreen]) {
//        NSLog(@"Same screen, aborting");
        return;
    }

    // Determine new mouse position
    NSPoint nextMousePos;
    if ([self hasPreviousMousePosForScreen:newScreen]) {
        // Retrieve previous mouse pos on that display
//        NSLog(@"Restoring previous mouse pos");
        nextMousePos = [self getPreviousMousePosForScreen:newScreen];
    } else {
        // None stored: determine center of new window
        NSLog(@"Calculating new mouse pos from window bounds");
        nextMousePos = [self getCenterPointForWindow:window onScreen:newScreen];
    }

    // Remember current position -- but only if mouse hasn't moved off-screen already.
    NSPoint curMousePos = [self getMousePos];

    if (NSPointInRect(curMousePos, [curScreen frame])) {
//        NSLog(@"Remembering mouse pos on previous screen %@", [self getIdForScreen:curScreen]);
        [self setPreviousMousePos:curMousePos forScreen:curScreen];
    } else {
        // Mouse was manually moved across displays: don't remember position
//        NSLog(@"Discard mouse pos which has moved outside screen %@", [self getIdForScreen:curScreen]);
        [self clearPreviousMousePosForScreen:curScreen];
    }
    
    // Move to new screen -- but only if we're not already on it.
    if (!NSPointInRect(curMousePos, [newScreen frame])) {
        [self setMousePos:nextMousePos];
        [mouseIndicator showAt:nextMousePos onScreen:newScreen];
    }
    curScreen = newScreen;
}

- (NSPoint)getMousePos
{
//    CGEventRef event = CGEventCreate(NULL);
//    NSPoint curMousePos = CGEventGetLocation(event);
//    CFRelease(event);
//    return curMousePos;
    return [NSEvent mouseLocation];
}

- (void)setMousePos:(NSPoint)pos
{
    // Need to convert from AppKit screen coordinates to Quartz mouse coordinates:
    CGError error = CGWarpMouseCursorPosition([self appkitToQuartz:pos]);
    if (error != kCGErrorSuccess) {
        NSLog(@"Error setting mouse position: %d", error);
    }
}

- (Boolean)screenBoundsOf:(NSScreen*)screen containWindow:(NSDictionary*)window
{
    CGRect bounds;
    CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)[window objectForKey:@"kCGWindowBounds"], &bounds);
    // Comparing Quartz window bounds with AppKit screen dimensions: need to convert them first.
    CGRect intersection = CGRectIntersection([screen frame], [self quartzToAppkit:bounds]);
    return intersection.size.height > 0 && intersection.size.width > 0;
}

- (NSPoint)getCenterPointForWindow:(NSDictionary*)window onScreen:(NSScreen*)screen
{
    CGRect bounds;
    CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)[window objectForKey:@"kCGWindowBounds"], &bounds);
    // Constructing AppKit point from Quartz coordinates: need to convert first.
    bounds = [self quartzToAppkit:bounds];
    return NSMakePoint(
                       bounds.origin.x + (bounds.size.width / 2),
                       bounds.origin.y + (bounds.size.height / 2));
}

// Convert vertical coordinates relative to main screen:
// - AppKit coords are with origin bottom-left
// - Quartz coords are with origin top-left
- (CGPoint)appkitToQuartz:(NSPoint)point
{
    return CGPointMake(
        point.x,
        [NSScreen mainScreen].frame.size.height - point.y);
}

// Convert vertical coordinates relative to main screen:
// - AppKit coords are with origin bottom-left
// - Quartz coords are with origin top-left
- (NSRect)quartzToAppkit:(CGRect)rect
{
    return NSMakeRect(
        rect.origin.x,
        [NSScreen mainScreen].frame.size.height - rect.origin.y - rect.size.height,
        rect.size.width,
        rect.size.height);
}

- (id)getIdForScreen:(NSScreen*)screen
{
    return [[screen deviceDescription] objectForKey:@"NSScreenNumber"];
}

- (Boolean)hasPreviousMousePosForScreen:(NSScreen*)screen
{
    return [mousePosForScreen objectForKey:[self getIdForScreen:screen]] != nil;
}

- (NSPoint)getPreviousMousePosForScreen:(NSScreen*)screen
{
    return [[mousePosForScreen objectForKey:[self getIdForScreen:screen]] pointValue];
}

- (void)setPreviousMousePos:(NSPoint)mousePos forScreen:(NSScreen*)screen
{
    [mousePosForScreen setObject:[NSValue valueWithPoint:mousePos] forKey:[self getIdForScreen:screen]];
}

- (void)clearPreviousMousePosForScreen:(NSScreen*)screen
{
    [mousePosForScreen removeObjectForKey:[self getIdForScreen:screen]];
}

void DisplayReconfigurationCallBack(CGDirectDisplayID display, CGDisplayChangeSummaryFlags flags, void *userInfo)
{
    u_int32_t mutatorFlags = // Changes to the shape or position, or disabling of the display.
        kCGDisplayMovedFlag |
        kCGDisplayRemoveFlag |
        kCGDisplayDisabledFlag |
        kCGDisplayMirrorFlag |
        kCGDisplayDesktopShapeChangedFlag;
    if (flags & mutatorFlags) {
        NSLog(@"Removing display %d", display);
        [mousePosForScreen removeObjectForKey:[NSNumber numberWithInteger:display]];
    }
}

- (NSString*)getApplicationName:(NSRunningApplication*)app
{
    NSString * path = [[NSWorkspace sharedWorkspace]absolutePathForAppBundleWithIdentifier:[app bundleIdentifier]];
    return [[NSFileManager defaultManager] displayNameAtPath:path];
}

/**
 *
 * Tools: logging.
 *
 **/

- (void)recordActiveWindow:(NSDictionary*)window forApplication:(NSRunningApplication*)app onScreen:(NSScreen*)screen
{
    if (isRecording) {
        Log(@"Window \"%@\" of application \"%@\" on display %@",
            [window objectForKey:@"kCGWindowName"],
            [self getApplicationName:app],
            [self getIdForScreen:screen]);
    }
}

NSFileHandle *OpenUserLog(NSString *logFilePath)
{
    NSFileHandle *logFile;
    NSFileManager * mFileManager = [NSFileManager defaultManager];
    if([mFileManager fileExistsAtPath:logFilePath] == NO) {
        [mFileManager createFileAtPath:logFilePath contents:nil attributes:nil];
    }
    logFile = [NSFileHandle fileHandleForWritingAtPath:logFilePath];
    [logFile seekToEndOfFile];
    return logFile;
}

void Log(NSString* format, ...)
{
    // Build string
    va_list argList;
    va_start(argList, format);
    NSString* formattedMessage = [[NSString alloc] initWithFormat:format arguments:argList];
    va_end(argList);
    
    // Console
    //    NSLog(@"%@", formattedMessage);
    
    // File logging
    NSString *logMessage = [NSString stringWithFormat:@"%@ %@\n",
                            [dateFormatter stringFromDate:[NSDate date]],
                            formattedMessage];
    [logFile writeData:[logMessage dataUsingEncoding:NSUTF8StringEncoding]];
    [logFile synchronizeFile];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
    [logFile closeFile];
}

/**
 *
 * Tools: add/remove login item.
 * Based on https://gist.github.com/boyvanamstel/1409312 (MIT license)
 *
 **/

- (BOOL)isLoginItem {
    // See if the app is currently in LoginItems.
    LSSharedFileListItemRef itemRef = [self itemRefInLoginItems];
    // Store away that boolean.
    BOOL isInList = itemRef != nil;
    // Release the reference if it exists.
    if (itemRef != nil) CFRelease(itemRef);
    
    return isInList;
}

- (void)addAsLoginItem {
    // Get the LoginItems list.
    LSSharedFileListRef loginItemsRef = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
    if (loginItemsRef == nil) return;
    
    // Add the app to the LoginItems list.
    CFURLRef appUrl = (__bridge CFURLRef)[NSURL fileURLWithPath:[[NSBundle mainBundle] bundlePath]];
    LSSharedFileListItemRef itemRef = LSSharedFileListInsertItemURL(loginItemsRef, kLSSharedFileListItemLast, NULL, NULL, appUrl, NULL, NULL);
    if (itemRef) CFRelease(itemRef);
}

- (void)removeAsLoginItem {
    // Get the LoginItems list.
    LSSharedFileListRef loginItemsRef = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
    if (loginItemsRef == nil) return;

    // Remove the app from the LoginItems list.
    LSSharedFileListItemRef itemRef = [self itemRefInLoginItems];
    LSSharedFileListItemRemove(loginItemsRef,itemRef);
//    if (itemRef != nil) CFRelease(itemRef);
}

- (LSSharedFileListItemRef)itemRefInLoginItems {
    LSSharedFileListItemRef itemRef = nil;
    
	NSString * appPath = [[NSBundle mainBundle] bundlePath];
    
	// This will retrieve the path for the application
	// For example, /Applications/test.app
	CFURLRef url = (__bridge CFURLRef)[NSURL fileURLWithPath:appPath];
    
	// Create a reference to the shared file list.
	LSSharedFileListRef loginItems = LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL);
    
	if (loginItems) {
		UInt32 seedValue;
		//Retrieve the list of Login Items and cast them to
		// a NSArray so that it will be easier to iterate.
		NSArray  *loginItemsArray = (__bridge NSArray *)LSSharedFileListCopySnapshot(loginItems, &seedValue);
		for(int i = 0; i< [loginItemsArray count]; i++){
			LSSharedFileListItemRef currentItemRef = (__bridge LSSharedFileListItemRef)[loginItemsArray
                                                                                        objectAtIndex:i];
			//Resolve the item with URL
			if (LSSharedFileListItemResolve(currentItemRef, 0, (CFURLRef*) &url, NULL) == noErr) {
				NSString * urlPath = [(__bridge NSURL*)url path];
				if ([urlPath compare:appPath] == NSOrderedSame){
                    itemRef = currentItemRef;
				}
			}
		}
        CFRelease(loginItems);
	}
    return itemRef;
}

@end
