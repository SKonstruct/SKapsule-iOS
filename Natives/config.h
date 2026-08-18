#ifndef CONFIG_H
#define CONFIG_H

#define CONFIG_BRANCH ""
#define CONFIG_COMMIT ""

/* #undef CONFIG_RELEASE */
#ifdef CONFIG_RELEASE
#define CONFIG_TYPE "release"
#else
#define CONFIG_TYPE "debug"
#endif

#endif /* CONFIG_H */
