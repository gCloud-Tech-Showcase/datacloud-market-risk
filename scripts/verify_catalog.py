#!/usr/bin/env python3
"""Check that the Knowledge Catalog layer is in place and green.

Checks:
  1. Every profile, quality and insights scan's latest run succeeded.
  2. Every quality rule passed.
  3. The three data products exist with their assets.
  4. The glossary has its terms.
  5. Lineage traces serving.var_by_desk back to the raw prices and positions.

Usage:
  python3 scripts/verify_catalog.py [--project=<id>] [--region=<region>] [--wait=<minutes>]

--wait polls until no scan is still running, for up to that many minutes.
Needs: python3 and gcloud, logged in with access to the project.
"""

import argparse
import json
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EXPECTED_PRODUCTS = {"market-data": 3, "trading-positions": 1, "market-risk-metrics": 4}
EXPECTED_TERMS = 10
LINEAGE_START = "serving.var_by_desk"
LINEAGE_SOURCES = ["raw.sp500_daily_prices", "raw.portfolio_positions"]


def tf_default(name):
    text = (ROOT / "infra" / "variables.tf").read_text()
    match = re.search(r'variable "%s" \{.*?default\s*=\s*"([^"]*)"' % name, text, re.S)
    return match.group(1) if match else None


def token():
    return subprocess.run(
        ["gcloud", "auth", "print-access-token"], check=True, capture_output=True, text=True
    ).stdout.strip()


class Api:
    def __init__(self, project):
        self.project = project
        self.token = token()

    def call(self, url, body=None):
        request = urllib.request.Request(
            url,
            data=json.dumps(body).encode() if body is not None else None,
            method="POST" if body is not None else "GET",
            headers={
                "Authorization": f"Bearer {self.token}",
                "x-goog-user-project": self.project,
                "Content-Type": "application/json",
            },
        )
        try:
            with urllib.request.urlopen(request) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            return {"error": error.read().decode()[:300]}


def latest_jobs(api, base):
    scans = api.call(f"{base}/dataScans?pageSize=200").get("dataScans", [])
    jobs = {}
    for scan in scans:
        scan_id = scan["name"].rsplit("/", 1)[1]
        listed = api.call(f"{base}/dataScans/{scan_id}/jobs?pageSize=1").get("dataScanJobs", [])
        if not listed:
            jobs[scan_id] = None
            continue
        jobs[scan_id] = api.call(f"https://dataplex.googleapis.com/v1/{listed[0]['name']}?view=FULL")
    return jobs


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", default=tf_default("project_id"))
    parser.add_argument("--region", default=tf_default("region"))
    parser.add_argument("--wait", type=int, default=0)
    args = parser.parse_args()

    api = Api(args.project)
    base = f"https://dataplex.googleapis.com/v1/projects/{args.project}/locations/{args.region}"
    failures = []

    print(f"Knowledge Catalog checks for {args.project} in {args.region}\n")

    # 1 and 2. Scans and quality rules.
    deadline = time.time() + args.wait * 60
    while True:
        jobs = latest_jobs(api, base)
        running = [s for s, j in jobs.items() if j and j.get("state") in ("PENDING", "RUNNING")]
        if not running or time.time() >= deadline:
            break
        print(f"  waiting for {len(running)} scan(s) still running...")
        time.sleep(30)

    print("Scans")
    for scan_id, job in sorted(jobs.items()):
        state = job.get("state", "NO RUN") if job else "NO RUN"
        line = f"  {'ok  ' if state == 'SUCCEEDED' else 'FAIL'} {scan_id}: {state}"
        quality = (job or {}).get("dataQualityResult")
        if quality is not None and state == "SUCCEEDED":
            rules = quality.get("rules", [])
            failed = [r["rule"].get("name", "?") for r in rules if not r.get("passed")]
            line += f", {len(rules) - len(failed)}/{len(rules)} rules passed"
            if failed:
                failures.append(f"{scan_id}: failed rules {', '.join(failed)}")
                line = line.replace("ok  ", "FAIL", 1)
        if state != "SUCCEEDED":
            failures.append(f"{scan_id}: {state}")
        print(line)
    if not jobs:
        failures.append("no scans found")

    # 3. Data products.
    print("\nData products")
    for product_id, expected in EXPECTED_PRODUCTS.items():
        product = api.call(f"{base}/dataProducts/{product_id}")
        assets = api.call(f"{base}/dataProducts/{product_id}/dataAssets").get("dataAssets", [])
        ok = "error" not in product and len(assets) == expected
        print(f"  {'ok  ' if ok else 'FAIL'} {product_id}: {len(assets)}/{expected} assets")
        if not ok:
            failures.append(f"data product {product_id}")

    # 4. Glossary.
    print("\nGlossary")
    terms = api.call(f"{base}/glossaries/market-risk/terms?pageSize=100").get("terms", [])
    ok = len(terms) == EXPECTED_TERMS
    print(f"  {'ok  ' if ok else 'FAIL'} market-risk: {len(terms)}/{EXPECTED_TERMS} terms")
    if not ok:
        failures.append("glossary terms")

    # 5. Lineage, walking upstream from the desk VaR view.
    print("\nLineage")
    lineage = f"https://datalineage.googleapis.com/v1/projects/{args.project}/locations/{args.region}:searchLinks"
    seen, frontier = set(), [f"bigquery:{args.project}.{LINEAGE_START}"]
    while frontier:
        target = frontier.pop()
        links = api.call(lineage, {"target": {"fullyQualifiedName": target}}).get("links", [])
        for link in links:
            source = link["source"]["fullyQualifiedName"]
            if source not in seen:
                seen.add(source)
                frontier.append(source)
    for source in LINEAGE_SOURCES:
        ok = f"bigquery:{args.project}.{source}" in seen
        print(f"  {'ok  ' if ok else 'FAIL'} {LINEAGE_START} traces back to {source}")
        if not ok:
            failures.append(f"lineage to {source}")

    print()
    if failures:
        print(f"{len(failures)} check(s) failed:")
        for failure in failures:
            print(f"  - {failure}")
        sys.exit(1)
    print("All checks passed.")


if __name__ == "__main__":
    main()
