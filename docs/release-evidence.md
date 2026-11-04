# Release evidence

This file records verified results, not planned capabilities.

| Area | Current evidence |
|---|---|
| Repository | [danci5/avatodo-hackathon](https://github.com/danci5/avatodo-hackathon), public under Apache-2.0. Unauthenticated access and a fresh mirror of every published branch were verified 4 November 2026. Private planning/design remain separate; public source availability is separate from an installable app release |
| Local task engine | Swift 6 package built on macOS with Xcode 27.0 / Swift 6.4; 9 Swift Testing tests passed on 3 November 2026 using `bash scripts/test.sh` |
| Application build | Not yet verified |
| Physical iPhone/Watch | User reports version 27.2; exact models and current connection not yet verified |
| Meta account requests | Not yet executed from this app |
| Character pipeline | Designed; no verified Muse-generated animation package yet |
| UI | A separate private native SwiftUI design prototype is under review, using system typography and Liquid Glass. Its sample interactions and captures are design evidence. No production UI integrated |
| Installable app / TestFlight | Not released; public source availability is separate from a working device release |
| Demo video / hackathon submission | Not produced / not submitted |

Before release, record source commit, model IDs, device/OS, test results, measured latency, full command-to-saved-result recordings, asset provenance and any limitations. Verify public repository and video access while logged out.

The package tests cover grocery replacement, atomic multi-item completion, undo and reopening, concurrent duplicate requests, payload reuse rejection, stale edits/undo, delete/recover, failed writes, ambiguous titles, invalid inputs and unsupported snapshot versions. These are local domain tests with fictional data, not model, speech, simulator or physical-device evidence. JSON atomic persistence is the development adapter; native SwiftData integration remains planned.
