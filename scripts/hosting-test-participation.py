#!/usr/bin/env python3
"""Check a host's public participation in WordPress's distributed hosting tests.

Hosts can run WordPress core's PHPUnit suite on their own infrastructure
(WordPress/phpunit-test-runner) and submit results to the public dashboard at
https://make.wordpress.org/hosting/test-results/ (WordPress/phpunit-test-reporter).
This collector reads that public evidence and classifies it against a declared
fleet-variant inventory, honestly: participation, freshness, target-build
coverage, fleet-variant coverage, and test outcome stay separate fields, and a
weaker evidence class is never silently promoted to a stronger one.

Read-only, by construction. It speaks only to the core REST API the live
deployment already exposes publicly (wp/v2 on make.wordpress.org/hosting,
verified live 2026-08-27). It never touches the authenticated submission
endpoint (wp-unit-test-api/v1/results, which is POST-only), never sends
credentials, and never parses HTML.

  python3 scripts/hosting-test-participation.py \\
      --host "Example Hosting" --variants variants.csv \\
      --revision 63366 --target "trunk r63366" \\
      --evidence "$WP_AUDIT_ROOT/participation" --format markdown

  python3 scripts/hosting-test-participation.py --find "example"   # discovery
  python3 scripts/hosting-test-participation.py --control          # self-test, offline

Inputs:
  --host NAME          Provider display name, as the operator states it.
  --variants FILE      Fleet-variant inventory CSV (see header below). A host
                       employee supplies the canonical list; a hosted-server
                       auditor lists only the tier they are actually on.
  --variant SPEC       Inline single variant, "id:description[:reporter_login]"
                       — the hosted-server-auditor shortcut for one tier.
  --reporter LOGIN     Confirmed reporter login(s), repeatable, for host-level
                       evidence when a variant row has no mapping.
  --revision N         Target build as a develop.svn revision number. Without
                       it, target evidence reads INCONCLUSIVE(target-mapping).
  --target LABEL       The target build's human name (e.g. "7.2-RC1"), recorded
                       verbatim; it does NOT substitute for --revision.
  --window N           Freshness window in revisions (default 25 — the live
                       dashboard's own "Registered, but no reports in >25
                       Revisions" split, verified 2026-08-27).
  --format X           json (default) or markdown.
  --evidence DIR       Preserve raw responses + manifest + outputs there.
  --find NAME          Discovery only: list candidate reporter accounts whose
                       public name matches. Candidates are AMBIGUOUS_MATCH until
                       the operator confirms them — never auto-attributed.

Variants CSV header:
  variant_id,description,reporter_login,mapping_confirmed,notes
  mapping_confirmed is yes/no: "yes" means the host (or the operator, from the
  host's own statement) confirmed that THIS reporter account tests THIS variant.
  Anything else keeps the variant at AMBIGUOUS_MATCH — a name that looks right
  is not a mapping.

Participation classifications (one per variant, plus a host rollup):
  VERIFIED_TARGET_VARIANT    confirmed mapping + a result for the exact target revision
  VERIFIED_CURRENT_VARIANT   confirmed mapping + results inside the window, none for target
  VERIFIED_CURRENT_HOST_ONLY host is currently reporting; variant not attributable
  PARTIAL_COVERAGE           (rollup) some declared variants verified, others not
  STALE_REGISTRATION         reporter registered; last report outside the window
  NO_PUBLIC_MATCH            no defensible public match as of retrieval time
  AMBIGUOUS_MATCH            unconfirmed candidates, duplicates, or conflicts
  BLOCKED                    source, network, schema, or required input unavailable
  NOT_APPLICABLE             not third-party hosted, or the check does not apply

Test outcomes (separate from participation, never merged):
  PASSED / FAILED / ERRORED  the reporter's published result status terms
  NO_RESULT                  no submission found in the checked scope
  INCONCLUSIVE               a submission exists but its status is unreadable

Evidence hierarchy (class 1 strongest; recorded per observation, never promoted):
  1 exact reporter + confirmed variant mapping + exact target revision
  2 exact reporter + confirmed variant mapping, inside the window
  3 exact reporter, current, but no defensible variant mapping
  4 stale registered reporter
  5 alias / fuzzy-name / unconfirmed candidate — operator confirmation required
  6 no public match found

Evidence ceiling — what a green row can and cannot prove: a public result proves
that account ran core's PHPUnit suite on some infrastructure at that revision
with that PHP and database. It does not prove plugin compatibility, upgrade
safety, browser behavior, production fleet coverage, or that the tested
infrastructure is the tier a given customer is on. The live deployment publishes
no environment label (verified 2026-08-27: result titles carry login, revision,
PHP, and database only), so results cannot be attributed to a hosting product
from public data alone — only a per-variant reporter account can do that.
NO_PUBLIC_MATCH is a statement about public evidence at retrieval time, not
proof that a host does not test privately or under another account.

Exit codes:
  0  completed; every lane produced a defensible classification
  1  hard error (bad usage, unreadable variants file, invalid inputs)
  2  nothing to check (no variants and no reporters given)
  3  completed, but at least one lane is BLOCKED — fail closed, do not
     substitute a guess; CI and skills branch on this

Test seam: WP_AUDIT_PTR_FIXTURE=<dir> answers each request from
<dir>/<request-key>.json instead of the network, so the controls run offline.
A fixture file of the form {"__error__": "..."} simulates a transport failure;
a missing fixture file is a control bug and fails loudly. The controls cover
the twelve scenario classes listed in run_control() below.
"""

