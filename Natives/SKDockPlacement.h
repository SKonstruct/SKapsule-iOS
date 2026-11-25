#pragma once

#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

// Where the selected control's small dialog goes in the touch editor. Header-only and Foundation-only so
// `make test` runs it; the same rule and the same cases as Android's DialogDock.kt (keep them in step).
//
// The spot must not cover the control (the player is dragging it), must stay clear of the reserved areas
// (the tab strip and the Done button), covers as little of the other controls as it can, and is as far from
// the control as the screen allows. The candidates are the four corners and four edge middles. If nothing
// is free (a very small screen) the farthest candidate is used anyway.

static inline CGFloat SKRectOverlapArea(CGRect a, CGRect b) {
    CGRect i = CGRectIntersection(a, b);
    return CGRectIsNull(i) ? 0 : i.size.width * i.size.height;
}

static inline BOOL SKRectsOverlap(CGRect a, CGRect b) {
    return SKRectOverlapArea(a, b) > 0;
}

static inline CGPoint SKDockPlace(CGSize screen, CGSize dialog, CGRect control, const CGRect *reserved,
                                  int reservedCount, const CGRect *others, int othersCount, CGFloat margin,
                                  CGFloat gap) {
    CGFloat right = screen.width - dialog.width - margin;
    CGFloat bottom = screen.height - dialog.height - margin;
    CGFloat midX = (screen.width - dialog.width) / 2;
    CGFloat midY = (screen.height - dialog.height) / 2;
    CGPoint candidates[8] = {
        {margin, margin}, {right, margin}, {margin, bottom}, {right, bottom},
        {margin, midY},   {right, midY},   {midX, margin},   {midX, bottom},
    };
    CGRect keepClear = CGRectInset(control, -gap, -gap);
    CGPoint chosen = candidates[0];
    BOOL haveChoice = NO;
    // Three passes of preference: free of the control and reserved areas, then free of the control only, then any.
    for (int pass = 0; pass < 3 && !haveChoice; pass++) {
        CGFloat bestCovered = 0, bestDistance = 0;
        for (int i = 0; i < 8; i++) {
            CGRect box = CGRectMake(candidates[i].x, candidates[i].y, dialog.width, dialog.height);
            if (pass < 2 && SKRectsOverlap(box, keepClear)) continue;
            BOOL clashes = NO;
            for (int r = 0; pass == 0 && r < reservedCount; r++) {
                if (SKRectsOverlap(box, reserved[r])) clashes = YES;
            }
            if (clashes) continue;
            CGFloat covered = 0;
            for (int o = 0; o < othersCount; o++) covered += SKRectOverlapArea(box, others[o]);
            CGFloat dx = CGRectGetMidX(box) - CGRectGetMidX(control);
            CGFloat dy = CGRectGetMidY(box) - CGRectGetMidY(control);
            CGFloat distance = dx * dx + dy * dy;
            if (!haveChoice || covered < bestCovered || (covered == bestCovered && distance > bestDistance)) {
                haveChoice = YES;
                bestCovered = covered;
                bestDistance = distance;
                chosen = candidates[i];
            }
        }
    }
    return chosen;
}
