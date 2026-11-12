#ifndef CONFIG_H
#define CONFIG_H

#define CONFIG_VERSION "1.0.2"
#define CONFIG_BRANCH "main"
#define CONFIG_COMMIT "adbd169"

/* #undef CONFIG_RELEASE */
#ifdef CONFIG_RELEASE
#define CONFIG_TYPE "release"
#else
#define CONFIG_TYPE "debug"
#endif

#endif /* CONFIG_H */