import csv
import hashlib
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

COLLECTOR_VERSION = "1.0.0"
ROOT = Path(__file__).resolve().parent.parent
BASE_URL = os.environ.get(
    "WP_AUDIT_PTR_BASE", "https://make.wordpress.org/hosting/wp-json/wp/v2"
)
DASHBOARD_URL = "https://make.wordpress.org/hosting/test-results/"
GETTING_STARTED_URL = "https://make.wordpress.org/hosting/test-results-getting-started/"
REQUEST_MESSAGES = "templates/participation-request-messages.md"
USER_AGENT = (
    "wp-release-audit-method/hosting-test-participation "
    "(+https://github.com/courtneyr-dev/wp-release-audit-method; read-only)"
)
TIMEOUT = 30
DEFAULT_WINDOW = 25  # the live dashboard's active/inactive split, 2026-08-27
PER_PAGE = 100
MAX_RESULT_PAGES = 5  # 500 results per reporter; deeper history is reported as truncated

VARIANT_FIELDS = ["variant_id", "description", "reporter_login", "mapping_confirmed", "notes"]

PARTICIPATION = (
    "VERIFIED_TARGET_VARIANT", "VERIFIED_CURRENT_VARIANT", "VERIFIED_CURRENT_HOST_ONLY",
    "PARTIAL_COVERAGE", "STALE_REGISTRATION", "NO_PUBLIC_MATCH", "AMBIGUOUS_MATCH",
    "BLOCKED", "NOT_APPLICABLE",
)
OUTCOMES = ("PASSED", "FAILED", "ERRORED", "NO_RESULT", "INCONCLUSIVE")
OUTCOME_BY_SLUG = {"passed": "PASSED", "failed": "FAILED", "errored": "ERRORED"}


class CollectorError(Exception):
    """Hard error: bad usage or unreadable local input."""


class SourceBlocked(Exception):
    """The public source, network, or schema was unavailable — fail closed."""


# ── transport ────────────────────────────────────────────────────────────────
def request_key(path, params):
    """Deterministic fixture filename for one logical request."""
    q = urllib.parse.urlencode(sorted(params.items()))
    slug = re.sub(r"[^a-z0-9]+", "-", f"{path}-{q}".lower()).strip("-")
    return slug[:120]


def fetch(path, params, evidence=None):
    """GET one wp/v2 collection page. Returns (parsed, headers_dict).

    Fixture mode answers from WP_AUDIT_PTR_FIXTURE/<request-key>.json where the
    JSON is {"body": <payload>, "headers": {...}} — the same shape live capture
    writes, so a captured live response can be replayed as a fixture verbatim.
    """
    fixture_dir = os.environ.get("WP_AUDIT_PTR_FIXTURE")
    key = request_key(path, params)
    if fixture_dir:
        f = Path(fixture_dir) / f"{key}.json"
        if not f.exists():
            raise SourceBlocked(f"fixture missing for request '{key}' in {fixture_dir}")
        data = json.loads(f.read_text(encoding="utf-8"))
        if isinstance(data, dict) and "__error__" in data:
            raise SourceBlocked(f"simulated transport failure: {data['__error__']}")
        return data.get("body"), {k.lower(): v for k, v in data.get("headers", {}).items()}

    url = f"{BASE_URL}/{path}?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            raw = resp.read()
            headers = {k.lower(): v for k, v in resp.headers.items()}
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, OSError) as exc:
        raise SourceBlocked(f"fetch failed for {url}: {exc}") from exc
    try:
        body = json.loads(raw.decode("utf-8"))
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        raise SourceBlocked(f"non-JSON response from {url}: {exc}") from exc
    if evidence is not None:
        evidence.record(url, raw, key, headers)
    return body, headers


def require_keys(items, keys, what):
    """Fail closed the day the upstream schema stops carrying what we read."""
    for item in items:
        missing = [k for k in keys if k not in item]
        if missing:
            raise SourceBlocked(
                f"schema drift in {what}: expected keys {missing} are absent — "
                "refusing to guess; update the collector against the live schema"
            )


# ── evidence store ───────────────────────────────────────────────────────────
class EvidenceStore:
    def __init__(self, directory):
        self.dir = Path(directory) if directory else None
        self.manifest = []
        if self.dir:
            self.dir.mkdir(parents=True, exist_ok=True)

    def record(self, url, raw, key, headers):
        if not self.dir:
            return
        f = self.dir / f"{key}.json"
        wrapped = json.dumps(
            {"body": json.loads(raw.decode("utf-8")), "headers": dict(headers)},
            indent=1,
        ).encode("utf-8")
        f.write_bytes(wrapped)
        self.manifest.append({
            "url": url,
            "file": f.name,
            "sha256": hashlib.sha256(raw).hexdigest(),
            "retrieved_at": now_iso(),
        })

    def finish(self, output, markdown, replay):
        if not self.dir:
            return
        (self.dir / "manifest.json").write_text(json.dumps({
            "collector_version": COLLECTOR_VERSION,
            "base_url": BASE_URL,
            "replay": replay,
            "responses": self.manifest,
        }, indent=1), encoding="utf-8")
        (self.dir / "participation.json").write_text(
            json.dumps(output, indent=1), encoding="utf-8")
        (self.dir / "participation.md").write_text(markdown, encoding="utf-8")


