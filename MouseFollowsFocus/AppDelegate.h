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
    IBOutlet NSMenuItem *isActiveMenuItem;
//    IBOutlet NSMenuItem *startOnStartupMenuItem;
}
@property BOOL isActive;
- (IBAction)toggleIsActive:(id)pId;
//- (IBAction)toggleStartOnStartup:(id)pId;
- (IBAction)about:(id)pId;
- (IBAction)quit:(id)pId;
@end
