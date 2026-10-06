# URL import and Simplified Chinese localization plan

Continues local `feat/hosts-import` on upstream `5bf2eb3`; preserves previous uncommitted Hosts feature. Previous candidate snapshot and SHA are in `workspace/netshield2-review/manifest.json`. No commit/push/CI/install authorization.

## Scope
- Three explicit inputs: paste, local file, or user-entered HTTPS URL. All feed the same bounded Hosts parser and read-only preview. Download never writes a rule or changes filter configuration.
- HTTPS only, no credentials in URL; no insecure transport exceptions. Bounded ephemeral streaming session, HTTP200/raw text, maximum2MiB, request/resource timeout30/60s, bounded and validated redirects, cancel/late-callback protection. No URL subscription, periodic update, clipboard auto-read, or hidden credential persistence.
- Retain file security-scoped access and bounded read; no change to Hosts syntax,4096 rule cap, default rules, DNS resolver or global precedence.
- Add English fallback and Simplified Chinese localization for App/dashboard/import, notices/actions, and user-facing shared/provider messages. Follow system bundle locale; stable identifiers, domains, policy keys/actions, export schemas remain unchanged. Put common locale resources in each application/extension bundle via explicit Theos resource list.
- Research hostname evidence and scalable blocklist options separately. Do not equate faster string matching with complete IP-only filtering or silently enlarge capacity.

## Success and failure signals
- Invalid URL/TLS/error status/HTML/oversize/timeout/cancel must not import anything; only success bytes go to existing preview. Repeated taps and callbacks cannot import twice or resurrect dismissed UI.
- Production tests for URL validation, delegate bounded state and fake network responses; actual macOS execution only if Apple Foundation exists. Do not label Linux source checks as runtime tests.
- Locale key parity, source extraction, duplicate detection and printf type/order consistency; negative fixtures must reject invalid translations. English native tests remain unaffected without bundled resources.
- Check staged resource paths for all3bundles with fixtures; validate existing metadata/uninstall hooks, C parser, format and git diff.
- Final inspect changes for only URL/import/localization scope; report Apple compile/device/file-provider/network/localization acceptance gaps and immutable artifacts.
