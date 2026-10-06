# Design QA

final result: passed

## Target and evidence

- Source visual truth: `docs/design-reference.png`, original second concept selected by the user. The later symbol-only revision was explicitly rejected for implementation.
- Implementation: native MacPulse NSPopover with live host metrics, captured through native computer-use tools on macOS. This is a working macOS application, not a web prototype.
- Private implementation screenshot: `../../work/evidence/panel-live.png` (892 × 1270 pixels, including native popover shadow).
- Private full-view comparison: `../../work/evidence/comparison.png`. Source panel crop (782,56)–(1425,983), 643 × 927 pixels, normalized to 420 × 606. Implementation content crop (26,26)–(866,1244), 840 × 1218 pixels, normalized from 2× to 420 × 609 points. These evidence files contain local system measurements and are deliberately not published.
- State: dark theme, open primary monitor, approximately one minute of real history. Mock values in the source were replaced with live values. No data was fabricated to match the source.
- Native viewport: 420-point-wide panel, content about 610 points high; no browser or device frame.

## Findings and comparison history

1. Initial native capture: panel was about 60 points taller than the selected concept. Reduced chart height and section/header/footer padding. The memory total used decimal gigabytes, which was inconsistent with familiar macOS memory presentation; changed memory only to binary GB. Network interface discovery initially fell back to an unrelated auxiliary interface; changed it to the actual default route and 64-bit counters.
2. Rebuilt and recaptured the real application. The combined, normalized comparison shows matching vertical information order, comparable panel proportions, green CPU/blue memory charts, download/upload split, storage/battery rows and footer action. No clipping or overlapping controls remains.
3. Focused inspection of header, memory subtitle/axis, transfer rates and bottom actions at 2× confirms legibility. Numeric values and history shapes differ by design because these are actual measurements.

## Required fidelity surfaces

- Typography: native system font, semibold section labels and percentages, monospaced digits. Korean labels match the source. Values fit at observed and expected widths.
- Spacing/layout: original single-column hierarchy preserved. Final panel dimensions are close to the normalized concept; native popover corners and anchor follow the host macOS version.
- Colors/tokens: charcoal panel, muted gray labels, green CPU, blue memory/download, purple upload. The production surface is a stable opaque charcoal; the concept contains subtle wallpaper tinting.
- Image quality/assets: SF Symbols for settings, arrows, storage, battery and chevrons; Swift Charts for live data. The desktop wallpaper and editorial concept caption are not app-owned UI and are not reproduced.
- Copy/content: source labels retained, with explicit loading/unavailable states. App name/version/privacy explanation are in settings. Actual disk, battery and network semantics are documented in README.

## Interactions and practical limits

- Verified running native panel, live updates and 60-second bounded history; settings open/back, 1→2→1 second selection, and Quit/relaunch.
- Verified Activity Monitor launch via the footer.
- Login-item registration is implemented through SMAppService but left disabled; no forced login-item change or reboot test was performed.
- Escape has an explicit local key handler. The automation's subsequent app lookup reopens the app, so a persistent closed-state assertion is not used as proof of keyboard dismissal.
- Sleep/wake handlers reset baselines; physical sleep/wake and network disconnection were not forced during user work. Counter reset and interface-switch arithmetic are covered separately.
- Apple Silicon live runtime verified. Intel binary is included and compiled; Intel hardware runtime is not claimed.

## Follow-up polish

- P3: native corners and very slight chart-label spacing differ from the generated concept. These are platform rendering/polish differences, not blocked workflows.
- No actionable P0/P1/P2 findings remain.
