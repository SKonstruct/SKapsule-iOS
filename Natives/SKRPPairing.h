#pragma once

#include <stddef.h>
#include <stdint.h>

/*
 * On-device remote pairing (iOS 27 and later), implemented by Natives/RPPairing (Rust) and
 * linked as libskrppairing.a by scripts/build-rppairing-ios.sh. Keep in step with
 * Natives/RPPairing/src/lib.rs.
 */

typedef struct SkrpSession SkrpSession;
typedef void (*SkrpPinCallback)(const char *pin, void *context);

/* New host identity and a listener on all IPv4 interfaces. NULL on failure, with *error set
   (free with skrp_string_free). */
SkrpSession *skrp_new(const char *name, char **error);
uint16_t skrp_port(const SkrpSession *session);
/* The Bonjour instance name to publish; owned by the session. */
const char *skrp_service_name(const SkrpSession *session);
size_t skrp_txt_count(const SkrpSession *session);
const char *skrp_txt_key(const SkrpSession *session, size_t index);
const char *skrp_txt_value(const SkrpSession *session, size_t index);

/* Blocks until paired (0), failed (1, *error set) or cancelled (2). On success *out_plist and
   *out_len hold the pairing file (skrp_bytes_free) and *out_device_name the device's name
   (skrp_string_free). Call once per session. */
int32_t skrp_accept(const SkrpSession *session, SkrpPinCallback pin_callback, void *pin_context,
                    uint8_t **out_plist, size_t *out_len, char **out_device_name, char **error);
/* Ends a running or future skrp_accept with 2. Any thread. */
void skrp_cancel(const SkrpSession *session);
/* Only after skrp_accept has returned (or was never called). */
void skrp_free(SkrpSession *session);
void skrp_bytes_free(uint8_t *bytes, size_t len);
void skrp_string_free(char *string);
