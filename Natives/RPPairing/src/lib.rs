//! On-device remote pairing for built-in JIT (iOS 27 and later). See SKRPPairing.h.
//!
//! The device lists every `_remotepairing-pairable-host._tcp` service under Settings > Privacy &
//! Security > Developer Mode, and pairing with one asks for a PIN the "computer" shows. This plays
//! that computer for the device it runs on: it listens on a TCP port, hands the port and TXT records
//! to the app to publish over Bonjour, runs idevice's `PairableHost` and returns the pairing file.

use std::ffi::{c_char, c_void, CStr, CString};
use std::net::TcpListener as StdListener;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::ptr;
use std::sync::{Arc, Mutex};

use idevice::remote_pairing::{PairableHost, PairableHostInfo, RpPairingFile, RpPairingSocket};
use tokio::net::TcpListener;
use tokio::runtime::Runtime;
use tokio::sync::Notify;

pub struct SkrpSession {
    runtime: Runtime,
    listener: Mutex<Option<TcpListener>>,
    info: PairableHostInfo,
    file: RpPairingFile,
    port: u16,
    service_name: CString,
    txt: Vec<(CString, CString)>,
    cancel: Arc<Notify>,
}

pub type SkrpPinCallback = extern "C" fn(pin: *const c_char, context: *mut c_void);

/// A raw pointer the callback is handed back; the caller promises it is usable from any thread.
struct Context(*mut c_void);
unsafe impl Send for Context {}

fn set_error(out: *mut *mut c_char, message: impl Into<Vec<u8>>) {
    if out.is_null() {
        return;
    }
    let text = CString::new(message).unwrap_or_else(|_| CString::new("error").unwrap());
    unsafe { *out = text.into_raw() };
}

fn guarded<T>(error: *mut *mut c_char, fallback: T, body: impl FnOnce() -> Result<T, String>) -> T {
    match catch_unwind(AssertUnwindSafe(body)) {
        Ok(Ok(value)) => value,
        Ok(Err(message)) => {
            set_error(error, message);
            fallback
        }
        Err(_) => {
            set_error(error, "internal error");
            fallback
        }
    }
}

/// New host identity and a listener on all IPv4 interfaces. NULL on failure, with `*error` set.
#[no_mangle]
pub unsafe extern "C" fn skrp_new(name: *const c_char, error: *mut *mut c_char) -> *mut SkrpSession {
    guarded(error, ptr::null_mut(), || {
        let name = if name.is_null() { "SKapsule".to_string() } else { CStr::from_ptr(name).to_string_lossy().into_owned() };
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .map_err(|e| format!("runtime: {e}"))?;

        let std_listener = StdListener::bind("0.0.0.0:0").map_err(|e| format!("listen: {e}"))?;
        std_listener.set_nonblocking(true).map_err(|e| format!("listen: {e}"))?;
        let port = std_listener.local_addr().map_err(|e| format!("listen: {e}"))?.port();
        let listener = {
            let _guard = runtime.enter();
            TcpListener::from_std(std_listener).map_err(|e| format!("listen: {e}"))?
        };

        // The identifier is derived from the name, so every pairing replaces the device's earlier
        // record for this app: only the newest pairing file works, which is what we want.
        let file = RpPairingFile::generate(&name);
        let info = PairableHostInfo::generate(name, "Mac17,7");
        let identifier = file.identifier().to_string();
        let txt = info
            .mdns_txt_records(&identifier)
            .into_iter()
            .filter_map(|(k, v)| Some((CString::new(k).ok()?, CString::new(v).ok()?)))
            .collect();

        Ok(Box::into_raw(Box::new(SkrpSession {
            runtime,
            listener: Mutex::new(Some(listener)),
            info,
            file,
            port,
            service_name: CString::new(identifier).map_err(|e| e.to_string())?,
            txt,
            cancel: Arc::new(Notify::new()),
        })))
    })
}

#[no_mangle]
pub unsafe extern "C" fn skrp_port(session: *const SkrpSession) -> u16 {
    session.as_ref().map_or(0, |s| s.port)
}

/// The Bonjour instance name to publish; owned by the session.
#[no_mangle]
pub unsafe extern "C" fn skrp_service_name(session: *const SkrpSession) -> *const c_char {
    session.as_ref().map_or(ptr::null(), |s| s.service_name.as_ptr())
}

#[no_mangle]
pub unsafe extern "C" fn skrp_txt_count(session: *const SkrpSession) -> usize {
    session.as_ref().map_or(0, |s| s.txt.len())
}

