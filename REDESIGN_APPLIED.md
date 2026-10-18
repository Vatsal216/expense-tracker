# Fintech UI implementation — v10

This repository contains the full source with the premium fintech redesign applied directly.

## Included changes

- Material 3 light and dark themes with accessible ink, muted text, borders, fields and navigation states.
- Shared 4-point spacing and corner-radius tokens in `lib/fintech_design.dart`.
- Explicit high-contrast `FintechFilterPill` controls on Dashboard, Money Map and transaction filters.
  - Inactive: dark readable text on a white surface.
  - Active: white text and icon on a green surface.
  - Minimum 44px touch target and semantic selected state.
- Responsive Bento layout for the Reports summary metrics.
- Existing dashboard filtering, custom range persistence, local finance planner, recurring-payment tab,
  transaction drill-downs, SMS classification and UPI code are preserved.

## v10 full-tab redesign pass

The original main-branch UI had a mixture of older white containers and newer green cards. That caused
weak contrast in dark mode and made the tabs feel like separate designs. The v10 source resolves this
with shared components used across every primary tab:

- **Home:** responsive Bento quick actions; readable Week/Month/Day filters.
- **Activity:** consistent filter controls and redesigned adaptive transaction cards.
- **Pay:** retains the purpose-built UPI flow, now inherits the same Material 3 inputs, typography and
  button system.
- **Plan:** planner and recurring tabs share the same app bar, tab and surface tokens.
- **Reports:** responsive Bento summary, de-duplicated highlights and drill-down cards.
- **Settings / Budgets:** redesigned adaptive settings sections, empty states and budget cards.

The new `FintechSurface` replaces hard-coded white panels, so it automatically adapts to both light and
dark themes while maintaining the design system's border, spacing and touch behaviour.

## Build

Run `bash bootstrap.sh`, then `flutter pub get` and `flutter build apk --debug`.

The current workspace did not include a Flutter/Dart SDK, so source validation was performed with the
redesign installer smoke test. Run `dart format lib/main.dart lib/fintech_design.dart`, `flutter analyze`
and `flutter test` in a Flutter environment before release.
