#ifndef CONFIG_H
#define CONFIG_H

#define CONFIG_BRANCH "main"
#define CONFIG_COMMIT "f817d0f"

#define CONFIG_RELEASE 1
#ifdef CONFIG_RELEASE
#define CONFIG_TYPE "release"
#else
#define CONFIG_TYPE "debug"
#endif

#endif /* CONFIG_H */
