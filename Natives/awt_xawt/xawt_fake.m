// xawt_fake: minimal stubs so the JRE's AWT can load libawt_xawt.dylib without
// pulling in X11. Caciocavallo replaces the actual toolkit at runtime; these
// symbols just prevent link-time failures.

#import <Foundation/Foundation.h>

void awt_xawt_stub(void) {}
