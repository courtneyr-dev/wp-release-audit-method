#!/usr/bin/env python3
"""Follow-up watch: new replies to release work you filed, commented on, or were pinged on.

Twice a day, the follow-up-watch workflow asks: since the last run, did anyone else
reply where you took part this release cycle, or mention you anywhere on Core Trac?

Sources (all public, read anonymously; GitHub uses the workflow token):
- Core Trac: tickets in the filed-issues register, tickets your profile feed says you
  created, and tickets you changed since the cycle start (timeline `authors=` filter).
  New changes by anyone else on those tickets are follow-ups. A change on any other
  ticket whose text contains @<you> is a mention.
- GitHub: issues and pull requests in the watched orgs that `involves:` you and were
  updated in the window; new comments by anyone else are follow-ups.
- Make blogs and support forums: posts and topics your profile feed says you commented
  or replied on since the cycle start; new feed items by anyone else are follow-ups.

Configuration comes from the environment, so no account name lives in this file:
  WATCH_WPORG_USER     WordPress.org username (profile feed, Trac author filter, @mentions)
  WATCH_GITHUB_USER    GitHub username (involves: search, own-comment filter)
  WATCH_SINCE          cycle start, YYYY-MM-DD (for 7.2: Beta 1, 2026-10-20)
  WATCH_GITHUB_ORGS    comma-separated orgs to search (default: WordPress)
  GITHUB_TOKEN         optional; raises the GitHub API rate limit

The digest never names a commenter and neutralizes @-mentions, links and HTML in
titles, which are untrusted text. It lists links, counts and whether you're mentioned.

Usage:
  followup-watch.py --since 2026-11-06T13:00:00Z --out comment.md --status status.md
  followup-watch.py --control      # built-in positive and negative cases, no network

Exit codes: 0 every source answered; 2 at least one source was blocked or failed (the
digest still covers the others and says which); 1 bad configuration; 3 control failed.
"""
import argparse
import csv
import datetime as dt
import email.utils
import html
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

UA = "wp-release-audit-method-followup-watch/1.0 (+https://github.com/courtneyr-dev/wp-release-audit-method)"
TRAC = "https://core.trac.wordpress.org"
REGISTER = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "pilots", "filed-issues-register.csv")
UTC = dt.timezone.utc


class Blocked(Exception):
    pass


class Fetcher:
    def __init__(self, token=None):
        self.token = token

    def get(self, url, accept=None):
        h = {"User-Agent": UA}
        if accept:
            h["Accept"] = accept
        if self.token and url.startswith("https://api.github.com/"):
            h["Authorization"] = f"Bearer {self.token}"
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=h), timeout=60) as r:
                body = r.read().decode("utf-8", "replace")
        except urllib.error.HTTPError as e:
            raise Blocked(f"HTTP {e.code}") from None
        except (urllib.error.URLError, TimeoutError) as e:
            raise Blocked(f"network error: {getattr(e, 'reason', e)}") from None
        if re.search(r"cf_chl_opt|<title>\s*Just a moment", body[:20000], re.I):
            raise Blocked("challenge page")
        return body


# ---------- parsing helpers ----------

def rss_items(xml):
    out = []
    for it in re.findall(r"<item>(.*?)</item>", xml, re.S):
        def tag(t):
            m = re.search(rf"<{t}>(.*?)</{t}>", it, re.S)
            v = m.group(1).strip() if m else ""
            c = re.match(r"<!\[CDATA\[(.*)\]\]>$", v, re.S)
            return c.group(1) if c else v
        pub = tag("pubDate")
        when = email.utils.parsedate_to_datetime(pub).astimezone(UTC) if pub else None
        out.append({"title": html.unescape(tag("title")), "link": html.unescape(tag("link")),
                    "creator": html.unescape(tag("dc:creator")), "when": when,
                    "text": tag("description") + tag("content:encoded")})
    return out


def channel_title(xml):
    m = re.search(r"<channel>.*?<title>(.*?)</title>", xml, re.S)
    return html.unescape(m.group(1)).strip() if m else ""


def clean(title, limit=110):
    """Untrusted title -> inert markdown: no live mentions, links, HTML or line breaks."""
    t = re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", "", title))).strip()
    t = t.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    t = t.replace("[", "&#91;").replace("]", "&#93;").replace("`", "'").replace("@", "@\u200b")
    return t[:limit] + ("…" if len(t) > limit else "")


