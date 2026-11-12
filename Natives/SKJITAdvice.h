#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * What to tell the user when built-in JIT cannot reach this device's debug service. The
 * helper's own errors are a library's wording ("early eof", "connection reset"); the cause
 * is almost always one of three things the user can fix. Pure functions so `make test`
 * can cover them. The route rule: LocalDevVPN's tunnel is a VPN interface, and nothing else carries 10.7.0.1.
 */
typedef NS_ENUM(NSInteger, SKJITConnectionProblem) {
    SKJITProblemNone = 0,
    /// Nothing answered at LocalDevVPN's address: it is off, not routing, or on cellular data.
    SKJITProblemUnreachable,
    /// The device closed the connection: it no longer accepts this pairing file.
    SKJITProblemPairing,
    /// The connection opened but the service never spoke: another VPN is carrying the traffic.
    SKJITProblemOtherVPN,
};

static inline SKJITConnectionProblem SKJITProblemFromMessage(NSString *helperMessage) {
    NSString *text = helperMessage.lowercaseString;
    BOOL (^has)(NSArray<NSString *> *) = ^BOOL(NSArray<NSString *> *needles) {
      for (NSString *needle in needles) {
          if ([text containsString:needle]) return YES;
      }
      return NO;
    };
    if (has(@[ @"connectionreset", @"connection reset", @"device refused connection" ])) return SKJITProblemPairing;
    if (has(@[ @"early eof", @"unexpected eof" ])) return SKJITProblemOtherVPN;
    if (has(@[
            @"connectionrefused", @"connection refused", @"timedout", @"timed out", @"networkunreachable",
            @"network unreachable", @"hostunreachable", @"host unreachable", @"no route"
        ]))
        return SKJITProblemUnreachable;
    return SKJITProblemNone;
}

/// `cellularOnly`: cellular data is the only network up, which breaks LocalDevVPN's loopback.
static inline NSString *_Nullable SKJITAdviceForProblem(SKJITConnectionProblem problem, BOOL cellularOnly) {
    switch (problem) {
        case SKJITProblemPairing:
            return @"The device no longer accepts this pairing file (each new pairing replaces the last). "
                   @"Import a fresh one in JIT Setup.";
        case SKJITProblemOtherVPN:
            return @"Another VPN seems to be carrying the traffic. Turn it off and connect LocalDevVPN.";
        case SKJITProblemUnreachable:
            return cellularOnly
                       ? @"LocalDevVPN's loopback does not work over cellular data. Connect to Wi-Fi, or connect "
                         @"LocalDevVPN and then turn on Airplane Mode."
                       : @"Connect LocalDevVPN, then try again.";
        case SKJITProblemNone:
            break;
    }
    return nil;
}

/// A failure message with the advice for its cause appended; unchanged when the cause is unknown.
static inline NSString *SKJITMessageWithAdvice(NSString *message, BOOL cellularOnly) {
    NSString *advice = SKJITAdviceForProblem(SKJITProblemFromMessage(message), cellularOnly);
    return advice ? [NSString stringWithFormat:@"%@\n\n%@", message, advice] : message;
}

NS_ASSUME_NONNULL_END
