#pragma once

#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

// Where the selected control's small dialog goes in the touch editor. Header-only and Foundation-only so
// `make test` runs it; the same rule and the same cases as Android's DialogDock.kt (keep them in step).
//
// Fixed at the top right, `margin` in from the edges, so it is always in the same place. It is moved down only
// as far as needed to clear the reserved areas up there (the standalone editor's Done button), and never off
// the bottom of the screen.

static inline CGPoint SKDockPlace(CGSize screen, CGSize dialog, const CGRect *reserved, int reservedCount,
                                  CGFloat margin, CGFloat gap) {
    CGFloat x = screen.width - dialog.width - margin;
    CGFloat y = margin;
    // Highest first, so one pass clears a stack of reserved areas.
    BOOL used[8] = {NO};
    for (int pass = 0; pass < reservedCount && pass < 8; pass++) {
        int next = -1;
        for (int i = 0; i < reservedCount && i < 8; i++) {
            if (!used[i] && (next < 0 || reserved[i].origin.y < reserved[next].origin.y)) next = i;
        }
        if (next < 0) break;
        used[next] = YES;
        if (CGRectIntersectsRect(CGRectMake(x, y, dialog.width, dialog.height), reserved[next])) {
            y = CGRectGetMaxY(reserved[next]) + gap;
        }
    }
    CGFloat maxY = MAX(0, screen.height - dialog.height - margin);
    return CGPointMake(x, MIN(MAX(y, 0), maxY));
}
