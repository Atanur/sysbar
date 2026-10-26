#!/usr/bin/env -S python3 -I
"""Keeps CHANGELOG.md, the GitHub release notes and the website's "What's new" in step.

  scripts/changelog.py draft [VERSION]  prints the feat, fix and perf commits since the last tag, to write the notes from
  scripts/changelog.py check VERSION    fails unless CHANGELOG.md has notes for VERSION
  scripts/changelog.py notes VERSION    prints VERSION's notes as Markdown, for `gh release create --notes-file`
  scripts/changelog.py site             writes the newest releases into docs/index.html between its changelog markers

CHANGELOG.md has a `## 0.5.3 — 2026-10-27` heading per release, newest first, each followed by
`- ` items written for people who use the app rather than copied from commits.
"""
import datetime
import html
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CHANGELOG = ROOT / "CHANGELOG.md"
SITE = ROOT / "docs" / "index.html"
START, END = "<!-- changelog:start -->", "<!-- changelog:end -->"
HEADING = re.compile(r"^## (\d+\.\d+\.\d+)(?:\s+[—–-]\s+(\d{4}-\d{2}-\d{2}))?\s*$")
OPEN_RELEASES = 3
SITE_RELEASES = 8
USER_FACING = re.compile(r"^(feat|fix|perf)(\(.+\))?!?: ")


def releases():
    """[(version, date, [item])] in file order; wrapped item lines are joined."""
    found, items = [], None
    for line in CHANGELOG.read_text(encoding="utf-8").splitlines():
        heading = HEADING.match(line)
        if heading:
            items = []
            found.append((heading.group(1), heading.group(2), items))
        elif line.startswith("## "):
            items = None
        elif items is not None and line.startswith(("- ", "* ")):
            items.append(line[2:].strip())
        elif items is not None and items and line.startswith(" ") and line.strip():
            items[-1] += " " + line.strip()
    return found


def find(version):
    for release in releases():
        if release[0] == version:
            return release
    return None


def draft(version):
    tags = subprocess.run(["git", "describe", "--tags", "--abbrev=0"], cwd=ROOT, capture_output=True, text=True)
    since = tags.stdout.strip()
    span = f"{since}..HEAD" if tags.returncode == 0 else "HEAD"
    log = subprocess.run(["git", "log", "--format=%s%n%b%x00", span], cwd=ROOT, capture_output=True, text=True, check=True)
    print(f"## {version or 'X.Y.Z'} — {datetime.date.today().isoformat()}\n")
    for entry in log.stdout.split("\0"):
        subject, _, body = entry.strip().partition("\n")
        if USER_FACING.match(subject):
            print(f"- {USER_FACING.sub('', subject)}")
            for line in body.strip().splitlines():
                print(f"    {line}")
    print(f"\n(commits since {since or 'the start'}; rewrite these for people who use the app)", file=sys.stderr)


def inline(text):
    """Escapes the text and keeps `code`, **bold** and https [links](url) as HTML."""
    escaped = html.escape(text, quote=True)
    escaped = re.sub(r"\[([^\]]+)\]\((https://[^)\s]+)\)", r'<a href="\2">\1</a>', escaped)
    escaped = re.sub(r"`([^`]+)`", r"<code>\1</code>", escaped)
    return re.sub(r"\*\*([^*]+)\*\*", r"<b>\1</b>", escaped)


def article(version, date, items):
    when = ""
    if date:
        shown = datetime.date.fromisoformat(date).strftime("%b %-d, %Y")
        when = f' <time datetime="{date}">{shown}</time>'
    rows = "".join(f"<li>{inline(item)}</li>" for item in items)
    return f'<article class="release"><h3><span class="version">{version}</span>{when}</h3><ul>{rows}</ul></article>'


def site():
    shown = releases()[:SITE_RELEASES]
    lines = [article(*release) for release in shown[:OPEN_RELEASES]]
    older = shown[OPEN_RELEASES:]
    if older:
        inner = "".join(article(*release) for release in older)
        lines.append(f'<details class="older"><summary>Earlier releases</summary>{inner}</details>')
    page = SITE.read_text(encoding="utf-8")
    if page.count(START) != 1 or page.count(END) != 1:
        sys.exit(f"{SITE.relative_to(ROOT)} needs exactly one {START} and one {END}")
    head, rest = page.split(START)
    _, tail = rest.split(END)
    SITE.write_text(head + START + "\n" + "\n".join(lines) + "\n" + END + tail, encoding="utf-8")
    print(f"{SITE.relative_to(ROOT)}: {len(shown)} releases")


def main():
    command, version = (sys.argv[1:] + [None, None])[:2]
    if command == "draft":
        draft(version)
    elif command in ("check", "notes") and version:
        release = find(version)
        if not release or not release[2]:
            sys.exit(f"CHANGELOG.md has no notes for {version}. Write them first; "
                     f"scripts/changelog.py draft {version} lists the commits since the last release.")
        if command == "notes":
            print("\n".join(f"- {item}" for item in release[2]))
    elif command == "site":
        site()
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
