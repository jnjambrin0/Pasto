## What and why

<!-- What this change does and the problem it solves. Link the issue: "Fixes #123". -->

## How it was checked

<!-- Tests added or run, and what you tried by hand in the app (light and dark, English and Spanish if it touches text). -->

- [ ] `scripts/build.sh` succeeds without new warnings
- [ ] `scripts/test.sh` passes
- [ ] New logic has unit tests (pure logic only; see docs/DEVELOPMENT.md)

## Checklist

- [ ] Every new or changed user-facing string is in the module's string catalog, in English and Spanish
- [ ] No module depends on a module in its own layer or above it (docs/ARCHITECTURE.md)
- [ ] VoiceOver, keyboard navigation, Reduce Motion and Increase Contrast still work for what changed
- [ ] Nothing new leaves the Mac, and nothing copied reaches the logs in clear text
- [ ] All code and assets are my own work or properly licensed, and none come from another product

## Screenshots

<!-- For visible changes: before and after. -->
