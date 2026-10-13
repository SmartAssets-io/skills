#!/usr/bin/env python3
"""Content-bound CbC records and independently signed maintainer acceptance."""

import hashlib
import json
import os
import re
from pathlib import Path
import subprocess
import sys
import tempfile
import uuid
from datetime import datetime
from typing import Any


def parse_json(text: str) -> Any:
    try:
        return json.loads(text)
    except (ValueError, TypeError) as error:
        raise ValueError("invalid CbC JSON") from error


def canonical(value: Any) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], stderr=subprocess.DEVNULL).decode().strip()


def artifact_path(value: str) -> str:
    root = Path(git("rev-parse", "--show-toplevel")).resolve()
    path = Path(os.path.abspath(value))
    if not path.resolve(strict=True).is_relative_to(root):
        raise ValueError("artifact or claim resolves outside the repository")
    return path.relative_to(root).as_posix()


def snapshot(artifact: str, claim_file: str) -> dict[str, Any]:
    path = artifact_path(artifact)
    claim = None
    if claim_file:
        claim = {"path": artifact_path(claim_file),
                 "sha256": digest(Path(claim_file).read_bytes())}
    return {"artifact": path, "source_sha256": digest(Path(artifact).read_bytes()),
            "claim": claim}


def archive(path: Path) -> None:
    """Copy old bytes into content-addressed history without changing the original."""
    if not path.exists():
        return
    archive_bytes(path, path.read_bytes())


def archive_bytes(path: Path, data: bytes) -> None:
    target = path.parent / "history" / (digest(data) + "-" + path.name)
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        if target.read_bytes() != data:
            raise ValueError("history collision")
    else:
        with target.open("xb") as stream:
            stream.write(data)


