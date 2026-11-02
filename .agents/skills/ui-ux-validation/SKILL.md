---
name: ui-ux-validation
description: "Validate StageKeys SwiftUI workflows, platform layouts, accessibility and synchronization with actual performance state."
---

# Ui Ux Validation

Locate the view and owning Store action before changing bindings. Inspect `StageKeysApp.swift`, `Editors.swift`, `SettingsViews.swift`, `SoundBrowser.swift`, `PluginInterface.swift` and relevant controls. Distinguish saved document, audition draft, loading candidate and installed sound in the UI. Do not show a committed/ready selection before runtime acceptance or overwrite a newer selection on a stale callback.

For every workflow cover initial, empty, loading, success, unavailable, failed and cancelled states. Error text should explain the action and recovery without leaking paths/plugin state. Test Confirm/Discard, sheet dismissal, repeated opening, patch changes while a sheet is open and keyboard focus. Generic AU controls and embedded custom views require scrolling, accessible labels and sensible size constraints; compiled controller code does not prove actual custom UI presentation.

Validate macOS pointer/keyboard shortcuts and focus, iPad touch/rotation/multitasking, and iPhone compact layouts only on available surfaces. Record simulator versus physical device and viewport. Check VoiceOver names/value/action, contrast, dynamic type, focus order and hit targets. Do not infer device usability from a screenshot at one size.

Use deterministic Store tests for state synchronization and an interactive walkthrough for visual behavior; use existing browser/native automation only when appropriate to this native app. Record screenshots with app/version and remove private content before committing evidence. [UI validation](../../templates/ui-validation.md) captures actions and expected/observed state. Similar labels/layouts are not verified reference functionality or audio parity. Unavailable hardware and Demo-blocked reference surfaces stay UNKNOWN.