def mentions(text, user):
    return bool(user) and re.search(rf"@{re.escape(user)}\b", html.unescape(text), re.I) is not None


def iso(t):
    return t.strftime("%Y-%m-%dT%H:%M:%SZ")


# ---------- watch set ----------

def watch_set(f, cfg, status):
    """Tickets, Make posts and forum topics you took part in since the cycle start."""
    tickets, posts, topics, display = set(), set(), set(), ""
    try:
        with open(cfg["register"], newline="") as fh:
            for row in csv.DictReader(fh):
                if (row.get("date_filed") or "") < cfg["since_date"]:
                    continue
                url = row.get("url") or ""
                m = re.match(rf"{re.escape(TRAC)}/ticket/(\d+)", url)
                if m:
                    tickets.add(int(m.group(1)))
                elif re.match(r"https://make\.wordpress\.org/", url):
                    posts.add(url.split("#")[0])
    except OSError as e:
        status.append(("Register", f"not read ({e.strerror})"))
    try:
        xml = f.get(f"https://profiles.wordpress.org/{cfg['wporg']}/feed/")
        display = re.split(r"\s+[–-]\s+WordPress\.org", channel_title(xml))[0].strip()
        for it in rss_items(xml):
            if not it["when"] or it["when"].date().isoformat() < cfg["since_date"]:
                continue
            link = it["link"]
            m = re.match(rf"{re.escape(TRAC)}/ticket/(\d+)", link)
            if m:
                tickets.add(int(m.group(1)))
            elif re.match(r"https://make\.wordpress\.org/", link) and it["title"].startswith("Wrote a comment"):
                posts.add(link.split("#")[0])
            elif re.match(r"https://wordpress\.org/support/topic/", link) and re.match(r"(Posted a reply|Created a topic)", it["title"]):
                topics.add(link.split("#")[0])
        status.append(("Profile feed", "ok"))
    except Blocked as e:
        status.append(("Profile feed", f"BLOCKED ({e})"))
    days = max(1, (dt.datetime.now(UTC).date() - dt.date.fromisoformat(cfg["since_date"])).days + 1)
    try:
        xml = f.get(f"{TRAC}/timeline?ticket=on&ticket_details=on&changeset=off&milestone=off&wiki=off"
                    f"&format=rss&max=1000&daysback={min(days, 180)}&authors={urllib.parse.quote(cfg['wporg'])}")
        for it in rss_items(xml):
            m = re.search(r"/ticket/(\d+)", it["link"])
            if m:
                tickets.add(int(m.group(1)))
        status.append(("Core Trac (your tickets)", "ok"))
    except Blocked as e:
        status.append(("Core Trac (your tickets)", f"BLOCKED ({e})"))
    return tickets, posts, topics, display


# ---------- follow-ups ----------

def trac_followups(f, cfg, tickets, start, now, status):
    days = max(1, (now.date() - start.date()).days + 1)
    try:
        xml = f.get(f"{TRAC}/timeline?ticket=on&ticket_details=on&changeset=off&milestone=off&wiki=off"
                    f"&format=rss&max=5000&daysback={days}")
    except Blocked as e:
        status.append(("Core Trac", f"BLOCKED ({e})"))
        return []
    found = {}
    for it in rss_items(xml):
        m = re.search(r"/ticket/(\d+)", it["link"])
        if not m or not it["when"] or not (start < it["when"] <= now):
            continue
        if it["creator"].lower() == cfg["wporg"].lower():
            continue
        n, ment = int(m.group(1)), mentions(it["text"], cfg["wporg"])
        if n not in tickets and not ment:
            continue
        title = re.sub(r"^Ticket #\d+ \((.*)\) \w+$", r"\1", it["title"])
        e = found.setdefault(n, {"key": f"trac:{n}", "label": f"#{n}: {clean(title)}", "link": it["link"],
                                 "first": it["when"], "count": 0, "mention": False, "watched": n in tickets})
        e["count"] += 1
        e["mention"] = e["mention"] or ment
        if it["when"] < e["first"]:
            e["first"], e["link"] = it["when"], it["link"]
    status.append(("Core Trac", f"ok ({len(tickets)} tickets watched)"))
    return sorted(found.values(), key=lambda e: e["first"])


