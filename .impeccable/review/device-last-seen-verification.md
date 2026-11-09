# Device Last Online Time

Scope: Windows device cards and Android device rows. Preserve the incumbent
NearLink theme; this is a small Operate-surface refinement.

## Behavior

- Offline devices show a clock icon, a secondary label and the last online time.
- Recent observations use relative minutes; older ones use local calendar dates.
- Hover or long press exposes a full local timestamp including seconds.
- Narrow layouts wrap the date instead of truncating it. Desktop actions align
  between online and offline cards at the reviewed sizes.
- UTC timestamps persist across restart, update on rediscovery and are saved
  when a device times out. Online presence is checkpointed every 30 seconds.
- Legacy records without valid timestamps and unseen group members stay unknown.

## Visual Review

Verdict: ship for this refinement. Reviewed rendered Flutter widget captures:

- `devices-last-seen-1440.png`: desktop, normal text.
- `devices-last-seen-440.png`: narrow desktop, 1.3x text.
- `android-widget-devices-last-seen-390.png`: phone, normal text.
- `android-widget-devices-last-seen-320.png`: small phone, 1.3x text.

Names, addresses and dates in these captures are synthetic test fixtures.
The captures are layout evidence, not new native-device or network verification.

## Validation

- Regression run: 183 passed, one optional screenshot test skipped.
- The real-LAN UDP discovery test was excluded to avoid broadcasting temporary
  test identities into running user instances.
- Final focused checks: 10 passed, covering timestamp persistence, legacy data,
  timeout saving, local dates and existing NAT/forwarded endpoint behavior.
- Windows and Android layout capture checks: four passed.
- `flutter analyze --no-pub`: no issues found.

Existing installers/APKs and running Windows instances were not replaced.
