#!/usr/bin/env python3
"""Records the numbers GitHub gives away but does not keep.

Release download counts are cumulative and have no history. The traffic API
keeps fourteen days and then forgets. So once a day this script reads both and
appends what it sees to metrics/daily.csv, which is committed back to the repo.
The daily series is keyed by date, so a missed run leaves no hole: the next run
fills the last fortnight again from the traffic API and only the counters
(downloads, stars) are sampled as of that day.
"""

import csv
import json
import os
import sys
import urllib.request
from datetime import datetime, timezone

REPO = os.environ.get("GITHUB_REPOSITORY", "jovix0101/PriceBar")
TOKEN = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN", "")
PATH = "metrics/daily.csv"
FIELDS = [
    "date", "views", "uniques", "clones", "clone_uniques",
    "downloads", "downloads_dmg", "stars", "forks", "watchers", "open_issues",
]


def api(path):
    request = urllib.request.Request(
        f"https://api.github.com/repos/{REPO}{path}",
        headers={
            "Authorization": f"Bearer {TOKEN}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "PriceBar metrics",
        },
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def day(stamp):
    return datetime.fromisoformat(stamp.replace("Z", "+00:00")).astimezone(timezone.utc).strftime("%Y-%m-%d")


def load():
    rows = {}
    if not os.path.exists(PATH):
        return rows
    with open(PATH, newline="") as handle:
        for row in csv.DictReader(handle):
            rows[row["date"]] = {key: row.get(key, "") for key in FIELDS}
    return rows


def row_for(rows, date):
    row = rows.setdefault(date, dict.fromkeys(FIELDS, ""))
    row["date"] = date
    return row


def main():
    rows = load()
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")

    releases = api("/releases?per_page=100")
    downloads = sum(asset.get("download_count", 0) for release in releases for asset in release.get("assets", []))
    # The fixed name behind the product page's download button, so a click
    # there can be told apart from someone browsing the Releases page.
    downloads_dmg = sum(
        asset.get("download_count", 0)
        for release in releases
        for asset in release.get("assets", [])
        if asset.get("name") == "PriceBar.dmg"
    )

    repo = api("")
    row = row_for(rows, today)
    row.update(
        downloads=downloads, downloads_dmg=downloads_dmg,
        stars=repo["stargazers_count"], forks=repo["forks_count"],
        watchers=repo["subscribers_count"], open_issues=repo["open_issues_count"],
    )

    for kind in ("views", "clones"):
        try:
            series = api(f"/traffic/{kind}")[kind]
        except Exception as error:  # noqa: BLE001 - traffic needs push access
            print(f"traffic/{kind} unavailable: {error}", file=sys.stderr)
            continue
        for point in series:
            row = row_for(rows, day(point["timestamp"]))
            if kind == "views":
                row["views"] = point["count"]
                row["uniques"] = point["uniques"]
            else:
                row["clones"] = point["count"]
                row["clone_uniques"] = point["uniques"]

    os.makedirs(os.path.dirname(PATH), exist_ok=True)
    with open(PATH, "w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        writer.writeheader()
        for date in sorted(rows):
            writer.writerow(rows[date])

    print(f"{len(rows)} days recorded, today downloads={downloads} dmg={downloads_dmg} stars={repo['stargazers_count']}")


if __name__ == "__main__":
    main()
