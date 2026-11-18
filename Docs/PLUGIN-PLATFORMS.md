# Plug-in platform scope

Refs #14. V1 targets installed macOS AUv2/AUv3 instruments. Direct VST3 hosting is deferred; there is no VST-to-AU wrapper or implied VST support. Third-party effect hosting is not required for native conversion. iPhone/iPad require installed iOS AUv3 instruments and separately authorized compatible content. macOS binaries and proprietary library containers are not portable native sounds.

The browser states the current platform scope. A known third-party macOS AUv2 identity is rejected explicitly on mobile. Unknown legacy identities still require actual component discovery; metadata alone does not establish availability. Apple system music devices are handled separately from third-party AUv3.

Editor view requests now carry an active generation. Dismissed/replaced requests cannot attach a view or parameter observer after teardown. Mobile editors use the available sheet viewport with scrolling instead of a mandatory desktop-width frame.

Physical iPad/iPhone qualification is deferred at the owner’s request to #238 and #242. It remains required before a mobile release, independently of completed software/Mac scope #14: install a supported AUv3, load/state-recall it, open/close its editor repeatedly, rotate/split-view, background/foreground, route-change and recover audio. Simulator compilation and Mac AU tests cannot close this gate. TestFlight/App Store signing and runtime plugin isolation remain separate issues.

Kontakt and other proprietary libraries are used through an installed compatible Audio Unit instrument, with separately authorized content. StageKeys does not import Kontakt library containers as native sounds or include those plugins/libraries. The unsupported-format message directs users to a compatible AU. Actual installed-plugin editor, state and failure compatibility remains governed by #12/#13.