#[no_mangle]
pub unsafe extern "C" fn skrp_txt_key(session: *const SkrpSession, index: usize) -> *const c_char {
    session.as_ref().and_then(|s| s.txt.get(index)).map_or(ptr::null(), |(k, _)| k.as_ptr())
}

#[no_mangle]
pub unsafe extern "C" fn skrp_txt_value(session: *const SkrpSession, index: usize) -> *const c_char {
    session.as_ref().and_then(|s| s.txt.get(index)).map_or(ptr::null(), |(_, v)| v.as_ptr())
}

/// Blocks until paired (0), failed (1, `*error` set) or cancelled (2).
#[no_mangle]
pub unsafe extern "C" fn skrp_accept(
    session: *const SkrpSession,
    pin_callback: SkrpPinCallback,
    pin_context: *mut c_void,
    out_plist: *mut *mut u8,
    out_len: *mut usize,
    out_device_name: *mut *mut c_char,
    error: *mut *mut c_char,
) -> i32 {
    guarded(error, 1, || {
        let session = session.as_ref().ok_or("no session")?;
        let listener = session.listener.lock().map_err(|_| "busy")?.take().ok_or("already accepted")?;
        let context = Context(pin_context);
        let mut file = session.file.clone();
        let info = session.info.clone();
        let cancel = session.cancel.clone();

        let outcome = session.runtime.block_on(async move {
            let pairing = async {
                let (stream, _) = listener.accept().await.map_err(|e| format!("accept: {e}"))?;
                let mut host = PairableHost::new(RpPairingSocket::new_device(stream), info);
                let context = context;
                let peer = host
                    .accept(&mut file, |pin| async move {
                        if let Ok(pin) = CString::new(pin) {
                            pin_callback(pin.as_ptr(), context.0);
                        }
                    })
                    .await
                    .map_err(|e| format!("{e}"))?;
                Ok::<_, String>((file.to_bytes(), peer.name))
            };
            tokio::select! {
                result = pairing => Some(result),
                _ = cancel.notified() => None,
            }
        });

        match outcome {
            None => Ok(2),
            Some(Err(message)) => Err(message),
            Some(Ok((bytes, device_name))) => {
                let mut boxed = bytes.into_boxed_slice();
                *out_len = boxed.len();
                *out_plist = boxed.as_mut_ptr();
                std::mem::forget(boxed);
                *out_device_name = CString::new(device_name).unwrap_or_default().into_raw();
                Ok(0)
            }
        }
    })
}

/// Ends a running or future accept with 2. Any thread.
#[no_mangle]
pub unsafe extern "C" fn skrp_cancel(session: *const SkrpSession) {
    if let Some(s) = session.as_ref() {
        s.cancel.notify_one();
    }
}

/// Only after accept has returned (or was never called).
#[no_mangle]
pub unsafe extern "C" fn skrp_free(session: *mut SkrpSession) {
    if !session.is_null() {
        drop(Box::from_raw(session));
    }
}

#[no_mangle]
pub unsafe extern "C" fn skrp_bytes_free(bytes: *mut u8, len: usize) {
    if !bytes.is_null() {
        drop(Box::from_raw(std::slice::from_raw_parts_mut(bytes, len)));
    }
}

#[no_mangle]
pub unsafe extern "C" fn skrp_string_free(string: *mut c_char) {
    if !string.is_null() {
        drop(CString::from_raw(string));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    extern "C" fn no_pin(_: *const c_char, _: *mut c_void) {}

    #[test]
    fn session_advertises_and_cancels() {
        unsafe {
            let mut error = ptr::null_mut();
            let name = CString::new("SKapsule").unwrap();
            let session = skrp_new(name.as_ptr(), &mut error);
            assert!(!session.is_null() && error.is_null());
            assert!(skrp_port(session) > 0);
            assert!(!skrp_service_name(session).is_null());

            let keys: Vec<String> = (0..skrp_txt_count(session))
                .map(|i| CStr::from_ptr(skrp_txt_key(session, i)).to_string_lossy().into_owned())
                .collect();
            for needed in ["name", "identifier", "authTag", "model", "ver"] {
                assert!(keys.iter().any(|k| k == needed), "missing TXT key {needed}");
            }

            // A cancel before accept still ends the accept.
            skrp_cancel(session);
            let (mut plist, mut len, mut device) = (ptr::null_mut(), 0usize, ptr::null_mut());
            let code = skrp_accept(session, no_pin, ptr::null_mut(), &mut plist, &mut len, &mut device, &mut error);
            assert_eq!(code, 2);
            skrp_free(session);
        }
    }
}
