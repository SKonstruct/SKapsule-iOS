#pragma once

/**
 * Mouse buttons as a bitmask: bit 0 left, 1 right, 2 middle (UIKit's button mask and GLFW's
 * button numbers agree on this). A mouse or trackpad is one pointer however many buttons it
 * has, so a second button never starts a touch of its own and releasing the first while the
 * second is held never ends one; the press and release of each button is the difference
 * between two masks.
 */
static inline void SKMouseButtonChanges(unsigned previous, unsigned now, unsigned *pressed, unsigned *released) {
    *pressed = now & ~previous;
    *released = previous & ~now;
}
