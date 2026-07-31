---
title: "WordPress Security-Invariant Catalog"
type: reference
status: active
created: '2026-07-21'
updated: '2026-07-21'
tags:
  - wordpress
  - security-audit
  - invariants
  - trust-boundaries
related:
  - '*index*'
  - '[audit-playbook](../method/audit-playbook.md)'
  - '[wordpress-attack-surfaces](../method/wordpress-attack-surfaces.md)'
---

# Security-invariant catalog

Hunt **broken assumptions**, not dangerous functions. Each invariant: what it asserts · where it breaks · how to test · the negative control that would disprove the hypothesis. The article's chain broke five of these at once (marked ⚑).

## Representation & alignment
| # | Invariant | Where it breaks | Test / negative control |
|---|---|---|---|
| 1 ⚑ | Every request maps to the validation created for **that same** request | Batched/looped handlers with `continue`/early-return that update one parallel array but not its partner | Send a batch with a malformed early item; assert handler[i] executed used validation[i]. Control: well-formed batch stays aligned. |
| 2 ⚑ | The validated object **is** the object later executed | Two-phase validate-then-execute; index reuse | Instrument that executed handler == validated handler. Control: single-phase route. |
| 3 | Parallel arrays stay aligned through success, error, early-continue | Any `foreach` appending to >1 array with conditional `continue` | Fuzz error positions; assert lengths + index correspondence. |
| 4 ⚑ | A scalar cannot reach code that assumes a validated array (and vice-versa) | `is_array()` guards that silently pass scalars raw (`author__not_in`) | Pass scalar where array expected; assert rejected/escaped. Control: array input is `absint`-mapped. |
| 5 | Schema/type validated == type consumed | Mass assignment, JSON body coercion | Type-confusion fixtures per REST arg. |

## Canonicalization & authorization
| # | Invariant | Where it breaks | Test / control |
|---|---|---|---|
| 6 | Canonicalization happens **before** security decisions | Path/URL/encoding normalized after the check | Encoded-input control vs canonical. |
| 7 | Authorization checks the **same** route/resource/params later executed | Permission callback borrowed across desync/representation | Assert permission-callback subject == executed subject. |
| 8 | A nonce is **not** authorization | `wp_verify_nonce` used where `current_user_can` is required | Valid nonce + insufficient cap must be blocked. |
| 9 | Escaping is at output, not a substitute for validation | `esc_*` used to "sanitize" logic inputs | Assert logic path validates independent of escaping. |
| 10 | Sanitized values can't be replaced by unsanitized aliases | Alias var reintroduces raw input downstream | Taint-trace both names. |

## Identity, state & lifecycle
| # | Invariant | Where it breaks | Test / control |
|---|---|---|---|
| 11 ⚑ | Temporary user changes cannot outlive their operation | `wp_set_current_user` in changesets/cron without guaranteed restore | Assert `get_current_user_id()` restored on success **and** exception. Control: normal apply restores. |
| 12 | Blog/locale/user/global state restores on success **and** failure | `switch_to_blog`, `switch_to_locale`, `$GLOBALS` without `finally` | Force exception mid-op; assert restoration. |
| 13 | IDs refer to real objects of expected type/owner/blog/status | Fabricated cache rows; ID reuse | Assert `get_post()->post_type/status` match DB. |
| 14 ⚑ | A cached object == its DB row in entity **and** security meaning | Per-request object cache poisoned via SQLi/UNION; reconciliation prefers in-memory | Compare cache vs DB fields at write; assert no privileged field diverges. Control: unpoisoned request. |
| 15 ⚑ | Cache reconciliation can't turn attacker transient state into trusted persistent state | `wp_update_post` writing in-memory-preferred fields (`oembed_cache`→`post`) | Assert `post_type`/`post_status` can't be elevated via reconciliation. |
| 16 | Activation/update/migration/uninstall enforce valid state transitions | Invalid `status_type` pairs; skipped migrations | Fuzz status/type; assert rejects unknown transitions. |
| 17 | Lifecycle can't fabricate rows from a SELECT-only primitive | Embed/oembed cache writes triggered by reads | Assert read paths don't INSERT posts. |

