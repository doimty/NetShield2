# NetShield2 ⛨

NetShield2 is a customizable firewall & live network monitor with actionable notifications for jailbroken iOS 15 16 17 18 devices. Unlike the original [NetShield](https://github.com/EolnMsuk/NetShield) and paid [NetFence](https://havoc.app/package/netfence), the new [**NetShield2**](https://github.com/EolnMsuk/NetShield2/) is a system wide content filter, which does not require app injection to function.

<img width="1280" height="1689" alt="ALL" src="https://github.com/user-attachments/assets/8762df84-bfc0-464a-a8fa-aaa5aa70cdd3" />

## Get started

1. Install the (rootless or roothide) deb from the releases section. No respring is required.
2. Open NetShield2 from the homescreen and switch on the main **Firewall** toggle, accept the iOS Notification and allow **Filter Network Content**, enter passcode and close the VPN settings. To confirm the filter has been added, re-open Settings > General > VPN & Device Management > Content Filter > NetShield2... Running.
3. Recommended: return to NetShield2, tap **Notification Settings** and switch Banner Style from Temporary to **Persistent**. If you use **Do Not Disturb**, allow NetShield2 in **Settings > Focus > Do Not Disturb > Apps**.
4. When a new app connects, touch and hold the NetShield2 notification banner and choose **Allow In & Out**, **Block Incoming**, or **Keep Blocking**. Tapping the notification body (instead of long pressing) will open NetShield2 where you can also assign rules to any pending requests.

Unanswered connections are blocked after 30 seconds. The latest 64 expired requests remain in **Waiting for your decision**, where you can decide later and retry the app. Older requests are removed as history fills. To force a process to request again, tap its rule and select **Use Default Rule** and you will be notified the next time it requests the internet.

## Options

- **Firewall:** on/off; turning it off keeps your rules.
- **Filter System Sockets:** when enabled, the firewall is capable of filtering network for all apps and processes. Disable only if an app is crashing on launch.
- **Allow all iOS system processes:** when enabled, processes starting with `com.apple` are allowed without prompts or permission notifications.
- **Unidentified:** Allowed by default, set to blocked to prevent unknown processes from accessing network (not recommended).
- **Default Rule:** Ask me by default, changing this to Allow or Block will prevent prompting / notifications and block or allow any new requests.
- **Notifications:** notification settings and instructions for banners and Do Not Disturb.
- **Advanced Settings:** manual rules, Reset Rules & History and Reset ALL Settings.
- **Global Rules:** IP/domain and remote port rules apply across all processes.
- **App Rules:** change saved decisions. Changes apply to new connection requests only.
- **Recent Activity:** the rolling 300-event record grouped by process, IP/domain, remote port, direction and allowed/blocked outcome.

## Hosts import + 简体中文 (2.2.8-1+hosts2 candidate)

This fork adds **Advanced Settings → Import Hosts Blocklist** (高级设置 → 导入 Hosts 屏蔽规则). Paste text, choose a local file, or enter a direct HTTPS Hosts URL and select Download & Preview. Review the preview, then tap Import. Download, preview and cancellation never save rules. This is not the upstream release linked above; use the Actions artifact for this branch and check its build status. Device filtering and large-list suitability are not certified by a successful build.

English and Simplified Chinese resources are bundled with the app and both filter extensions, following the system's language preference. Package revision `-1+hosts2` identifies this fork; Apple bundle short version remains 2.2.8 and the original filter engine version is unchanged.

HTTPS downloads use a temporary session without stored cookies, credentials or cache, require HTTP200, reject HTML and downgrade redirects, limit redirects to5, and enforce a2MiB decoded-data cap with30/60second timeouts. There are no subscriptions or automatic updates. URLs are not retained in policy or logged; network errors omit potentially sensitive URL queries.

```text
0.0.0.0 ads.example tracker.example
127.0.0.1 telemetry.example
:: ipv6-ad.example
```

- UTF-8 (optional BOM), comments, LF/CRLF/CR, multiple aliases per line and ASCII/punycode domains are accepted. Duplicate names are removed. The blocking addresses are `0.0.0.0`, `127.0.0.1`, `::` and `::1`, including equivalent IPv6 spellings.
- Real-IP redirects, localhost metadata and invalid names are skipped and counted. This is not a system Hosts editor, DNS redirection, Adblock parser, bare-domain list importer, remote subscription or auto-updater.
- Input is limited to **2 MiB / 4096 unique exact domain names**. All global rules combined (including manual IP/port rules) remain limited to **4096**; the whole stored policy also has a **2 MiB** cap. Overflow rejects the batch; nothing is silently truncated.
- Existing same-domain/www global rules are preserved, including allow and directional rules. The preview lists every proposed addition. At save, only those approved keys are reconsidered against the latest locked policy; concurrently added rules are preserved. New keys discard their orphan DNS cache, not other rules' caches.
- **Global blocks override app rules and the system-process allowance.** Existing explicit IP rules can still take precedence. The existing engine also matches www aliases and cached DNS addresses, which can block other sites sharing an IP. Stored exact keys do not imply exact Hosts filtering semantics.
- Domain rules trigger background DNS queries. IP-only connections rely on short-lived cached answers; large-list coverage can be delayed or incomplete. The existing four-worker, three-second resolver has an ideal first-pass lower bound of about **51 minutes for 4096 domain rules**, versus a maximum five-minute answer lifetime. This is static analysis, not device measurement. Saving rules does **not** mean every domain is actively covered or verified.
- Import does not enable Firewall, change Default Rule, request notification permissions, or restart filtering. Existing admitted connections remain unchanged. Rules are saved as ordinary global rules. There is no batch undo or JSON-restore feature; existing export is a record, not an automatic rollback mechanism.

For a blocklist-only setup without per-app prompts, the existing **Default Rule → Allow** option can be chosen separately. That also allows other previously unruled apps, so import never changes it automatically.

Local parser checks: `python3 scripts/test_hosts_parser.py`. Full merge/storage tests: `python3 scripts/test.py` on macOS with Xcode command-line tools. See [implementation plan](docs/hosts-import-plan.md).

## Coverage

Rules apply to new connections delivered by iOS, not every raw packet or OS-exempt path. Direction rules refer to who initiates a connection. No VPN server entry is needed: it uses a content filter, not a VPN tunnel. To see the 

## Support Developer

[Venmo](https://venmo.com/u/rustonrails) | Bitcoin: `31uHLpioo1TbxAmo9kM7rrKcLz3wvcoZaL`
