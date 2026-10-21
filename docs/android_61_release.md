# Android 61 development release

Android 61 packages the current shared game source for remote download through
[GitHub Releases](https://github.com/johnwestons/the-picture-shop/releases/tag/android.61).
The release contains the installer, SHA-256 checksum, install instructions and
build verification reports. It is a development test APK, not a store release.

Included: purchase-only Regal Moll folder, neon arcade selector, air-hockey touch
movement wheel, garage exterior sprite, Critter Crisis mobile work, and the current
warehouse, employee, economy, machine and multiplayer fixes. Local Play requires
matching protocol 41 builds. Internet Direct Play remains gated.

The standalone folder test page has three work-order tickets, timing bonuses,
a smaller delivery buffer and timed boxing. Those experiments remain separate
from the APK. Its published source is also archived in `web/regal-folder-lab`.
The drag-to-align/swipe-to-fold picture in `references/regal-folder-ui/concept-v1.png`
is an unimplemented design preview, not an APK feature.

The APK must be built from the committed source; release verification records
the exact commit, runtime archive checksum and APK checksum. Automated tests do
not establish physical phone/tablet acceptance. A fresh install, touch check,
background/resume, offline reload and matching-build multiplayer soak remain
device checks for this release.

Download on the phone and open the APK in Downloads/My Files. Fresh test saves
were requested: download first, uninstall only The Picture Shop without keeping
its data, then install. Installing over a compatible signed build instead keeps
its saves. No device data is changed by publishing the release.
