//
//  MouseIndicator.m
//  MouseFollowsFocus
//
//  Created by mongo on 26/02/2013.
//  Copyright (c) 2013 martind. All rights reserved.
//

#import "MouseIndicatorWindow.h"
#import "MouseIndicatorView.h"

@implementation MouseIndicatorWindow

MouseIndicatorView *mouseIndicatorView;
NSTimer *timer;

float initialAlpha = 0.8;
double startTime = 0;

- (id)initWithSize:(int)_size color:(NSColor*)color
{
    self = [super
            initWithContentRect:NSMakeRect(0, 0, _size, _size)
            styleMask:NSBorderlessWindowMask
            backing:NSBackingStoreBuffered defer:NO
//            screen:screen
            ];
    if (self)
    {
        size = _size;
        timerInterval = 0.05;
        duration = 0.5;

        [self setReleasedWhenClosed:NO];
        [self setLevel:NSScreenSaverWindowLevel];
        [self setIgnoresMouseEvents:YES];
        [self setOpaque:NO];
        [self setAlphaValue:0.0];

        mouseIndicatorView = [[MouseIndicatorView alloc] initWithFrame:[self frame] color:color];
        [self.contentView addSubview:mouseIndicatorView];
}
    return self;
}

- (void) showAt:(NSPoint)mousePos onScreen:(NSScreen*)screen
{
    [self setFrame:NSMakeRect(mousePos.x - size/2,
                              mousePos.y - size/2,
                              size,
                              size)
           display:YES];
    [self orderFront:nil];
    
    if ([timer isValid]) {
        [timer invalidate]; // Stop active timer
    }
    [self setAlphaValue:initialAlpha];
    startTime = CACurrentMediaTime();
    timer = [NSTimer scheduledTimerWithTimeInterval:timerInterval
                                                           target:self
                                                         selector:@selector(updateDisplayTimer)
                                                         userInfo:nil
                                                          repeats:YES];
}

- (void) updateDisplayTimer
{
    double elapsedTime = CACurrentMediaTime() - startTime;
    
    float alpha;
    if (elapsedTime >= duration) {
        alpha = 0.0;
        [timer invalidate];
        [self close];
    } else {
        alpha = initialAlpha * (duration - elapsedTime) / duration;
        alpha *= alpha;
    }
    
    [self setAlphaValue:alpha];
    [self display];
}

@end
