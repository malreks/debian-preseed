# Non-Perl source syntax review

Date: 2026-11-19.

This review complements the renderer repair and the separately recorded isolated
validation. Its final source portion inspected a 3,036-file checkout inventory,
including all 1,699 files under `d-i/debian/hooks/target/`. That portion did not
execute repository tests, installed helpers, Lua chunks, C fixtures, service
managers, package managers or hardware operations. The typed output checks below
then ran actual producers within the separately reviewed private image. The
source parsers reported no unexpected syntax failures. A subsequent service
operand review found and corrected the clipboard cleanup call described below.

## Accepted source checks

| Source class | Coverage | Result |
| --- | ---: | --- |
| Python files, templates and extensionless entrypoints | 588 | AST parsing passed; no repository imports |
| Shell files, templates and extensionless entrypoints | 341 | 334 Dash and seven Bash parser-only checks passed |
| Literal child-shell bodies and preseed command strings | 149, representing 148 unique programs | Parser-only checks passed after decoding their outer quoting and continuation lines |
| New service-inspector fixture's complete literal shell driver | 1 | Extracted as AST data and passed separately to Dash in parser-only mode |
| Literal Python command and heredoc bodies | 22 unique bodies | AST parsing passed |
| AWK program occurrences | 289, representing 148 unique programs | Compiler-only parsing passed, including all seven standalone AWK files |
| Lua and Nmap NSE sources | 10 | Text-only Lua compilation passed; no chunks invoked |
| C fixture sources | 2 | GCC syntax-only parsing passed with warnings treated as errors; no linking or execution |
| Polkit JavaScript rules and templates | 11 | Node parser-only checks passed; no JavaScript executed |
| JSON source/data files | 236 | Strict raw JSON parsing passed; duplicate keys and nonfinite constants rejected |
| YAML source/data files | 46 | Safe YAML parsing passed |
| XML, SVG and XML policy files | 24 | XML parsing passed without external-entity resolution |
| TOML source/data files | 10 | Raw TOML parsing passed |
| INI, desktop and NetworkManager files | 41 | Raw INI parsing passed |
| CSS sources and templates | 31 | Comment, string and delimiter structure passed; all 22 local imports resolve |
| Standard application desktop entries | 26 | `desktop-file-validate` passed |

Counts are source inventories and parser occurrences, not executed behavioral
cases. The final refresh retained every previously checked unique AWK and
embedded Python body. It expanded child-shell recognition to cover option forms
such as `sh -eu -c`, decoded the generated preseed continuations, and removed
duplicate inspection of a child program before and after its outer quote layer
was decoded. The preseed coverage includes eight current suite launch strings
and eight retained baseline reference strings.

The final source refresh also checked the latest `tools/post_change_check.py`,
the new service and clipboard fixtures, and the corrected clipboard owner with
AST parsing. It reparsed both generated receipt files and the current preseed
command strings after the final rebuild. Both suite receipts identify release
`f3438948657b580ffdd65ce04c15707e81be6f77566fb4bcee2ed69a41fa39c8` and source
fingerprint `a9b6a9fcf114ce7e5da728c99c78263faf3962c02f1362bf4ba3e63ec079aaa9`.
Lua, C, CSS, JavaScript and desktop-entry inputs retained their checked hashes.
The current entrypoint inventory contains no unclassified non-Perl shebang.
This evidence is tied to the final source snapshot; subsequent source changes
require the appropriate changed-file check.

## Service operand contract review

The final caller review covered all 83 files under `hooks/target/usr/` that
mention `systemctl`, `systemd-analyze` or `journalctl`, including 15 documentation
and help files. It traced dynamic unit names through generic wrappers,
configuration, persisted state, IPC input and their production callers.

Three commands now terminate option parsing before a general unit operand:

- The Perl security owner passes `--` before the selected service in
  `systemd-analyze security`.
- The shell system inspector passes `--` before the selected service in
  `systemctl status`.
- `usr/local/libexec/desktop/labwc-session-state.tmpl` passes `--` before each
  enumerated clipboard watcher unit in `systemctl stop`.

These unit grammars permit leading hyphens. Without the terminator, a name such
as `-Hcliphist.service` can be interpreted as an option, preventing the intended
cleanup. The correction retains the existing unit grammar and cleanup order.
Network-sharing and failed-unit diagnostics already terminate their dynamic
unit operands. Other inspected callers use closed constant sets, validated
fixed prefixes or generated UUID names. Dynamic journal unit values are
arguments of `--unit`/`-u` or are included in a single `--unit=VALUE` argument.
No additional concrete unit option-boundary defect was found in this scope.