def replace(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    archive(path)
    archive_bytes(path, data)
    fd, tmp = tempfile.mkstemp(dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def read_record(ledger: Path) -> dict[str, Any]:
    text = ledger.read_text()
    blocks = re.findall(r"^```json\n(.*?)^```[ \t]*$", text, re.MULTILINE | re.DOTALL)
    if len(blocks) != 1:
        raise ValueError("expected one evidence record")
    record = parse_json(blocks[0])
    if not isinstance(record, dict):
        raise ValueError("invalid evidence record")
    return record


def evidence_files(record: dict[str, Any]) -> dict[str, str]:
    ref = record.get("evidence", {}).get("ref")
    if isinstance(ref, str) and Path(ref).is_file():
        return {ref: digest(Path(ref).read_bytes())}
    # Adapter labels such as 'mock' and 'z3' are not file references.
    if isinstance(ref, str) and ("/" in ref or ref.endswith(".json")):
        raise ValueError("referenced evidence is unavailable")
    return {}


def record_write(artifact: str, ledger: Path, claim_file: str, inputs: str) -> None:
    record = parse_json(sys.stdin.read())
    current = snapshot(artifact, claim_file)
    if inputs and parse_json(inputs) != current:
        raise ValueError("source or claim changed during verification")
    record["artifact"]["path"] = current["artifact"]
    record["verification_id"] = str(uuid.uuid4())
    record["inputs"] = current
    record["evidence_files"] = evidence_files(record)
    # Archive referenced reports as well as the ledger before a later run.
    archive(ledger)
    if ledger.exists():
        try:
            old = read_record(ledger)
        except ValueError:
            old = {}  # The historical bytes remain archived, even for legacy prose.
        for ref in old.get("evidence_files", {}):
            archive(Path(ref))
    quote = "\n".join("> " + line for line in (record.get("claim") or "(none)").splitlines())
    text = (f"# CbC Evidence: {artifact}\n\n"
            f"- **Status:** {record['status']}\n"
            f"- **Adapter:** {record['adapter']}\n"
            f"- **Commit:** {record['artifact']['commit']}\n"
            f"- **Verified:** {record['verified_at']}\n\n"
            "Claim:\n\n" + quote + "\n\n"
            "```json\n" + json.dumps(record, indent=2) + "\n```\n")
    replace(ledger, text.encode())
    print(ledger)


def binding(artifact: str, ledger: Path) -> dict[str, Any]:
    record = read_record(ledger)
    path = artifact_path(artifact)
    if record.get("status") not in ("discharged", "waived"):
        raise ValueError("verification is not discharged or waived")
    if record.get("artifact", {}).get("path") != path:
        raise ValueError("evidence belongs to another artifact")
    inputs = record.get("inputs")
    if not isinstance(inputs, dict):
        raise ValueError("historical record requires current verification")
    claim = inputs.get("claim")
    root = Path(git("rev-parse", "--show-toplevel"))
    current = snapshot(artifact, str(root / claim["path"]) if claim else "")
    if current != inputs:
        raise ValueError("source or claim is stale")
    if evidence_files(record) != record.get("evidence_files"):
        raise ValueError("referenced evidence is stale")
    # Hash the entire ledger, including claim text and verifier metadata.
    return {"artifact": path, "source_sha256": inputs["source_sha256"],
            "claim": claim or {"path": None, "sha256": digest(canonical(record.get("claim", "")))},
            "evidence_sha256": digest(ledger.read_bytes())}


def validate(artifact: str, ledger: Path, approval: str, signature: str) -> None:
    payload = parse_json(approval)
    expected = binding(artifact, ledger)
    if not isinstance(payload, dict) or payload.get("schema") != "cbc-acceptance/v1":
        raise ValueError("invalid acceptance schema")
    for key, value in expected.items():
        if payload.get(key) != value:
            raise ValueError(f"acceptance binding mismatch: {key}")
    for key in ("accepted_by", "approved_at", "approval_ref"):
        if not isinstance(payload.get(key), str) or not payload[key].strip():
            raise ValueError(f"missing approval field: {key}")
    if any(char.isspace() or char in "*?![],\\\\" for char in payload["accepted_by"]):
        raise ValueError("maintainer identity must be a literal SSH principal")
    stamp = datetime.fromisoformat(payload["approved_at"].replace("Z", "+00:00"))
    if stamp.tzinfo is None:
        raise ValueError("approval time requires a timezone")
    trust = Path(git("config", "--local", "--get", "cbc.acceptanceAllowedSigners"))
    root = Path(git("rev-parse", "--show-toplevel")).resolve()
    if not trust.is_absolute() or trust.resolve().is_relative_to(root):
        raise ValueError("allowed signers must be an absolute path outside the worktree")
    # Only explicit identities authorize acceptance. Wildcards are insufficient.
    entries = [line for line in trust.read_text().splitlines()
               if line.strip() and not line.lstrip().startswith("#")
               and payload["accepted_by"] in line.split()[0].split(",")]
    if not entries:
        raise ValueError("maintainer identity is not explicitly authorized")
    with tempfile.TemporaryDirectory() as tmp:
        allowed = Path(tmp) / "allowed-signers"
        allowed.write_text("\n".join(entries) + "\n")
        sig = Path(tmp) / "approval.sig"
        sig.write_text(signature)
        result = subprocess.run(
            ["ssh-keygen", "-Y", "verify", "-f", str(allowed), "-I", payload["accepted_by"],
             "-n", "cbc-acceptance", "-s", str(sig)],
            input=approval.encode(), stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        if result.returncode:
            raise ValueError("approval signature is not authorized")


def main() -> None:
    action, artifact, *args = sys.argv[1:]
    if action == "snapshot":
        print(json.dumps(snapshot(artifact, args[0])))
        return
    ledger = Path(args[0])
    acceptance = ledger.with_suffix(".acceptance.json")
    if action == "record":
        record_write(artifact, ledger, args[1], args[2])
    elif action == "payload":
        payload = {"schema": "cbc-acceptance/v1", **binding(artifact, ledger),
                   "accepted_by": "", "approved_at": "", "approval_ref": ""}
        print(json.dumps(payload, indent=2))
    elif action == "accept":
        approval = Path(args[1]).read_bytes().decode("utf-8")
        signature = Path(args[2]).read_text()
        validate(artifact, ledger, approval, signature)
        replace(acceptance, canonical({"approval": approval, "signature": signature}) + b"\n")
        print(f"cbc accept: {artifact} -> accepted")
    elif action == "check":
        envelope = parse_json(acceptance.read_text())
        validate(artifact, ledger, envelope["approval"], envelope["signature"])
    else:
        raise ValueError("unknown acceptance action")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, TypeError, IndexError, AttributeError,
            subprocess.SubprocessError) as error:
        print(f"cbc acceptance: {error}", file=sys.stderr)
        sys.exit(4)
