# Hosts import local candidate plan

Base: `EolnMsuk/NetShield2` `5bf2eb3259dd937cc87f756dcaca49ba5e667a4c` (2.2.8).
Branch: `feat/hosts-import`. Local edits only; no commit, push, build dispatch, install or system changes authorized.
No AGENTS.md found in repo or checked ancestors.

## Scope and assumptions
- Add an Advanced Settings entry offering paste or local document selection, then a read-only preview and explicit Import.
- Convert ONLY Hosts blocking mappings (0.0.0.0, 127.0.0.1, ::, ::1) into existing global domain block rules. Valid other IP mappings are skipped as redirects. Ignore localhost metadata. ASCII/punycode domains only; UTF-8 comments supported.
- Preserve existing filter policy semantics, permissions, app rules, DNS resolver, package identity and 4096 global rule / 2 MiB document caps. Input <=2 MiB. Large-list engine redesign and remote subscriptions excluded.
- Existing engine matches domain/www aliases and may match cached IPs (shared-IP overblocking possible). Preview must disclose this plus global priority and only-new-flow effects. This is not system Hosts editing or exact DNS redirection.
- No default-rule changes, notification permission changes or filter restart. No new network fetch.

## Success criteria
1. Pure C production parser compiles/tests on local Linux and macOS runner; tests include malformed encoding, limits, comments, aliases and redirects.
2. Dedup and capacity checks before writing. Preview and Cancel never write. No overwrite of existing exact/www rules. Overflow rejects entire batch.
3. Commit uses NSUpdatePolicy under existing lock and latest policy, only considers keys shown as additions at preview. Concurrent newly created rules preserved; no newly eligible/unpreviewed keys imported.
4. All writes use original atomic validated policy storage, including byte-size checking. Bounded file reading and parsing off main thread.
5. Native Objective-C regression cases supplied and wired into existing macOS test runner; do not claim execution unless Apple Foundation/Xcode actually available.
6. Minimal integration diff; no unrelated engine or workflow changes beyond including tests.

## Independent failure signals and verification
- Reject import if file/encoding/rule capacity/storage is invalid, if no blocks can be imported, or if lock cannot be acquired; preserve disk state.
- Test real C parser, native merge/store tests, source/package validation, uninstall fixtures, format checks and git diff --check.
- Read-only independent review of policy, DNS and storage hazards.
- Apple SDK compilation and device UI/file-provider/actual filtering must be separately validated; local C tests are not iOS acceptance.
