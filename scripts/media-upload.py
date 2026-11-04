"""Upload exercise videos to CloudKit's public database through CloudKit Web Services.

Run through `./dev media-upload`, never directly: the wrapper owns the server-to-server key (a mode-600 file in a private
temp directory that a trap deletes) and passes this script only that file's PATH. The key is never read here: every
signature comes from `openssl dgst -sha256 -sign <keyfile>`. Standard library only; run with `python3 -I`.

Usage: media-upload.py --key-file F --key-id ID --env development|production --media-dir D [--limit N] [--only SOURCEID]

Protocol (CloudKit Web Services reference): each request carries X-Apple-CloudKit-Request-{KeyID,ISO8601Date,SignatureV1};
the signature is base64(ECDSA-SHA256(date ":" base64(sha256(body)) ":" subpath)). Per batch of records:
records/lookup (skip those that already hold both assets), assets/upload (tokens), POST each file to its upload URL
(multipart/form-data), then records/modify with forceReplace so a re-run replaces rather than duplicates.
No header value is ever printed.
"""

import argparse
import base64
import concurrent.futures
import datetime
import hashlib
import json
import os
import random
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

HOST = "https://api.apple-cloudkit.com"
CONTAINER = "iCloud.com.ericribeiro.Workouts"
RECORD_TYPE = "ExerciseMedia"
FIELDS = (("videoLight", "video-light.mp4"), ("videoDark", "video-dark.mp4"))
BATCH = 20
UPLOAD_THREADS = 8
MAX_ATTEMPTS = 6
PROGRESS_EVERY = 50


class ApiError(Exception):
    pass


def log(message):
    print(message, flush=True)


def log_error(message):
    print(message, file=sys.stderr, flush=True)