def github_followups(f, cfg, start, now, status):
    if not cfg["github"]:
        status.append(("GitHub", "skipped (WATCH_GITHUB_USER not set)"))
        return []
    out, checked = [], 0
    try:
        for org in cfg["orgs"]:
            q = f"involves:{cfg['github']} org:{org} updated:>={iso(start)}"
            res = json.loads(f.get("https://api.github.com/search/issues?per_page=100&q=" + urllib.parse.quote(q),
                                   accept="application/vnd.github+json"))
            for item in res.get("items", []):
                checked += 1
                api = item["comments_url"] + "?per_page=100&since=" + urllib.parse.quote(iso(start))
                new = [c for c in json.loads(f.get(api, accept="application/vnd.github+json"))
                       if c["user"]["login"].lower() != cfg["github"].lower()
                       and start < dt.datetime.fromisoformat(c["created_at"].replace("Z", "+00:00")) <= now]
                if not new:
                    continue
                repo = item["repository_url"].split("/repos/")[1]
                out.append({"key": f"gh:{repo}#{item['number']}", "label": f"{repo}#{item['number']}: {clean(item['title'])}",
                            "link": new[0]["html_url"], "first": dt.datetime.fromisoformat(new[0]["created_at"].replace("Z", "+00:00")),
                            "count": len(new), "mention": any(mentions(c.get("body") or "", cfg["github"]) for c in new), "watched": True})
    except Blocked as e:
        status.append(("GitHub", f"BLOCKED ({e}) after {checked} items"))
        return out
    status.append(("GitHub", f"ok ({checked} items updated in the window)"))
    return out


def feed_followups(f, name, urls, display, cfg, start, now, status):
    out, blocked = [], []
    for url in sorted(urls):
        try:
            xml = f.get(url.rstrip("/") + "/feed/")
            items = rss_items(xml)
        except Blocked as e:
            blocked.append(str(e))
            continue
        new = [i for i in items if i["when"] and start < i["when"] <= now
               and (not display or i["creator"].strip().lower() != display.lower())]
        if new:
            new.sort(key=lambda i: i["when"])
            # Item titles name the commenter ("By: …", "Comment on X by …"); label with the post instead.
            title = re.sub(r"^(Comments on|Topic|Re|Reply To)\s*:\s*", "", channel_title(xml)).strip()
            title = title or url.rstrip("/").rsplit("/", 1)[-1].replace("-", " ")
            out.append({"key": f"{name}:{url}", "label": clean(title), "link": new[0]["link"], "first": new[0]["when"],
                        "count": len(new), "mention": any(mentions(i["text"], cfg["wporg"]) for i in new), "watched": True})
    state = f"ok ({len(urls)} watched)" if not blocked else f"BLOCKED on {len(blocked)} of {len(urls)} ({blocked[0]})"
    status.append((name, state))
    return out


# ---------- report ----------

def render(sections, start, now):
    lines = [f"New follow-ups between {iso(start)} and {iso(now)}:", ""]
    for name, items in sections:
        if not items:
            continue
        lines.append(f"**{name}**")
        lines.append("")
        for e in items:
            bits = [f"{e['count']} new" + (" comment" if e["count"] == 1 else " comments")]
            if e["mention"]:
                bits.append("mentions you")
            if not e["watched"]:
                bits.append("not a ticket you're on")
            lines.append(f"- [{e['label']}]({e['link']}) ({', '.join(bits)})")
        lines.append("")
    return "\n".join(lines)


def run(f, cfg, start, now):
    status = []
    tickets, posts, topics, display = watch_set(f, cfg, status)
    sections = [
        ("Core Trac", trac_followups(f, cfg, tickets, start, now, status)),
        ("GitHub", github_followups(f, cfg, start, now, status)),
        ("Make blogs", feed_followups(f, "Make blogs", posts, display, cfg, start, now, status)),
        ("Support forums", feed_followups(f, "Support forums", topics, display, cfg, start, now, status)),
    ]
    return sections, status


# ---------- control ----------

