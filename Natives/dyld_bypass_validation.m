// dyld_bypass_validation.m — bypass library validation for unsigned dylibs
// Based on: https://blog.xpnsec.com/restoring-dyld-memory-loading
// Adapted from Amethyst-iOS for SKapsule-iOS (simplified: no iOS 26 TXM paths)

#import <Foundation/Foundation.h>

#include <dlfcn.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include <mach-o/dyld.h>
#include <mach-o/dyld_images.h>
#include <sys/syscall.h>
#include <libkern/OSCacheControl.h>

#include "utils.h"

#if TARGET_OS_SIMULATOR

// Simulator doesn't need dyld bypass
void init_bypassDyldLibValidation(void) {
    NSLog(@"[DyldLVBypass] skipped (simulator)");
}

#else

#define ASM(...) __asm__(#__VA_ARGS__)

// ldr x8, value; br x8; value: .ascii "\x41\x42\x43\x44\x45\x46\x47\x48"
static char patch[] = {
    0x88,0x00,0x00,0x58,
    0x00,0x01,0x1f,0xd6,
    0x1f,0x20,0x03,0xd5,
    0x1f,0x20,0x03,0xd5,
    0x41,0x41,0x41,0x41,0x41,0x41,0x41,0x41
};

// Signatures to search for in dyld
static char mmapSig[] = {0xB0, 0x18, 0x80, 0xD2, 0x01, 0x10, 0x00, 0xD4};
static char fcntlSig[] = {0x90, 0x0B, 0x80, 0xD2, 0x01, 0x10, 0x00, 0xD4};

static int (*orig_fcntl)(int fildes, int cmd, void *param) = NULL;

extern void *__mmap(void *addr, size_t len, int prot, int flags, int fd, off_t offset);
extern int __fcntl(int fildes, int cmd, void *param);

static void builtin_memcpy(char *target, char *source, size_t size) {
    for (size_t i = 0; i < size; i++) {
        target[i] = source[i];
    }
}

kern_return_t builtin_vm_protect(mach_port_name_t task, mach_vm_address_t address,
    mach_vm_size_t size, boolean_t set_max, vm_prot_t new_prot);
ASM(_builtin_vm_protect: \n
    mov x16, #-0xe       \n
    svc #0x80            \n
    ret
);

static bool redirectFunction(char *name, void *patchAddr, void *target) {
    kern_return_t kret = builtin_vm_protect(mach_task_self(), (vm_address_t)patchAddr,
        sizeof(patch), false, PROT_READ | PROT_WRITE | VM_PROT_COPY);
    if (kret != KERN_SUCCESS) {
        NSLog(@"[DyldLVBypass] vm_protect(RW) failed for %s", name);
        return false;
    }

    builtin_memcpy((char *)patchAddr, patch, sizeof(patch));
    *(void **)((char *)patchAddr + 16) = target;
    sys_icache_invalidate((void *)patchAddr, sizeof(patch));

    kret = builtin_vm_protect(mach_task_self(), (vm_address_t)patchAddr,
        sizeof(patch), false, PROT_READ | PROT_EXEC);
    if (kret != KERN_SUCCESS) {
        NSLog(@"[DyldLVBypass] vm_protect(RX) failed for %s", name);
        return false;
    }

    NSLog(@"[DyldLVBypass] hooked %s", name);
    return true;
}

static bool searchAndPatch(char *name, char *base, char *signature, int length, void *target) {
    char *patchAddr = NULL;
    for (int i = 0; i < 0x80000; i += 4) {
        if (base[i] == signature[0] && memcmp(base + i, signature, length) == 0) {
            patchAddr = base + i;
            break;
        }
    }

    if (patchAddr == NULL) {
        NSLog(@"[DyldLVBypass] %s: signature not found", name);
        return false;
    }

    NSLog(@"[DyldLVBypass] found %s at %p", name, patchAddr);
    return redirectFunction(name, patchAddr, target);
}