class Client:
    def __init__(self, key_file, key_id, env):
        self.key_file = key_file
        self.key_id = key_id
        self.base = f"/database/1/{CONTAINER}/{env}/public"

    def _sign(self, message):
        proc = subprocess.run(
            ["openssl", "dgst", "-sha256", "-sign", self.key_file],
            input=message.encode(),
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        if proc.returncode != 0 or not proc.stdout:
            raise ApiError("openssl could not sign with the key file")
        return base64.b64encode(proc.stdout).decode()

    @staticmethod
    def _delay(attempt, retry_after):
        if retry_after is not None:
            return min(float(retry_after), 120.0)
        return min(2.0**attempt, 60.0) + random.random()

    def _send(self, request, what):
        """Send with retry on 429/503/5xx and network errors. Returns (status, body bytes)."""
        for attempt in range(MAX_ATTEMPTS):
            retry_after = None
            try:
                with urllib.request.urlopen(request, timeout=120) as resp:
                    return resp.status, resp.read()
            except urllib.error.HTTPError as err:
                body = err.read()
                if err.code in (429, 503, 502, 504, 421):
                    header = err.headers.get("Retry-After")
                    retry_after = header if header and header.replace(".", "", 1).isdigit() else None
                    try:
                        value = json.loads(body).get("retryAfter")
                        if value is not None:
                            retry_after = value
                    except (ValueError, AttributeError):
                        pass
                    if attempt + 1 < MAX_ATTEMPTS:
                        time.sleep(self._delay(attempt, retry_after))
                        continue
                return err.code, body
            except (urllib.error.URLError, TimeoutError, ConnectionError) as err:
                if attempt + 1 < MAX_ATTEMPTS:
                    time.sleep(self._delay(attempt, None))
                    continue
                raise ApiError(f"{what}: network error: {type(err).__name__}") from None
        raise ApiError(f"{what}: gave up")

    def call(self, operation, payload):
        """Signed JSON POST to <base>/<operation>; returns the decoded JSON body (raises on HTTP errors)."""
        subpath = f"{self.base}/{operation}"
        body = json.dumps(payload, separators=(",", ":")).encode()
        date = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        digest = base64.b64encode(hashlib.sha256(body).digest()).decode()
        signature = self._sign(f"{date}:{digest}:{subpath}")
        request = urllib.request.Request(
            HOST + subpath,
            data=body,
            method="POST",
            headers={
                "Content-Type": "text/plain",
                "X-Apple-CloudKit-Request-KeyID": self.key_id,
                "X-Apple-CloudKit-Request-ISO8601Date": date,
                "X-Apple-CloudKit-Request-SignatureV1": signature,
            },
        )
        status, raw = self._send(request, operation)
        try:
            data = json.loads(raw)
        except ValueError:
            data = {}
        if status != 200:
            code = data.get("serverErrorCode", "") if isinstance(data, dict) else ""
            reason = data.get("reason", "") if isinstance(data, dict) else ""
            raise ApiError(f"{operation}: HTTP {status} {code} {reason}".strip())
        return data

    def upload_file(self, url, path):
        """POST one file to a one-time upload URL (unsigned); returns its `singleFile` receipt dict."""
        boundary = "----workouts" + hashlib.sha256(os.urandom(16)).hexdigest()[:24]
        with open(path, "rb") as handle:
            content = handle.read()
        head = (
            f"--{boundary}\r\n"
            f'Content-Disposition: form-data; name="file"; filename="{os.path.basename(path)}"\r\n'
            "Content-Type: application/octet-stream\r\n\r\n"
        ).encode()
        body = head + content + f"\r\n--{boundary}--\r\n".encode()
        request = urllib.request.Request(
            url,
            data=body,
            method="POST",
            headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
        )
        status, raw = self._send(request, "asset upload")
        if status != 200:
            raise ApiError(f"asset upload: HTTP {status}")
        try:
            single = json.loads(raw)["singleFile"]
        except (ValueError, KeyError, TypeError):
            raise ApiError("asset upload: response had no singleFile") from None
        return single


def list_source_ids(media_dir, only, limit):
    if only:
        ids = [only]
    else:
        ids = sorted(name for name in os.listdir(media_dir) if os.path.isdir(os.path.join(media_dir, name)))
    return ids[:limit] if limit else ids


def existing_complete(lookup):
    """recordNames from a records/lookup response that already hold both asset fields."""
    done = set()
    for record in lookup.get("records", []):
        fields = record.get("fields") or {}
        if all(name in fields and fields[name].get("value") for name, _ in FIELDS):
            done.add(record.get("recordName"))
    return done


def process_batch(client, media_dir, ids, totals):
    # Which of these are already complete? (A lookup for a missing record, or for a type that does not exist yet, simply
    # returns no fields for it.)
    lookup = client.call(
        "records/lookup",
        {"records": [{"recordName": rid} for rid in ids], "desiredFields": [name for name, _ in FIELDS]},
    )
    done = existing_complete(lookup)
    totals["skipped_existing"] += len(done)

    todo = []  # (sourceId, [(field, path)])
    for rid in ids:
        if rid in done:
            continue
        files = []
        for field, name in FIELDS:
            path = os.path.join(media_dir, rid, name)
            if os.path.isfile(path):
                files.append((field, path))
        if len(files) < len(FIELDS):
            totals["missing_files"] += 1
            continue
        todo.append((rid, files))
    if not todo:
        return

    tokens = [
        {"recordType": RECORD_TYPE, "fieldName": field, "recordName": rid} for rid, files in todo for field, _ in files
    ]
    issued = client.call("assets/upload", {"tokens": tokens}).get("tokens", [])
    urls = {(t.get("recordName"), t.get("fieldName")): t.get("url") for t in issued}

    jobs = []
    for rid, files in todo:
        for field, path in files:
            jobs.append((rid, field, path, urls.get((rid, field))))

    receipts = {}
    errors = {}

    def run(job):
        rid, field, path, url = job
        if not url:
            raise ApiError("no upload URL issued")
        return client.upload_file(url, path)

    with concurrent.futures.ThreadPoolExecutor(max_workers=UPLOAD_THREADS) as pool:
        futures = {pool.submit(run, job): job for job in jobs}
        for future in concurrent.futures.as_completed(futures):
            rid, field, _, _ = futures[future]
            try:
                receipts[(rid, field)] = future.result()
            except (ApiError, OSError) as err:
                errors[rid] = f"{field}: {err}"

    operations = []
    for rid, files in todo:
        if rid in errors:
            totals["failed"] += 1
            log_error(f"failed {rid}: {errors[rid]}")
            continue
        fields = {"sourceId": {"value": rid, "type": "STRING"}}
        for field, _ in files:
            fields[field] = {"value": receipts[(rid, field)], "type": "ASSETID"}
        operations.append(
            {
                "operationType": "forceReplace",
                "record": {"recordType": RECORD_TYPE, "recordName": rid, "fields": fields},
            }
        )
    if not operations:
        return
    result = client.call("records/modify", {"operations": operations, "atomic": False})
    for record in result.get("records", []):
        if "serverErrorCode" in record:
            totals["failed"] += 1
            log_error(
                f"failed {record.get('recordName', '?')}: {record['serverErrorCode']} {record.get('reason', '')}".strip()
            )
        else:
            totals["uploaded"] += 1


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--key-file", required=True)
    parser.add_argument("--key-id", required=True)
    parser.add_argument("--env", choices=("development", "production"), required=True)
    parser.add_argument("--media-dir", required=True)
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--only", default="")
    parser.add_argument("--lookup", action="store_true")
    args = parser.parse_args()

    if not os.path.isdir(args.media_dir):
        log_error(f"media-upload: {args.media_dir} is not a directory")
        return 1
    ids = list_source_ids(args.media_dir, args.only, args.limit)
    if not ids:
        log_error("media-upload: no source folders to upload")
        return 1

    client = Client(args.key_file, args.key_id, args.env)
    if args.lookup:
        # Read-only check: print each asset field's size and the download URL's host (never the URL itself).
        try:
            result = client.call(
                "records/lookup",
                {"records": [{"recordName": rid} for rid in ids], "desiredFields": [n for n, _ in FIELDS]},
            )
        except ApiError as err:
            log_error(f"lookup failed: {err}")
            return 1
        for record in result.get("records", []):
            name = record.get("recordName", "?")
            if "serverErrorCode" in record:
                log(f"lookup: {name}: {record['serverErrorCode']}")
                continue
            for field, _ in FIELDS:
                value = (record.get("fields") or {}).get(field, {}).get("value") or {}
                host = urllib.parse.urlsplit(value.get("downloadURL", "")).hostname or "-"
                log(f"lookup: {name} {field} size={value.get('size', '-')} downloadURL-host={host}")
        return 0
    totals = {"uploaded": 0, "skipped_existing": 0, "missing_files": 0, "failed": 0}
    log(f"media-upload: {len(ids)} folders -> {CONTAINER} ({args.env}, public)")

    processed = 0
    next_report = PROGRESS_EVERY
    for start in range(0, len(ids), BATCH):
        batch = ids[start : start + BATCH]
        try:
            process_batch(client, args.media_dir, batch, totals)
        except ApiError as err:
            totals["failed"] += len(batch)
            log_error(f"failed batch starting at {batch[0]}: {err}")
            if "HTTP 401" in str(err) or "HTTP 403" in str(err):
                # A rejected key fails every batch the same way; stop instead of repeating it 50 times.
                log_error("media-upload: the server rejected the key; stopping")
                return 1
        processed += len(batch)
        while processed >= next_report:
            log(f"media-upload: {next_report}/{len(ids)} processed ({totals['uploaded']} uploaded)")
            next_report += PROGRESS_EVERY

    log(
        "media-upload: done. "
        f"uploaded={totals['uploaded']} skipped-existing={totals['skipped_existing']} "
        f"missing-files={totals['missing_files']} failed={totals['failed']}"
    )
    return 1 if totals["failed"] else 0


if __name__ == "__main__":
    sys.exit(main())
