# Engineering decisions

MacPulse is a native, local-only macOS 14+ menu-bar monitor. The selected design is the original dark, chart-oriented concept in `design-reference.png`.

## Reuse review

- Selected: Apple SDK frameworks AppKit, SwiftUI, Charts, Darwin, SystemConfiguration and IOKit. SDK 27.0, Swift 6.4, deployment target macOS 14. These installed system APIs provide status items, anchored popovers, accessible controls, chart rendering and system counters. Apple SDK terms apply; no SDK source is redistributed.
- [swift-system-metrics](https://github.com/apple/swift-system-metrics), Apache-2.0: reports process-level metrics; unsuitable for the requested whole-Mac CPU and memory view. Also checked the Swift Package Index entry.
- [Stats](https://github.com/exelban/stats), MIT: maintained complete monitor, useful reference but not a small stable telemetry package. Integrating its full application and helpers would exceed this utility's scope. No source copied.
- Remaining custom work: thin system-counter adapter, delta calculations, rolling one-minute history, native UI composition and packaging. No third-party packages or privileged helper.

API references: [NSStatusItem](https://developer.apple.com/documentation/appkit/nsstatusitem), [NSPopover](https://developer.apple.com/documentation/appkit/nspopover), [IOPowerSources](https://developer.apple.com/documentation/iokit/iopowersources_h).

## Distribution

Native application; no web hosting or Vercel deployment. Public GitHub Releases contain an ad-hoc-signed universal application. Not notarized. Local installation does not disable Gatekeeper or alter system security settings.
