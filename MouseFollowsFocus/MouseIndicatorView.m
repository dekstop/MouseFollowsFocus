//
//  MouseIndicatorView.m
//  MouseFollowsFocus
//
//  Created by mongo on 26/02/2013.
//  Copyright (c) 2013 martind. All rights reserved.
//

#import "MouseIndicatorView.h"

@implementation MouseIndicatorView

- (id)initWithFrame:(NSRect)frame color:(NSColor*)_color
{
    self = [super initWithFrame:frame];
    if (self) {
        color = _color;
    }
    
    return self;
}

- (void)drawRect:(NSRect)dirtyRect
{
    [[NSColor clearColor] set];
    NSRectFill([self frame]);
    
    NSBezierPath* circlePath = [NSBezierPath bezierPath];
    [circlePath appendBezierPathWithOvalInRect: dirtyRect];
    [color setFill];
    [circlePath fill];
//    [[NSColor blackColor] setStroke];
//    [circlePath stroke];
}

@end
