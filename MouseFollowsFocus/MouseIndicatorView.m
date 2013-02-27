//
//  MouseIndicatorView.m
//  MouseFollowsFocus
//
//  Created by mongo on 26/02/2013.
//  Copyright (c) 2013 martind. All rights reserved.
//

#import "MouseIndicatorView.h"

@implementation MouseIndicatorView

float scale;
float initialSize;

- (id)initWithFrame:(NSRect)frame color:(NSColor*)_color
{
    self = [super initWithFrame:frame];
    if (self) {
        color = _color;
        scale = 1.0;
        initialSize = 0.1;
    }
    
    return self;
}

- (void)setScale:(float)_scale
{
    scale = _scale;
}

- (void)drawRect:(NSRect)dirtyRect
{
    [[NSColor clearColor] set];
    NSRectFill([self frame]);
    
    float size = initialSize + scale * (1.0 - initialSize);
    
    dirtyRect.origin.x += dirtyRect.size.width * (1-size)/2;
    dirtyRect.origin.y += dirtyRect.size.height * (1-size)/2;
    dirtyRect.size.height *= size;
    dirtyRect.size.width *= size;
    
    NSBezierPath* circlePath = [NSBezierPath bezierPath];
    [circlePath appendBezierPathWithOvalInRect: dirtyRect];
    [color setFill];
    [circlePath fill];
//    [[NSColor blackColor] setStroke];
//    [circlePath stroke];
}

@end