The new guarded clipboard regression method passed inside the final private
image, whose manifest SHA-256 is
`d37e72c8861d14022c5b75b94cfad274bb3e0543801c10b2ddfcca60599bd0aa`.
It invokes the actual `clear_clipboard` and `ctl` functions with a strict
recording command sink. Its cases cover ordinary, instance and leading-hyphen
unit names, rejected malformed names, the cliphist executable present or absent,
and the exact sequence of watcher stops and clipboard clearing. The actual
method returned status zero without timeout or cancellation. No systemctl,
session, compositor or clipboard command was executed by this fixture. The
Perl and shell service-operand fixtures have their results in the combined
isolated validation record.

## Typed templates validated through their actual producers

Twelve structured templates cannot be passed directly to their final-format
parser because they deliberately contain unquoted typed placeholders or complete
block placeholders. Their raw parse diagnostics were classified as checks
requiring actual rendered output. They were subsequently resolved by invoking
their real producers and parsing the resulting bytes inside the private image.

All paths below are relative to `d-i/debian/hooks/target/`:

| Format | Templates |
| --- | --- |
| INI | `etc/NetworkManager/system-connections/wifi.nmconnection.tmpl` |
| JSON | `etc/app-veth.json.tmpl`; `etc/hardware-tuning/broker.json.tmpl`; `etc/hardware-tuning/intel.json.tmpl`; `etc/hardware-tuning/nvidia.json.tmpl` |
| JSON | `etc/labwc/3proxy/session.json.tmpl`; `etc/skel-desktop/.config/Code/User/settings.json.tmpl`; `etc/skel-desktop/.config/sleek/userData/colors.json.tmpl` |
| JSON | `etc/tailscale/netkit.json.tmpl`; `usr/local/share/desktop/software/software-release-policy.json.tmpl` |
| TOML | `etc/greetd/config.toml.tmpl`; `etc/skel-desktop/.config/wayscriber/config.toml.tmpl` |

The complete regenerated payload was prepared with its unchanged shared renderer
for both supported suites and both selected role families. The focused typed
helper then produced the following accepted results:

| Suite | Selected family/profile | Final outputs parsed | Distinct deferred templates covered | Not selected |
| --- | --- | ---: | ---: | ---: |
| Forky | desktop / btrfs-de-p15s | 13 | 12 | 0 |
| Trixie | desktop / btrfs-de-p15s | 13 | 12 | 0 |
| Forky | server / btrfs-srv-flex | 2 | 2 | 10 |
| Trixie | server / btrfs-srv-flex | 2 | 2 | 10 |

The extra desktop output is a second Wi-Fi configuration: WPA with IPv4, and SAE
with IPv4 plus IPv6. Both came from the unchanged `network-generate.pl` CLI,
using the actual `network-assets.list`, private data-only adapter directories,
documentation IP addresses, locally administered MAC addresses and explicitly
synthetic AP data. The final INI checks also verified the produced SSID escaping,
security mode and IPv6 method.

The application network, proxy, greeter, Tailscale and software release policy
checks used the actual shell map producers or exact publication argument lists.
A fixture boundary captured those source, destination, mode and typed values,
then passed them to the unchanged `render.pl --file scalar` implementation. The
greeter used its real TOML escaping. The three theme-only files—Code settings,
Sleek colors and Wayscriber configuration—were parsed directly after the complete
base render. No placeholder was filled with an arbitrary value to satisfy a
parser.

Hardware JSON came from the actual `hardware-tuning-config.py` offline installer
API, including its environment, vendor policy and broker validators. Its asset
list was resolved through the actual repository owner resolver. Enabled vendors
were supplied explicitly from the selected policy: Intel plus NVIDIA on the
desktop profile, and Intel on the server profile. The fixture supplied the
expected package D-Bus activation data and real rendered Waybar battery inputs.
It created configuration files and offline enablement links below its private
target root; it did not instantiate a tuning backend, discover a device or start
a service. NVIDIA is disabled in the selected server profile, and the other nine
unselected templates have desktop-only consumers.

Final JSON parsing rejected duplicate keys and nonfinite constants. TOML parsing
and strict INI parsing also passed, and none of these outputs retained installer
or theme markers. The isolated typed helper identity was
`a8cbe412d7ec9c6848c39aeed7fb8cdd33dc45bea10d2e2993ec36f34730f154`.
Per-output identities, actual producer captures, commands and private fixture
paths are retained in the four `typed-validation.json` reports. Image identity,
supervisor timeout, native tool versions and cleanup belong to the combined
isolated validation record.

