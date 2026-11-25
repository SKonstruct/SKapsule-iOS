# Third-party skills

Copied unmodified from https://github.com/rshankras/claude-code-apple-skills
at commit 9ffb83138209057875698dd11c1720c657c47a92 (MIT, see LICENSE-apple-skills.txt), 2026-10-21:

- skills/ios/run-simulator -> run-simulator/
- skills/testing/flow-walkthrough -> flow-walkthrough/
- skills/swift/concurrency-patterns -> swift-concurrency-patterns/

Copied unmodified from https://github.com/conorluddy/ios-simulator-skill at
commit e38b3ad (MIT, see LICENSE-ios-simulator-skill.txt), 2026-10-25:

- ios-simulator-skill/skills/ios-simulator-skill -> ios-simulator-skill/ (screen mapping, tap/type
  by accessibility label, screenshots, logs, simctl; needs Python 3.12+ and `idb`; scripts make no
  network calls)

Copied unmodified from https://github.com/twostraws/SwiftUI-Agent-Skill (1eac100) and
https://github.com/twostraws/Swift-Concurrency-Agent-Skill (bee3f69), Paul Hudson, MIT, 2026-10-25
(see LICENSE-twostraws-skills.txt): `swift-concurrency-pro/` only (`swiftui-pro` not copied: no SwiftUI here). Markdown only.

Considered and skipped: callstack/agent-device (duplicates ios-simulator-skill, adds an npm
dependency), lycorp-jp/sim-use (brew binary; its extra value is physical iPhones).