static void *getDyldBase(void) {
    struct task_dyld_info dyld_info;
    mach_msg_type_number_t count = TASK_DYLD_INFO_COUNT;

    kern_return_t ret = task_info(mach_task_self_,
        TASK_DYLD_INFO, (task_info_t)&dyld_info, &count);
    if (ret != KERN_SUCCESS) return NULL;

    struct dyld_all_image_infos *infos =
        (struct dyld_all_image_infos *)dyld_info.all_image_info_addr;
    return (void *)infos->dyldImageLoadAddress;
}

static void *hooked_mmap(void *addr, size_t len, int prot, int flags, int fd, off_t offset) {
    if (flags & MAP_JIT) {
        errno = EINVAL;
        return MAP_FAILED;
    }

    void *map = __mmap(addr, len, prot, flags, fd, offset);
    if (mprotect(map, len, prot) == -1) {
        munmap(map, len);
        map = MAP_FAILED;
    }
    if (map == MAP_FAILED && fd && (prot & PROT_EXEC)) {
        map = __mmap(addr, len, prot, flags | MAP_PRIVATE | MAP_ANON, 0, 0);
        void *memoryLoadedFile = __mmap(NULL, len, PROT_READ, MAP_PRIVATE, fd, offset);
        mprotect(map, len, PROT_READ | PROT_WRITE);
        memcpy(map, memoryLoadedFile, len);
        mprotect(map, len, prot);
        munmap(memoryLoadedFile, len);
    }
    return map;
}

static int hooked_fcntl(int fildes, int cmd, void *param) {
    if (cmd == F_ADDFILESIGS_RETURN) {
        orig_fcntl(fildes, cmd, param);
        fsignatures_t *fsig = (fsignatures_t *)param;
        fsig->fs_file_start = 0xFFFFFFFF;
        return 0;
    }

    if (cmd == F_CHECK_LV) {
        return 0;
    }

    return orig_fcntl(fildes, cmd, param);
}

void init_bypassDyldLibValidation(void) {
    static BOOL bypassed;
    if (bypassed) return;
    bypassed = YES;

    NSLog(@"[DyldLVBypass] init");

    // SIGBUS may fire while patching exec pages; ignore until JVM launch
    signal(SIGBUS, SIG_IGN);

    orig_fcntl = __fcntl;
    char *dyldBase = getDyldBase();
    if (!dyldBase) {
        NSLog(@"[DyldLVBypass] failed to locate dyld base");
        return;
    }

    searchAndPatch("dyld_mmap", dyldBase, mmapSig, sizeof(mmapSig), hooked_mmap);
    bool fcntlOk = searchAndPatch("dyld_fcntl", dyldBase, fcntlSig, sizeof(fcntlSig), hooked_fcntl);

    if (!fcntlOk) {
        // Dopamine hook fallback: search for a branch instruction before a syscall
        char syscallSig[] = {0x01, 0x10, 0x00, 0xD4};
        char *fcntlAddr = NULL;
        for (int i = 0; i < 0x80000; i += 4) {
            if (dyldBase[i] == syscallSig[0] && memcmp(dyldBase + i, syscallSig, 4) == 0) {
                char *syscallAddr = dyldBase + i;
                uint32_t *prev = (uint32_t *)(syscallAddr - 4);
                if (*prev >> 26 == 0x5) {
                    fcntlAddr = (char *)prev;
                    break;
                }
            }
        }
        if (fcntlAddr) {
            uint32_t *inst = (uint32_t *)fcntlAddr;
            int32_t offset = ((int32_t)((*inst) << 6)) >> 4;
            NSLog(@"[DyldLVBypass] Dopamine hook offset = %x", offset);
            orig_fcntl = (void *)((char *)fcntlAddr + offset);
            redirectFunction("dyld_fcntl (Dopamine)", fcntlAddr, hooked_fcntl);
        } else {
            NSLog(@"[DyldLVBypass] fcntl hook failed (no Dopamine fallback found)");
        }
    }
}

#endif // TARGET_OS_SIMULATOR