These results establish producer, serialization and offline fixture publication
behavior. They do not establish boot, active networking, service activation or
physical hardware behavior.

## Candidate findings resolved without source changes

The slash-containing character classes in both ownership-journal AWK programs
and the CrowdSec overlay validator compile successfully under mawk. They are not
the Perl delimiter error reported in the installer log. The review therefore
preserves these AWK programs instead of applying a language-agnostic replacement.

One AWK expression in `scripts/desktop/detect.sh.tmpl` is constructed from decimal
values at runtime. Its selected value is checked by an anchored decimal grammar
before construction; all seven inspected callers supply fixed numeric lower and
upper bounds. Literal extraction does not constitute execution evidence for that
dynamic expression.

An AppArmor profile with a filename ending in `.sh` was initially recognized by
suffix as shell. Its contents identify it as AppArmor policy, so it is excluded
from shell counts and remains subject to the policy-validation boundary.

Two `.desktop` variants have different owning consumers from ordinary application
entries. `usr/share/wayland-sessions/labwc.desktop` contains `DesktopNames`, and
`usr/share/xfce4/helpers/foot.desktop.tmpl` declares `Type=X-XFCE-Helper`. The generic
desktop validator reports those extensions, while both files pass INI parsing.
Their metadata remains intact. The session and Xfce consumer behavior is not
claimed to have been exercised. The Code application entry also emits a category
hint, with a successful validator exit status.

## Parser execution boundaries

Shell checks use `dash -n` or `bash --noprofile --norc -n`, an explicit minimal
environment and disk-backed temporary directories. Quoted child programs are
decoded as data; the installer wrappers that carry them are not invoked.
Preseed continuation decoding follows the exact separator-preserving format
produced by `tools/build.py:preseed_command`; both the command string and its
literal child program are parsed without invoking the bootstrap.

AWK checks use only `mawk -W dump -f <private-source>`, with no input files and a
closed input stream. The [upstream mawk manual](https://invisible-island.net/mawk/manpage/mawk.html)
documents that mode as compilation followed by exit. A harmless compiler probe
containing `BEGIN { exit 37 }` returned zero from dump mode, and no program rule
was executed. The parser identifies itself as mawk 1.3.4, dated 20250131.

Lua checks use the installed Lua 5.4 parser library with `luaL_newstate` and
`luaL_loadbufferx` in text-only mode, then free the state. No Lua standard library
is opened, and no call, protected-call or file-execution function is used. The
[official Lua API](https://www.lua.org/manual/5.4/manual.html#lua_load) distinguishes
loading/compilation from running the resulting chunk.

Both C files were reviewed for preprocessing inputs before `gcc -fsyntax-only
-std=c11 -Wall -Wextra -Werror -x c -` consumed their bytes through standard input.
They include only ordinary public C headers. No executable or object file was
created, and their D-Bus peer implementations were never run.

JavaScript checks use the primary runtime's Node v24.22.3 executable with
`--check -` and source bytes on standard input. The complete minimal environment
contains no `NODE_OPTIONS`, preload or require setting. All eleven polkit rule
files and templates pass. The inventory contains no additional direct JavaScript
file or complete literal embedded `node -e`/HTML script candidate.

## Remaining boundaries

All four Zsh startup files—`.zshenv`, `.zprofile`, `.zshrc.tmpl` and `.zlogout`—pass
`zsh -f -n` with empty diagnostics inside the private image. Those accepted
results belong to the separate isolated validation record, rather than the host
source parser counts above.

The CSS checks establish lexical balance and local import wiring, not acceptance
of every property and value by GTK or a browser. The single Packer HCL template
was inspected as source but no native HCL parser was available. AppArmor policy,
nftables, systemd and other service-specific configurations require their proper
isolated consumers for native acceptance. BusyBox and ShellCheck remain separate
required checks; no substitute result is labeled as either of those tools.

Per-file hashes, exact parser results, raw-template classifications and the
excluded parser invocation are retained in the run's private validation evidence.
The complete release report should be used for the final combined source,
generation, isolated validation and remaining acceptance status.

The source inventory above precedes the final content refresh of the delivery reports and evidence. The delivery JSON is serialized and parsed again after that refresh; final archive membership is verified by the packaging record.
