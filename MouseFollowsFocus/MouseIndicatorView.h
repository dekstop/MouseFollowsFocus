//
//  MouseIndicatorView.h
//  MouseFollowsFocus
//
//  Created by mongo on 26/02/2013.
//  Copyright (c) 2013 martind. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface MouseIndicatorView : NSView {
    NSColor *color;
}

- (id)initWithFrame:(NSRect)frame color:(NSColor*)color;

@end
