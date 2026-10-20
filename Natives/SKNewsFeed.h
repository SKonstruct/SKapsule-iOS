#ifndef SKNEWSFEED_H
#define SKNEWSFEED_H

#import <UIKit/UIKit.h>

/// How long each event stays on the card before the next one, as in KnightLauncher.
static const NSTimeInterval SKNewsRotateInterval = 8.0;

/// One event in the card's rotation. imageURL and link are nil when absent or not HTTPS.
@interface SKNewsItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *body;
@property (nonatomic, copy) NSString *imageURL;
@property (nonatomic, copy) NSString *link;
@property (nonatomic, assign) NSTimeInterval startsAt;  // seconds since 1970, 0 if unset
@property (nonatomic, assign) NSTimeInterval endsAt;    // seconds since 1970, 0 if unset
/// Running, with under two days left (KnightLauncher's Event.isEndingSoon).
@property (nonatomic, readonly, getter=isEndingSoon) BOOL endingSoon;
@end

/// Calls back on the main queue with the events to rotate through, in feed order; empty
/// when there are none or the service cannot be reached.
void SKNewsFetch(void (^completion)(NSArray<SKNewsItem *> *items));

/// Calls back on the main queue with the banner image, or nil.
void SKNewsFetchImage(NSString *urlString, void (^completion)(UIImage *image));

/// "Starts in 2d" / "Ends in 5h" / "Ended", or nil when neither bound is set.
NSString *SKNewsStatusLabel(NSTimeInterval startsAt, NSTimeInterval endsAt);

#endif /* SKNEWSFEED_H */
