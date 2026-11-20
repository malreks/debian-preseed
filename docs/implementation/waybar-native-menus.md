# Native Waybar menu ownership

Fresh installations render the module objects, GtkBuilder XML and fixed action
commands together. Waybar owns each GTK menu inside its existing Wayland surface.
Tomat, Wayscriber, notifications and power retain their module identities and
canonical `menu-file` and `menu-actions` data. Their primary menu event is
`on-click`; the former standalone popup opening command is removed. Secondary
actions and scrolling retain their separate bindings. Native brightness,
battery and clock menus also use a registered press event.

Waybar 0.15.0's ALabel constructor enables button-press handling when a menu is
configured. AModule registers button-release handling only when a release
command is configured. A `menu=on-click-release` entry alone therefore does not
establish its event subscription. The packaged in-process menu callback passes
the actual input event to GTK. The relevant upstream sources are
[ALabel](https://github.com/Alexays/Waybar/blob/0.15.0/src/ALabel.cpp) and
[AModule](https://github.com/Alexays/Waybar/blob/0.15.0/src/AModule.cpp).

The standalone helper was reproduced under native headless labwc 0.20.3 and
packaged Waybar 0.15.0 with GTK3: `popup_at_pointer(None)` reported no trigger
event, failed its anchor-window assertion and remained unmapped. GTK documents
that a null trigger uses the current event; a separately started process does
not inherit Waybar's event or surface. See the
[GTK popup API](https://docs.gtk.org/gtk3/method.Menu.popup_at_pointer.html).
The helper, its dispatcher option, staging entry and AppArmor attachment are
retired. No fabricated GDK input event, serial, persistent anchor, public
Xwayland or desktop package source build is involved.

`scripts/desktop/waybar-menus.py` is an installation-only validator. The existing
private target setup boundary removes it after execution. It validates protected
rendered files, unique JSON and GtkBuilder identities, a one-to-one mapping of
actionable leaf menu items to actions, one native menu event owner, and every
command through the actual fixed runner's allowlist. There is no second action
table. Runtime dispatch remains nonblocking and puts the real application in
its independent managed service.

The packaged native menu API does not export authoritative popup-open state.
Tomat reports its actual timer phase, notifications report DND/error state,
Wayscriber reports its independently owned daemon state, and power is a static
button. The remaining per-launch state infrastructure serves CPU, memory,
storage and taskview. The Apps drawer retains its existing PRELIGHT/expanded
contract. Popup dismissal does not own or stop the selected application.

## Button color ownership

The launcher and Apps drawer have supported, authoritative lifetime owners.
`labwc-main-menu` and the Fuzzel picker publish an atomic, identity-checked
runtime marker; `labwc-waybar-exec menu-state` reads it and signals the launcher
module. The marker is removed in the owning picker `finally` path, so the
launcher remains in its active color until Fuzzel closes. The same contract is
used on both output bars. The packaged Waybar 0.15 Group module calls
`set_state_flags(PRELIGHT)` when a `click-to-reveal` drawer opens and clears it
on collapse. The Apps stylesheet therefore uses `#apps:hover #custom-apps` for
the drawer lifetime and does not depend on a timer or a status poll.

Tomat and Wayscriber cannot receive the same lifetime color from the supported
Waybar 0.15 native-menu contract. `AModule::handleUserEvent` maps the GTK menu
from the real input event, then explicitly unsets PRELIGHT; the package has no
popup-open CSS class, menu deactivation callback, or configuration hook that
can set a class on the originating module. A native labwc replay with the
signed Waybar 0.15.0 package measured the button at its normal color before
and while the Tomat popup was mapped. A click marker, fixed timeout, compositor
observer, fabricated input serial, persistent invisible anchor, or second GTK
owner would be race-prone and violate the native ownership/confinement
contract. The custom-module process does not provide a hidden workaround:
Waybar's signed 0.15.0 `util::command::open()` creates one close-on-exec
stdout pipe for the continuous reader, while click commands are separate
`forkExec()` children. There is no documented or stable FD5/FD6 passed to the
custom reader or to the menu callback, so treating either descriptor as a
popup lifecycle channel would be an ABI accident and would also break the
fixed descriptor-closing boundary in the installed helpers. A popup-active
button color would require a future upstream/package API that exposes menu
map/deactivate state, but that behavior is outside the supported package
contract used by this installer. The fresh-install contract therefore accepts
the package's normal-color state while those popups are mapped. Their native
menus, action maps, secondary clicks and daemon/timer state remain unchanged;
no Waybar package patch or rebuild is introduced.

Native mapping, focus, input, dismissal and application ownership require the
isolated GUI acceptance record; static validation and the reproduced standalone
failure do not establish those positive acceptance gates. Physical output,
hotplug, fractional scaling and suspend/resume acceptance remain separate.

The captured public-Xwayland startup messages are separate from menu ownership:
`Cannot find Xwayland binary "/usr/bin/Xwayland"` followed by
`failed to create xwayland server, continuing without`. The inspected signed
labwc 0.20.3 package manuals document Xwayland persistence, but no runtime disable
switch. Native labwc/Waybar surfaces and GTK menus were rendered without a public
Xwayland server in the private fixture. These messages do not justify installing
one or suppressing arbitrary compositor errors. The private Zoom/Discord
eligibility remains unchanged; their actual launch/shutdown acceptance is still
separate. A different packaged labwc candidate requires its own API check.