def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


# ── reads against the reporter's public data model ───────────────────────────
def strip_tags(text):
    return re.sub(r"<[^>]+>", "", text or "").strip()


def revision_number(slug):
    m = re.fullmatch(r"r(\d+)", slug or "")
    return int(m.group(1)) if m else None


def get_revisions(evidence, window):
    """Revision posts (parent=0), newest first, enough to cover the window.

    Freshness mirrors the reporter's own active/inactive split: a reporter is
    active iff it has a report attached to one of the N most-recent revision
    posts (upstream N=25, src/class-display.php:227 at fa1fa7b0). The window is
    a set of recent revisions, not a numeric distance — revisions only exist as
    posts when someone submitted for them.
    """
    pages = max(1, -(-(window + 2) // PER_PAGE))
    revisions = []
    for page in range(1, pages + 1):
        body, _ = fetch("result", {"parent": 0, "per_page": PER_PAGE, "page": page},
                        evidence)
        if not isinstance(body, list):
            raise SourceBlocked("schema drift: revision listing is not a list")
        require_keys(body, ["id", "slug", "title", "link"], "revision posts")
        for post in body:
            n = revision_number(post["slug"])
            if n is None:
                # Top-level result posts are revision containers named rNNNNN.
                # Anything else at the top level means the model changed.
                raise SourceBlocked(
                    f"schema drift: top-level result post '{post['slug']}' is not rN")
            revisions.append({
                "post_id": post["id"], "slug": post["slug"], "number": n,
                "title": strip_tags(post["title"].get("rendered", "")),
                "link": post["link"],
            })
        if len(body) < PER_PAGE:
            break
    if not revisions:
        raise SourceBlocked("no revision posts returned — nothing to measure against")
    revisions.sort(key=lambda r: r["number"], reverse=True)
    return revisions


def get_term_map(evidence, taxonomy):
    terms, page = {}, 1
    while True:
        body, headers = fetch(taxonomy, {"per_page": PER_PAGE, "page": page}, evidence)
        if not isinstance(body, list):
            raise SourceBlocked(f"schema drift: {taxonomy} listing is not a list")
        require_keys(body, ["id", "slug"], f"{taxonomy} terms")
        for t in body:
            terms[t["id"]] = {"slug": t["slug"], "name": strip_tags(t.get("name", t["slug"]))}
        total = int(headers.get("x-wp-totalpages", "1") or "1")
        if page >= total or len(body) < PER_PAGE:
            break
        page += 1
    return terms


def get_user_by_login(evidence, login):
    body, _ = fetch("users", {"slug": login}, evidence)
    if not isinstance(body, list):
        raise SourceBlocked("schema drift: users listing is not a list")
    if not body:
        return None
    require_keys(body, ["id", "slug", "name", "link"], "users")
    u = body[0]
    return {"id": u["id"], "login": u["slug"], "display_name": u["name"],
            "profile_url": u["link"]}


def find_candidates(evidence, needle):
    """Discovery only. Every hit is a CANDIDATE the operator must confirm."""
    body, _ = fetch("users", {"search": needle, "per_page": 20}, evidence)
    if not isinstance(body, list):
        raise SourceBlocked("schema drift: users search is not a list")
    return [{"id": u.get("id"), "login": u.get("slug"), "display_name": u.get("name"),
             "profile_url": u.get("link")} for u in body]


def get_results_for_author(evidence, author_id):
    """Result posts by one reporter, newest first. Returns (rows, truncated)."""
    rows = []
    for page in range(1, MAX_RESULT_PAGES + 1):
        body, headers = fetch(
            "result", {"author": author_id, "per_page": PER_PAGE, "page": page},
            evidence)
        if not isinstance(body, list):
            raise SourceBlocked("schema drift: results listing is not a list")
        require_keys(body, ["id", "parent", "title", "link", "date"], "result posts")
        rows.extend(body)
        total = int(headers.get("x-wp-totalpages", "1") or "1")
        if page >= total or len(body) < PER_PAGE:
            return rows, False
    return rows, True


# ── the model ────────────────────────────────────────────────────────────────
def read_variants_file(path):
    p = Path(path)
    if not p.exists():
        raise CollectorError(f"variants file not found: {path}")
    with p.open(encoding="utf-8", newline="") as fh:
        rows = list(csv.DictReader(fh))
    if not rows:
        raise CollectorError(f"variants file has no rows: {path}")
    missing = [f for f in VARIANT_FIELDS if f not in rows[0]]
    if missing:
        raise CollectorError(
            f"variants file is missing columns {missing}; header must be "
            + ",".join(VARIANT_FIELDS))
    return rows


def parse_inline_variant(spec):
    parts = spec.split(":")
    if len(parts) < 2:
        raise CollectorError(
            "--variant needs 'id:description[:reporter_login]', got " + repr(spec))
    return {
        "variant_id": parts[0].strip(), "description": parts[1].strip(),
        "reporter_login": parts[2].strip() if len(parts) > 2 else "",
        "mapping_confirmed": "yes" if len(parts) > 2 else "",
        "notes": "inline --variant",
    }


def observation(**kw):
    """One retained observation row, every field always present."""
    base = {
        "provider": "", "reporter_display_name": "", "reporter_url": "",
        "reporter_login": "", "alias_status": "", "fleet_variant": "",
        "environment_label": "",  # the live deployment publishes none (2026-08-27)
        "target_build": "", "reporter_revision": "", "last_observed_revision": "",
        "retrieved_at": "", "php_version": "", "db_version": "",
        "test_outcome": "", "participation": "", "evidence_class": "",
        "source_url": "", "limitation": "", "next_action": "",
    }
    unknown = set(kw) - set(base)
    if unknown:
        raise CollectorError(f"internal: unknown observation fields {unknown}")
    base.update(kw)
    return base


def parse_result_row(post, terms_php, terms_db, terms_status, rev_by_post_id):
    parent = rev_by_post_id.get(post["parent"])
    php = [terms_php[t]["name"] for t in post.get("php-version", []) if t in terms_php]
    db = [terms_db[t]["name"] for t in post.get("db-version", []) if t in terms_db]
    status_terms = [terms_status[t]["slug"] for t in post.get("report-result", [])
                    if t in terms_status]
    outcome = OUTCOME_BY_SLUG.get(status_terms[0]) if status_terms else "INCONCLUSIVE"
    return {
        "revision": parent["slug"] if parent else None,
        "revision_number": parent["number"] if parent else None,
        "parent_post": post["parent"],
        "php": "; ".join(php), "db": "; ".join(db),
        "outcome": outcome, "link": post["link"], "date": post["date"],
    }


def classify_variant(variant, reporter, rows, truncated, window_numbers,
                     target_revision, shared_login):
    """Pure classification for one declared variant. Returns (participation,
    evidence_class, limitation, next_action, matched_rows).

    mapping_confirmed values: "yes" = the host confirmed this account tests
    THIS variant; "host" = the account is confirmed as the host's, with no
    variant-level claim (the --reporter path); anything else = unconfirmed.
    """
    login = (variant.get("reporter_login") or "").strip()
    mapping = (variant.get("mapping_confirmed") or "").strip().lower()

    if not login:
        return ("NO_PUBLIC_MATCH", 6,
                "no reporter account is declared for this variant; public data "
                "cannot volunteer one",
                f"ask the host which reporter account (if any) tests this tier; "
                f"request participation with {REQUEST_MESSAGES}", [])
    if reporter is None:
        return ("NO_PUBLIC_MATCH", 6,
                f"login '{login}' has no public reporter account at retrieval time "
                "(absence of public evidence, not proof of nonparticipation)",
                "confirm the login with the host, or run --find for candidates", [])
    if mapping not in ("yes", "host"):
        return ("AMBIGUOUS_MATCH", 5,
                f"reporter '{login}' exists but the host has not confirmed it tests "
                "this variant; a plausible name is not a mapping",
                "get the mapping confirmed by the host, then set "
                "mapping_confirmed=yes and rerun", [])

    on_target = ([r for r in rows if r["revision_number"] == target_revision]
                 if target_revision is not None else [])
    in_window = [r for r in rows if r["revision_number"] in window_numbers]

    if mapping == "host" or shared_login:
        # Host-level evidence only. One account mapped to several variants (or
        # to none) cannot attribute results to a single tier — the public data
        # carries no environment label, so refusing this promotion is the
        # coverage-generalization guard doing its job.
        why = ("reporter account is confirmed as the host's, with no "
               "variant-level mapping" if mapping == "host" else
               f"reporter '{login}' is mapped to multiple declared variants")
        if on_target or in_window:
            return ("VERIFIED_CURRENT_HOST_ONLY", 3,
                    why + "; public results carry no environment label, so they "
                    "cannot be attributed to one variant",
                    "ask the host to run per-variant reporter accounts (see "
                    f"{GETTING_STARTED_URL})", on_target or in_window[:1])
        if rows:
            return ("STALE_REGISTRATION", 4,
                    why + "; last public report is outside the freshness window",
                    f"ask the host to resume runs; template: {REQUEST_MESSAGES}",
                    rows[:1])
        return ("STALE_REGISTRATION", 4,
                why + "; no results readable in the fetched history",
                f"ask the host to resume runs; template: {REQUEST_MESSAGES}", [])

    if on_target:
        lim = "" if in_window else \
            "exact target evidence exists, but the reporter is otherwise " \
            "outside the freshness window"
        return ("VERIFIED_TARGET_VARIANT", 1, lim, "record outcomes below",
                on_target)
    if in_window:
        lim = ("no result for the exact target revision"
               if target_revision is not None else
               "target build not mapped to a revision — target evidence is "
               "INCONCLUSIVE(target-mapping)")
        return ("VERIFIED_CURRENT_VARIANT", 2, lim,
                "acceptable as current evidence; for exact-target evidence, wait "
                "for or request a run at the target revision", in_window[:1])
    if rows:
        lim = "last public report is outside the freshness window"
        if truncated:
            lim += f" (history truncated at {MAX_RESULT_PAGES * PER_PAGE} results)"
        return ("STALE_REGISTRATION", 4, lim,
                f"ask the host to resume runs; request template: {REQUEST_MESSAGES}",
                rows[:1])
    return ("STALE_REGISTRATION", 4,
            "reporter account exists but no results were readable in the "
            "fetched history",
            f"ask the host to resume runs; request template: {REQUEST_MESSAGES}", [])


def rollup(variant_classes):
    verified = {"VERIFIED_TARGET_VARIANT", "VERIFIED_CURRENT_VARIANT"}
    got = set(variant_classes)
    if not got:
        return "NOT_APPLICABLE"
    if "BLOCKED" in got:
        return "BLOCKED"
    if got & verified and got - verified:
        return "PARTIAL_COVERAGE"
    if got <= verified:
        return "VERIFIED_TARGET_VARIANT" if got == {"VERIFIED_TARGET_VARIANT"} \
            else "VERIFIED_CURRENT_VARIANT"
    if got == {"VERIFIED_CURRENT_HOST_ONLY"}:
        return "VERIFIED_CURRENT_HOST_ONLY"
    if len(got) == 1:
        return got.pop()
    return "PARTIAL_COVERAGE" if got & verified else "NO_PUBLIC_MATCH" \
        if got == {"NO_PUBLIC_MATCH"} else "AMBIGUOUS_MATCH"


# ── output ───────────────────────────────────────────────────────────────────
def to_markdown(out):
    target_rev = (f"r{out['target_revision']}" if out["target_revision"]
                  else "unmapped — INCONCLUSIVE(target-mapping)")
    latest = (f"r{out['latest_revision']}" if out["latest_revision"]
              else "unavailable (BLOCKED)")
    lines = [
        f"### Distributed core test participation — {out['host'] or '(host unnamed)'}",
        "",
        f"Target build: **{out['target_build'] or '(not stated)'}** · "
        f"target revision: **{target_rev}** · "
        f"latest public revision: **{latest}** · "
        f"window: {out['window']} revisions · retrieved {out['retrieved_at']}",
        "",
        "| Host | Fleet variant | Reporter | Target evidence | Freshness |"
        " Outcome | Participation | Source | Gap / next action |",
        "|---|---|---|---|---|---|---|---|---|",
    ]
    target_slug = f"r{out['target_revision']}" if out["target_revision"] else None
    for ob in out["observations"]:
        rep = ob["reporter_display_name"] or "—"
        if ob["reporter_login"]:
            rep = f"[{rep}]({ob['reporter_url']}) (`{ob['reporter_login']}`)"
        # Only an exact-target row may print a revision in the target column —
        # a representative current-only row here would read as target coverage.
        target = (ob["reporter_revision"]
                  if target_slug and ob["reporter_revision"] == target_slug
                  else "none")
        fresh = ob["last_observed_revision"] or "—"
        gap = ob["limitation"] or "—"
        if ob["next_action"]:
            gap = (gap + " → " if gap != "—" else "") + ob["next_action"]
        lines.append(
            f"| {ob['provider']} | {ob['fleet_variant']} | {rep} | {target} "
            f"| {fresh} | {ob['test_outcome'] or '—'} | **{ob['participation']}** "
            f"| [dashboard]({ob['source_url'] or DASHBOARD_URL}) | {gap} |")
    s = out["summary"]
    lines += [
        "",
        f"**Host rollup: {s['host_participation']}.** Declared variants: "
        f"{s['variants_declared']} · exact-target evidence: {s['variants_target']} · "
        f"current-only: {s['variants_current']} · host-only: {s['variants_host_only']} · "
        f"no public match: {s['variants_no_match']} · "
        f"stale/ambiguous/blocked: {s['variants_other']}.",
        "",
        "Participation is not passing; passing core PHPUnit is not release "
        "readiness; NO_PUBLIC_MATCH is not proof of nonparticipation. "
        f"Evidence and replay: `{out['replay']}`",
    ]
    return "\n".join(lines)


def build_replay(argv):
    quoted = " ".join(a if re.fullmatch(r"[\w./=-]+", a) else json.dumps(a)
                      for a in argv)
    return f"python3 scripts/hosting-test-participation.py {quoted}"


# ── run modes ────────────────────────────────────────────────────────────────
def run_find(needle, evidence_dir):
    evidence = EvidenceStore(evidence_dir)
    try:
        candidates = find_candidates(evidence, needle)
    except SourceBlocked as exc:
        print(f"BLOCKED  {exc}")
        return 3
    if not candidates:
        print(f"NO_PUBLIC_MATCH  no reporter account matches '{needle}' "
              "(as of retrieval; not proof of nonparticipation)")
        return 0
    print(f"AMBIGUOUS_MATCH  {len(candidates)} candidate(s) for '{needle}' — "
          "every one needs operator confirmation before it counts:")
    for c in candidates:
        print(f"  {c['login']:24} {c['display_name']:32} {c['profile_url']}")
    print("Confirm the account with the host, then pass it as reporter_login "
          "with mapping_confirmed=yes.")
    return 0


def run_check(opts, argv):
    evidence = EvidenceStore(opts["evidence"])
    retrieved = now_iso()
    replay = build_replay(argv)

    variants = []
    if opts["variants_file"]:
        variants = read_variants_file(opts["variants_file"])
    for spec in opts["inline_variants"]:
        variants.append(parse_inline_variant(spec))
    for login in opts["reporters"]:
        # Host-level reporters with no variant attached still get observed.
        # --reporter means "confirmed as the host's account" (host-level only,
        # no variant claim) — unconfirmed candidates come from --find instead.
        if not any(v["reporter_login"] == login for v in variants):
            variants.append({"variant_id": "(host-level)", "description":
                             "host-level evidence, no variant claimed",
                             "reporter_login": login, "mapping_confirmed": "host",
                             "notes": "--reporter"})
    if not variants:
        print("hosting-test-participation: nothing to check — give --variants, "
              "--variant, or --reporter", file=sys.stderr)
        return 2

    blocked_reason = None
    observations = []
    try:
        revisions = get_revisions(evidence, opts["window"])
        latest = revisions[0]["number"]
        window_numbers = {r["number"] for r in revisions[: opts["window"]]}
        rev_by_post_id = {r["post_id"]: r for r in revisions}
        terms_php = get_term_map(evidence, "php-version")
        terms_db = get_term_map(evidence, "db-version")
        terms_status = get_term_map(evidence, "report-result")

        logins = sorted({(v.get("reporter_login") or "").strip()
                         for v in variants if (v.get("reporter_login") or "").strip()})
        login_count = {}
        for v in variants:
            lg = (v.get("reporter_login") or "").strip()
            if lg and (v.get("mapping_confirmed") or "").strip().lower() == "yes":
                login_count[lg] = login_count.get(lg, 0) + 1

        reporters, author_rows, author_trunc = {}, {}, {}
        for login in logins:
            reporters[login] = get_user_by_login(evidence, login)
            if reporters[login]:
                raw_rows, truncated = get_results_for_author(
                    evidence, reporters[login]["id"])
                # Resolve parents that were outside the revision window page.
                for post in raw_rows:
                    if post["parent"] and post["parent"] not in rev_by_post_id:
                        m = re.search(r"/test-results/(r\d+)/", post.get("link", ""))
                        if m:
                            rev_by_post_id[post["parent"]] = {
                                "post_id": post["parent"], "slug": m.group(1),
                                "number": revision_number(m.group(1)),
                                "title": "", "link": ""}
                author_rows[login] = [
                    parse_result_row(p, terms_php, terms_db, terms_status,
                                     rev_by_post_id)
                    for p in raw_rows if p["parent"]]
                author_trunc[login] = truncated
    except SourceBlocked as exc:
        blocked_reason = str(exc)

    variant_classes = []
    for v in variants:
        login = (v.get("reporter_login") or "").strip()
        if blocked_reason:
            participation, klass, lim, action, matched = (
                "BLOCKED", "", blocked_reason,
                "restore access to the public source, then rerun the exact "
                "replay command", [])
            reporter = None
        else:
            reporter = reporters.get(login)
            rows = author_rows.get(login, [])
            shared = login_count.get(login, 0) > 1
            participation, klass, lim, action, matched = classify_variant(
                v, reporter, rows, author_trunc.get(login, False),
                window_numbers, opts["revision"], shared)
        variant_classes.append(participation)

        last_obs = ""
        if not blocked_reason and reporter and author_rows.get(login):
            nums = [r["revision_number"] for r in author_rows[login]
                    if r["revision_number"] is not None]
            if nums:
                last_obs = f"r{max(nums)}"

        base = dict(
            provider=opts["host"], fleet_variant=v["variant_id"],
            reporter_login=login,
            reporter_display_name=(reporter or {}).get("display_name", ""),
            reporter_url=(reporter or {}).get("profile_url", ""),
            alias_status={"yes": "confirmed-for-variant", "host":
                          "confirmed-host-level"}.get(
                              (v.get("mapping_confirmed") or "").strip().lower(),
                              "proposed" if login else ""),
            target_build=opts["target"] or (
                f"r{opts['revision']}" if opts["revision"] else ""),
            last_observed_revision=last_obs, retrieved_at=retrieved,
            participation=participation, evidence_class=klass,
            limitation=lim, next_action=action,
        )
        if matched:
            for row in matched:
                # Outcome is recorded for rows at the exact target revision —
                # whatever the participation class says about attribution —
                # and reads NO_RESULT for representative non-target rows.
                on_target = (opts["revision"] is not None
                             and row["revision_number"] == opts["revision"])
                observations.append(observation(**{**base,
                    "reporter_revision": row["revision"] or "",
                    "php_version": row["php"], "db_version": row["db"],
                    "test_outcome": row["outcome"] if on_target else "NO_RESULT",
                    "source_url": row["link"],
                }))
        else:
            observations.append(observation(**{**base,
                "test_outcome": "NO_RESULT" if not blocked_reason else "",
                "source_url": DASHBOARD_URL,
            }))

    counts = {
        "variants_declared": len(variants),
        "variants_target": variant_classes.count("VERIFIED_TARGET_VARIANT"),
        "variants_current": variant_classes.count("VERIFIED_CURRENT_VARIANT"),
        "variants_host_only": variant_classes.count("VERIFIED_CURRENT_HOST_ONLY"),
        "variants_no_match": variant_classes.count("NO_PUBLIC_MATCH"),
        "variants_other": sum(1 for c in variant_classes if c in
                              ("STALE_REGISTRATION", "AMBIGUOUS_MATCH", "BLOCKED",
                               "NOT_APPLICABLE")),
        "host_participation": "BLOCKED" if blocked_reason else rollup(variant_classes),
    }
    out = {
        "collector_version": COLLECTOR_VERSION, "retrieved_at": retrieved,
        "base_url": BASE_URL, "host": opts["host"],
        "target_build": opts["target"],
        "target_revision": opts["revision"],
        "target_mapping": ("exact-revision" if opts["revision"] else
                           "INCONCLUSIVE(target-mapping)"),
        "window": opts["window"],
        "latest_revision": None if blocked_reason else latest,
        "observations": observations, "summary": counts,
        "blocked": blocked_reason,
        "limitations": [
            "The live deployment publishes no environment label; results cannot "
            "be attributed to a hosting product from public data alone "
            "(verified 2026-08-27).",
            "A public result proves a core PHPUnit run for that account, "
            "revision, PHP, and database — not plugin compatibility, upgrade "
            "safety, or production fleet coverage.",
            "NO_PUBLIC_MATCH is a statement about public evidence at retrieval "
            "time, not proof of nonparticipation.",
        ],
        "replay": replay,
    }
    md = to_markdown(out)
    evidence.finish(out, md, replay)
    print(md if opts["format"] == "markdown" else json.dumps(out, indent=1))
    return 3 if blocked_reason else 0


# ── controls ─────────────────────────────────────────────────────────────────
def run_control():
    """Offline controls over the captured fixture universes.

    Twelve scenario classes, each with the classification it must produce:
      1  exact host + variant + target revision      → VERIFIED_TARGET_VARIANT
      2  active host, no variant mapping             → VERIFIED_CURRENT_HOST_ONLY (shared login)
      3  several variants, evidence for one          → PARTIAL_COVERAGE rollup
      4  registered but stale reporter               → STALE_REGISTRATION
      5  no public match                             → NO_PUBLIC_MATCH
      6  duplicate/ambiguous candidates via --find   → both candidates listed, none auto-picked
      7  one login mapped to two variants            → both VERIFIED_CURRENT_HOST_ONLY
      8  submitted failure on target                 → participation verified, outcome FAILED
      9  target not mapped to a revision             → INCONCLUSIVE(target-mapping), no target class
     10  pagination across result pages              → all pages read
     11  upstream schema change                      → BLOCKED, exit 3
     12  network failure                             → BLOCKED, exit 3
    """
    fixture_root = ROOT / "fixtures" / "hosting-participation"
    problems = []

    def check(name, cond, detail=""):
        if not cond:
            problems.append(f"{name}: {detail}")

    def run(args, fixture="universe-a"):
        os.environ["WP_AUDIT_PTR_FIXTURE"] = str(fixture_root / fixture)
        import io
        from contextlib import redirect_stdout, redirect_stderr
        buf, err = io.StringIO(), io.StringIO()
        try:
            with redirect_stdout(buf), redirect_stderr(err):
                code = main(args)
        finally:
            os.environ.pop("WP_AUDIT_PTR_FIXTURE", None)
        return code, buf.getvalue(), err.getvalue()

    variants_ok = str(fixture_root / "variants-hostco.csv")
    variants_shared = str(fixture_root / "variants-hostco-shared-login.csv")

    # 1+3+8: full hostco inventory against target r90002. shared-basic has an
    # exact-target FAILED result; managed-wp is current-only; vps has no match.
    code, out, _ = run(["--host", "HostCo", "--variants", variants_ok,
                        "--revision", "90002", "--target", "trunk r90002",
                        "--format", "json"])
    check("cells 1/3/8 exit", code == 0, f"exit {code}")
    data = json.loads(out) if out.strip().startswith("{") else {}
    obs = {o["fleet_variant"]: o for o in data.get("observations", [])}
    check("cell 1 target-variant",
          obs.get("shared-basic", {}).get("participation") == "VERIFIED_TARGET_VARIANT",
          f"got {obs.get('shared-basic', {}).get('participation')}")
    check("cell 8 outcome stays separate",
          obs.get("shared-basic", {}).get("test_outcome") == "FAILED",
          f"got {obs.get('shared-basic', {}).get('test_outcome')}")
    check("cell 8 participation not demoted by failure",
          obs.get("shared-basic", {}).get("participation") == "VERIFIED_TARGET_VARIANT")
    check("cell 3 partial rollup",
          data.get("summary", {}).get("host_participation") == "PARTIAL_COVERAGE",
          f"got {data.get('summary', {}).get('host_participation')}")
    check("cell 5 no-public-match variant",
          obs.get("vps", {}).get("participation") == "NO_PUBLIC_MATCH",
          f"got {obs.get('vps', {}).get('participation')}")
    check("current-only variant",
          obs.get("managed-wp", {}).get("participation") == "VERIFIED_CURRENT_VARIANT",
          f"got {obs.get('managed-wp', {}).get('participation')}")

    # 4: stale reporter.
    code, out, _ = run(["--host", "StaleCo", "--variant",
                        "only-tier:the one tier:staleco-bot", "--revision", "90002",
                        "--format", "json"])
    data = json.loads(out)
    check("cell 4 stale", data["observations"][0]["participation"] ==
          "STALE_REGISTRATION", data["observations"][0]["participation"])
    check("cell 4 exit", code == 0, f"exit {code}")

    # 2: a confirmed host-level reporter (--reporter), no variant claim →
    # current evidence caps at VERIFIED_CURRENT_HOST_ONLY, never a variant class.
    code, out, _ = run(["--host", "HostCo", "--reporter", "hostco-managed-bot",
                        "--revision", "90002", "--format", "json"])
    data = json.loads(out)
    check("cell 2 host-only ceiling",
          data["observations"][0]["participation"] == "VERIFIED_CURRENT_HOST_ONLY",
          data["observations"][0]["participation"])

    # 7: one login confirmed for two variants → both capped at host-only.
    code, out, _ = run(["--host", "HostCo", "--variants", variants_shared,
                        "--revision", "90002", "--format", "json"])
    data = json.loads(out)
    got = {o["fleet_variant"]: o["participation"] for o in data["observations"]}
    check("cell 7 shared login capped",
          set(got.values()) == {"VERIFIED_CURRENT_HOST_ONLY"}, str(got))

    # 9: no --revision → current-only ceiling and explicit target-mapping gap.
    code, out, _ = run(["--host", "HostCo", "--variants", variants_ok,
                        "--target", "7.2-RC1", "--format", "json"])
    data = json.loads(out)
    check("cell 9 mapping label",
          data["target_mapping"] == "INCONCLUSIVE(target-mapping)",
          data["target_mapping"])
    check("cell 9 no target class without a revision",
          "VERIFIED_TARGET_VARIANT" not in
          {o["participation"] for o in data["observations"]})

    # 10: pagination universe — the reporter's exact-target result sits on
    # page 2 of their history; the verdict is only VERIFIED_TARGET_VARIANT if
    # page 2 was actually read.
    code, out, _ = run(["--host", "PageCo", "--variant",
                        "tier:the tier:pageco-bot", "--revision", "89990",
                        "--format", "json"], fixture="universe-paginated")
    data = json.loads(out)
    check("cell 10 pagination read through",
          data["observations"][0]["participation"] == "VERIFIED_TARGET_VARIANT",
          data["observations"][0]["participation"])

    # 11: schema drift → BLOCKED, exit 3, no classifications invented.
    code, out, _ = run(["--host", "HostCo", "--variants", variants_ok,
                        "--revision", "90002", "--format", "json"],
                       fixture="universe-drifted")
    check("cell 11 blocked exit", code == 3, f"exit {code}")
    data = json.loads(out)
    check("cell 11 blocked classification",
          {o["participation"] for o in data["observations"]} == {"BLOCKED"})

    # 12: simulated transport failure → BLOCKED, exit 3.
    code, out, _ = run(["--host", "HostCo", "--variants", variants_ok,
                        "--revision", "90002", "--format", "json"],
                       fixture="universe-netfail")
    check("cell 12 network-blocked exit", code == 3, f"exit {code}")

    # 6: discovery returns two candidates, neither auto-attributed.
    code, out, _ = run(["--find", "dupeco"], fixture="universe-a")
    check("cell 6 ambiguous candidates", "AMBIGUOUS_MATCH" in out and
          out.count("dupeco") >= 2, out.strip().splitlines()[0] if out else "no output")
    check("cell 6 exit", code == 0, f"exit {code}")

    if problems:
        print(f"FAIL  hosting-test-participation controls ({len(problems)})")
        for p in problems:
            print(f"        {p}")
        return 4
    print("ok    hosting-test-participation controls (12 scenario classes)")
    return 0


# ── argv ─────────────────────────────────────────────────────────────────────
def main(argv):
    opts = {"host": "", "variants_file": None, "inline_variants": [],
            "reporters": [], "revision": None, "target": "", "window":
            DEFAULT_WINDOW, "format": "json", "evidence": None}
    find_needle = None
    i = 0
    while i < len(argv):
        a = argv[i]

        def value():
            nonlocal i
            i += 1
            if i >= len(argv):
                raise CollectorError(f"{a} needs a value")
            return argv[i]

        try:
            if a == "--control":
                return run_control()
            elif a == "--host":
                opts["host"] = value()
            elif a == "--variants":
                opts["variants_file"] = value()
            elif a == "--variant":
                opts["inline_variants"].append(value())
            elif a == "--reporter":
                opts["reporters"].append(value())
            elif a == "--revision":
                opts["revision"] = int(value())
            elif a == "--target":
                opts["target"] = value()
            elif a == "--window":
                opts["window"] = int(value())
            elif a == "--format":
                opts["format"] = value()
                if opts["format"] not in ("json", "markdown"):
                    raise CollectorError(f"unknown format '{opts['format']}'")
            elif a == "--evidence":
                opts["evidence"] = value()
            elif a == "--find":
                find_needle = value()
            else:
                raise CollectorError(f"unknown argument '{a}'")
        except ValueError as exc:
            print(f"hosting-test-participation: {exc}", file=sys.stderr)
            return 1
        except CollectorError as exc:
            print(f"hosting-test-participation: {exc}", file=sys.stderr)
            return 1
        i += 1

    try:
        if find_needle is not None:
            return run_find(find_needle, opts["evidence"])
        return run_check(opts, argv)
    except CollectorError as exc:
        print(f"hosting-test-participation: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
