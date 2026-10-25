#!/usr/bin/env python3
"""Commit one notebook file into its BigQuery Studio notebook repository.

A BigQuery Studio notebook is a Dataform repository labelled
single-file-asset-type=notebook that holds a single file, content.ipynb.
OpenTofu creates the repository. No OpenTofu resource writes files into a
Dataform repository, so `tofu apply` calls this script to commit the content.

Usage: commit_notebook.py <repository resource name> <path to .ipynb>
"""
import base64
import json
import subprocess
import sys
import urllib.error
import urllib.request

repository, path = sys.argv[1], sys.argv[2]

token = subprocess.check_output(["gcloud", "auth", "print-access-token"], text=True).strip()
with open(path, "rb") as f:
    contents = base64.b64encode(f.read()).decode()

body = {
    "commitMetadata": {
        "author": {"name": "OpenTofu", "emailAddress": "opentofu@example.com"},
        "commitMessage": f"Deploy {path.rsplit('/', 1)[-1]}",
    },
    "fileOperations": {"content.ipynb": {"writeFile": {"contents": contents}}},
}
request = urllib.request.Request(
    f"https://dataform.googleapis.com/v1/{repository}:commit",
    data=json.dumps(body).encode(),
    method="POST",
    headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
)
try:
    with urllib.request.urlopen(request, timeout=60):
        print(f"Committed {path} to {repository}")
except urllib.error.HTTPError as error:
    sys.exit(f"Commit failed ({error.code}): {error.read().decode()}")