## Dispatch, recursion & background
| # | Invariant | Where it breaks | Test / control |
|---|---|---|---|
| 18 ⚑ | Dynamic hook names can't reach unrelated privileged actions | `do_action("{$a}_{$b}", …)` with attacker-controlled `$a`/`$b` (→ `parse_request`) | Enumerate reachable action names from controlled fields; assert allow-list. |
| 19 | Recursion/re-entry can't bypass an outer restriction | Recursive REST/batch re-entry | Assert inner call inherits outer authz. Control: single-level call blocked. |
| 20 | Background/async paths enforce the same controls as direct requests | Cron/Action Scheduler/queue skipping caps | Fire the job directly; assert cap check. |
| 21 | Error paths update every related structure consistently | Partial updates on exception | Inject failure; assert no half-written state. |

## Build, dependency & platform
| # | Invariant | Where it breaks | Test / control |
|---|---|---|---|
| 22 | The generated build omits no check present in source | Minifier/transpiler drops guard; server render differs from editor | Diff source vs `build/`; assert guards present. |
| 23 | The distributed ZIP contains no code absent from reviewed source | Extra files in package | Diff release ZIP vs tag. |
| 24 | Third-party libs behave as assumed at the **pinned** version | Upstream default/security change | Read pinned dep source; version-diff test. |
| 25 | Multisite can't cross blog/network boundaries unintentionally | Missing `is_super_admin`/blog scoping | Cross-blog access control. |
| 26 | Perf optimizations don't alter security semantics; security ≠ UI-only | Cache/short-circuit bypassing checks; JS-only gate | Assert server-side enforcement with UI removed. |

## Common WP bug classes (added after adversarial review — the catalog must not over-fit the one article chain)
| # | Invariant | Where it breaks | Test / control |
|---|---|---|---|
| 27 | Serialized data crossing a trust boundary is never unserialized into **objects** | `unserialize`/`maybe_unserialize` on attacker meta/option; POP-gadget chains; `phar://` via file funcs | Object-injection fixture; assert guarded decode (`allowed_classes=false`) / no gadget autoload. |
| 28 | Server-side fetches use **safe** HTTP (SSRF) | `wp_remote_get` instead of `wp_safe_remote_get`; oEmbed/provider fetch; redirect/DNS-rebinding to internal | Internal-URL + redirect-to-internal control; assert allowlist / safe wrapper / no follow to private IPs. |
| 29 | Output is escaped for its **exact context** (XSS) | attribute vs JS vs URL vs HTML context confusion; stored + reflected | Context-specific sentinel per sink; assert `esc_attr`/`esc_js`/`esc_url`/`wp_kses` correctness. |
| 30 | Every state change requires **intent + capability** (CSRF) | action with no nonce; nonce present but no `current_user_can` | No-nonce/cross-origin request must be blocked; valid nonce + insufficient cap must be blocked. |
| 31 | Charset / collation / i18n can't bypass query safety | multibyte `$wpdb->prepare` edge, missing `esc_like`, utf8mb4 truncation, locale-dependent compares | Multibyte injection fixture; **connection-charset + collation parity in the test matrix**. |
| 32 | Check-then-act is **atomic** (race / TOCTOU) | option check-then-set, nonce reuse, double-submit, `add_option` race | **Concurrent-request** harness; a single-request repro *cannot* disprove — flag as such. |
| 33 | Autoloaded options/meta can't amplify or inject | unbounded autoload growth; serialized autoload value | Assert bounded size + guarded decode. |
| 34 | Interactivity API / SSR state can't reflect untrusted input as instructions or markup | `wp_interactivity_state` reflecting input; directive injection | SSR-state sentinel; assert escaped/typed. |
| 35 | Crypto/secret material is unpredictable and single-use | weak reset-token/nonce entropy, predictable IDs, secret reuse | Predictability/reuse test; assert CSPRNG + expiry. |

## Guard against over-fitting (the biggest residual risk)
This catalog was seeded from one chain, so it will happily "cover" the shapes it already knows. Two guards:
- **Unknown-shape family is mandatory.** [orchestration](../method/orchestration.md) carries an explicit *no-invariant-matches* research family; a surface that fits no invariant here is **under-covered, not clean**.
- **Measure coverage against an external corpus** (CWE list, WPScan/Patchstack advisory classes, prior-audit corpus), never against this table. A finding class absent from both the target *and* this catalog is exactly where the next differently-shaped bug hides.

## How to use
For each invariant on a target, record in the registry: **established → transformed → consumed → error-path risk → test → negative control**. A hypothesis without a passing negative control is not a finding — it stays a hypothesis ([validation-and-proof](../method/validation-and-proof.md)).
