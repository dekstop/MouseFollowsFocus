//
//  AppDelegate
//  MouseFollowsFocus
//
//  Created by mongo on 18/02/2013.
//  Copyright (c) 2013 martind. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface AppDelegate : NSObject <NSApplicationDelegate> {
    IBOutlet NSMenu *statusMenu;
    NSStatusItem *statusItem;

    BOOL isActive;
    BOOL isRecording;
    IBOutlet NSMenuItem *isActiveMenuItem;
    IBOutlet NSMenuItem *isRecordingMenuItem;
    IBOutlet NSMenuItem *launchOnStartupMenuItem;
}
@property BOOL isActive;
@property BOOL isRecording;
- (IBAction)toggleIsActive:(id)pId;
- (IBAction)toggleIsRecording:(id)pId;
- (IBAction)openLog:(id)pId;
- (IBAction)toggleLaunchOnStartup:(id)pId;
- (IBAction)about:(id)pId;
- (IBAction)quit:(id)pId;
@end