def control():
    """Positive and negative cases against canned responses. No network."""
    me, gh, other = "watcher", "watcher-gh", "someone"
    start = dt.datetime(2026, 11, 6, 13, 0, tzinfo=UTC)
    now = dt.datetime(2026, 11, 6, 20, 0, tzinfo=UTC)
    rfc = lambda h, m=0: email.utils.format_datetime(dt.datetime(2026, 11, 6, h, m, tzinfo=UTC))

    def trac_item(n, who, h, text="", c=1):
        return (f"<item><title>Ticket #{n} (Title {n} @{other} [x](https://evil.test) &lt;b&gt;) updated</title>"
                f"<link>{TRAC}/ticket/{n}#comment:{c}</link><dc:creator>{who}</dc:creator>"
                f"<pubDate>{rfc(h)}</pubDate><description>{html.escape(text)}</description></item>")

    profile = ("<rss><channel><title>Watcher Person &#8211; WordPress.org Profile Activity</title>"
               f"<item><title>Created ticket #100 on Core Trac: x</title><link>{TRAC}/ticket/100</link><pubDate>{rfc(1)}</pubDate></item>"
               "<item><title>Wrote a comment on the post P, on the site Make WordPress Test: y</title>"
               f"<link>https://make.wordpress.org/test/2026/10/20/p/#comment-1</link><pubDate>{rfc(2)}</pubDate></item>"
               f"<item><title>Committed [1] to Plugins SVN: z</title><link>https://plugins.trac.wordpress.org/changeset/1/</link><pubDate>{rfc(3)}</pubDate></item>"
               "</channel></rss>")
    mine = f"<rss><channel>{trac_item(101, me, 1)}{trac_item(105, me, 1)}</channel></rss>"
    alltl = "<rss><channel>" + "".join([
        trac_item(100, other, 14, "a reply", 2),                 # watched, other, in window -> follow-up
        trac_item(100, other, 15, "another", 3),                 # same ticket -> count 2
        trac_item(101, me, 16, "my own"),                        # watched, self -> ignored
        trac_item(105, other, 12, "before window"),              # watched, before window -> ignored
        trac_item(102, other, 17, f"ping @{me} please"),         # unwatched, mention -> reported
        trac_item(103, other, 18, "unrelated"),                  # unwatched, no mention -> ignored
        trac_item(104, other, 19, f"email {me}@example.test"),   # not a mention -> ignored
    ]) + "</channel></rss>"
    make = ("<rss><channel><title>Comments on: Post P</title>"
            f"<item><title>Comment on P by Watcher Person</title><link>https://make.wordpress.org/test/2026/10/20/p/#comment-2</link>"
            f"<dc:creator><![CDATA[Watcher Person]]></dc:creator><pubDate>{rfc(14)}</pubDate><description>mine</description></item>"
            f"<item><title>By: Someone Else</title><link>https://make.wordpress.org/test/2026/10/20/p/#comment-3</link>"
            f"<dc:creator><![CDATA[Someone Else]]></dc:creator><pubDate>{rfc(15)}</pubDate><description>@{me} thanks</description></item>"
            "</channel></rss>")
    search = {"items": [{"number": 7, "title": "Issue @team", "repository_url": "https://api.github.com/repos/WordPress/x",
                         "comments_url": "https://api.github.com/repos/WordPress/x/issues/7/comments"}]}
    comments = [{"user": {"login": gh}, "created_at": "2026-11-06T14:00:00Z", "html_url": "https://github.com/WordPress/x/issues/7#c1", "body": "mine"},
                {"user": {"login": other}, "created_at": "2026-11-06T15:00:00Z", "html_url": "https://github.com/WordPress/x/issues/7#c2", "body": f"@{gh} done"}]

    class Canned:
        def get(self, url, accept=None):
            if "profiles.wordpress.org" in url:
                return profile
            if "authors=" in url:
                return mine
            if "/timeline?" in url:
                return alltl
            if "make.wordpress.org" in url:
                return make
            if "search/issues" in url:
                return json.dumps(search)
            if "/comments" in url:
                return json.dumps(comments)
            raise Blocked("HTTP 403")

    cfg = {"wporg": me, "github": gh, "since_date": "2026-10-20", "orgs": ["WordPress"], "register": os.devnull}
    sections, status = run(Canned(), cfg, start, now)
    got = {e["key"]: e for _, items in sections for e in items}
    body = render(sections, start, now)
    checks = [
        ("trac follow-up on a watched ticket is reported", "trac:100" in got and got["trac:100"]["count"] == 2),
        ("own Trac comment is ignored", "trac:101" not in got),
        ("comment before the window is ignored", "trac:105" not in got),
        ("@mention on an unwatched ticket is reported", "trac:102" in got and got["trac:102"]["mention"] and not got["trac:102"]["watched"]),
        ("unwatched ticket without a mention is ignored", "trac:103" not in got),
        ("an email address is not a mention", "trac:104" not in got),
        ("other's Make comment is reported, own is not", got.get("Make blogs:https://make.wordpress.org/test/2026/10/20/p/", {}).get("count") == 1),
        ("Make reply mentioning you is flagged", got.get("Make blogs:https://make.wordpress.org/test/2026/10/20/p/", {}).get("mention") is True),
        ("other's GitHub comment is reported, own is not", got.get("gh:WordPress/x#7", {}).get("count") == 1),
        ("SVN commits don't enter the watch set", "plugins.trac" not in body),
        ("feed entries are labeled by post, never by commenter", "Post P" in body and "Someone Else" not in body),
        ("titles can't ping anyone", "@" + other not in body and "@team" not in body),
        ("titles can't inject links or HTML", "](https://evil.test)" not in body and "<b>" not in body),
    ]
    # Negative control for the blocked path: a source that answers 403 must say BLOCKED.
    class Broken(Canned):
        def get(self, url, accept=None):
            if "/timeline?" in url and "authors=" not in url:
                raise Blocked("HTTP 403")
            return super().get(url, accept)
    _, st2 = run(Broken(), cfg, start, now)
    checks.append(("a blocked source is reported as BLOCKED", any(n == "Core Trac" and v.startswith("BLOCKED") for n, v in st2)))
    failed = [name for name, ok in checks if not ok]
    for name, ok in checks:
        print(("PASS " if ok else "FAIL ") + name)
    return 3 if failed else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--control", action="store_true")
    ap.add_argument("--since", help="window start, ISO 8601 UTC; default 36 hours ago")
    ap.add_argument("--out", help="write the digest (markdown) here when there are follow-ups")
    ap.add_argument("--status", help="write the per-source status (markdown) here")
    ap.add_argument("--count-file", help="write the number of follow-ups here")
    a = ap.parse_args()
    if a.control:
        return control()

    cfg = {"wporg": os.environ.get("WATCH_WPORG_USER", "").strip(), "github": os.environ.get("WATCH_GITHUB_USER", "").strip(),
           "since_date": os.environ.get("WATCH_SINCE", "").strip(), "register": REGISTER,
           "orgs": [o.strip() for o in os.environ.get("WATCH_GITHUB_ORGS", "WordPress").split(",") if o.strip()]}
    if not re.fullmatch(r"[A-Za-z0-9._-]{1,60}", cfg["wporg"]) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", cfg["since_date"]):
        print("set WATCH_WPORG_USER and WATCH_SINCE (YYYY-MM-DD)", file=sys.stderr)
        return 1
    if cfg["github"] and not re.fullmatch(r"[A-Za-z0-9-]{1,39}", cfg["github"]):
        print("WATCH_GITHUB_USER is not a GitHub username", file=sys.stderr)
        return 1
    now = dt.datetime.now(UTC).replace(microsecond=0)
    if a.since:
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z", a.since):
            print("--since must look like 2026-11-06T13:00:00Z", file=sys.stderr)
            return 1
        start = dt.datetime.fromisoformat(a.since.replace("Z", "+00:00"))
    else:
        start = now - dt.timedelta(hours=36)
    start = max(start, now - dt.timedelta(days=14))

    sections, status = run(Fetcher(os.environ.get("GITHUB_TOKEN")), cfg, start, now)
    count = sum(len(items) for _, items in sections)
    status_md = "\n".join(f"- {name}: {state}" for name, state in status)
    print(f"window {iso(start)} .. {iso(now)}; {count} follow-ups\n{status_md}")
    if a.status:
        with open(a.status, "w") as fh:
            fh.write(f"Last run: {iso(now)} (window from {iso(start)}).\n\n{status_md}\n\n<!-- followup-watch last-run: {iso(now)} -->\n")
    if a.count_file:
        with open(a.count_file, "w") as fh:
            fh.write(str(count))
    if a.out and count:
        with open(a.out, "w") as fh:
            fh.write(render(sections, start, now) + "\n")
    return 2 if any("BLOCKED" in s for _, s in status) else 0


if __name__ == "__main__":
    sys.exit(main())
