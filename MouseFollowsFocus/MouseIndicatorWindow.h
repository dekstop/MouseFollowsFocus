//
//  MouseIndicator.h
//  MouseFollowsFocus
//
//  Created by mongo on 26/02/2013.
//  Copyright (c) 2013 martind. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface MouseIndicatorWindow : NSWindow {
    float size;
    float timerInterval;
    float duration;
}

- (id)initWithSize:(int)size color:(NSColor*)color;
- (void) showAt:(NSPoint)mousePos onScreen:(NSScreen*)screen;

@end
