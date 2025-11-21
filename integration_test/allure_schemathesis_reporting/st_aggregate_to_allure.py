#!/usr/bin/env python3
import argparse
import json
import os
import re
import sys
import time
import uuid
import xml.etree.ElementTree as ET

METHODS = r"(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)"


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--junit", required=True)
    p.add_argument("--har", default="")
    p.add_argument("--schema", default="")
    p.add_argument("--base-url", dest="base_url", default="")
    p.add_argument("--out", required=True, help="allure-results output dir")
    return p.parse_args()


def redacted(s: str) -> str:
    s = re.sub(r'(Authorization"\s*:\s*"Bearer\s*)[^"]+', r"\1***REDACTED***", s)
    s = re.sub(r'(Authorization:\s*Bearer\s*)[\w\.-_]+', r"\1***REDACTED***", s)
    return s


def load_har(har_path):
    if not har_path or not os.path.isfile(har_path):
        return None
    try:
        with open(har_path, "r", encoding="utf-8", errors="ignore") as f:
            return json.loads(f.read())
    except Exception:
        return None


def filter_har(har_obj, method, path):
    if not har_obj:
        return None
    out = {"log": {"version": "1.2", "creator": {"name": "filter", "version": "1"}, "entries": []}}
    for e in har_obj.get("log", {}).get("entries", []):
        req = e.get("request", {})
        m = req.get("method", "")
        url = req.get("url", "")
        if m.upper() == method and path in url:
            out["log"]["entries"].append(e)
    return out


def extract_group_key(name, classname, failure_text):
    merged = " ".join([name or "", classname or "", failure_text or ""])  # type: ignore[arg-type]
    m = re.search(r"operationId[=\s:\"]+([\w\.-]+)", merged)
    if m:
        return ("OPID", m.group(1))

    for src in (name, classname):
        m = re.match(rf"^{METHODS}\s+([^\s]+)", src or "", re.I)
        if m:
            return ("PATH", f"{m.group(1).upper()} {m.group(2)}")

    return ("RAW", name or classname or "unknown")


def load_severity_config():
    env_path = os.environ.get("SCHEMATHESIS_SEVERITY_CONFIG") or os.environ.get("ST_SEVERITY_CONFIG")
    if env_path and os.path.isfile(env_path):
        path = env_path
    else:
        path = os.path.join(os.path.dirname(__file__), "schemathesis_severity.json")

    default = "normal"
    rules = []
    try:
        if os.path.isfile(path):
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)
            default = data.get("default_severity", default)
            rules = data.get("rules", [])
    except Exception:
        # If config is invalid, fall back to built-in defaults
        pass

    return {"default": default, "rules": rules}


def match_condition(when, operation_id, method, path):
    if not when:
        return True

    op_id_cond = when.get("operation_id")
    if op_id_cond is not None:
        if not operation_id or operation_id != op_id_cond:
            return False

    method_cond = when.get("method")
    if method_cond is not None:
        if not method or method.upper() != method_cond.upper():
            return False

    path_cond = when.get("path")
    if path_cond is not None:
        if not path or path != path_cond:
            return False

    path_re = when.get("path_regex")
    if path_re is not None:
        if not path or not re.match(path_re, path):
            return False

    # We currently don't have tags in the aggregated data; rules depending on tags won't match.
    if "tag" in when:
        return False

    return True


def resolve_severity(config, group_type, group_key, operation_id, method, path):
    default = config.get("default", "normal")
    rules = config.get("rules", [])

    for rule in rules:
        when = rule.get("when", {})
        if match_condition(when, operation_id, method, path):
            sev = rule.get("severity", default)
            if sev in ("critical", "normal", "low"):
                return sev
            return default

    return default


def read_junit(junit_path):
    root = ET.parse(junit_path).getroot()
    if root.tag.endswith("testsuite"):
        suites = [root]
    else:
        suites = [c for c in root if c.tag.endswith("testsuite")]
    cases = []
    for ts in suites:
        for tc in ts.findall(".//testcase"):
            name = tc.attrib.get("name", "")
            classname = tc.attrib.get("classname", "")
            fail = tc.find("failure")
            err = tc.find("error")
            status = "passed"
            message = ""
            if fail is not None:
                status = "failed"
                message = (fail.attrib.get("message", "") or "") + "\n" + (fail.text or "")
            elif err is not None:
                status = "failed"
                message = (err.attrib.get("message", "") or "") + "\n" + (err.text or "")
            cases.append({"name": name, "classname": classname, "status": status, "message": message})
    return cases


def main():
    a = parse_args()
    os.makedirs(a.out, exist_ok=True)
    cases = read_junit(a.junit)
    har_obj = load_har(a.har)
    severity_cfg = load_severity_config()
    endpoint_results = []

    groups = {}
    for c in cases:
        key_type, key_val = extract_group_key(c["name"], c["classname"], c["message"])
        groups.setdefault(key_val, {"type": key_type, "items": []})
        groups[key_val]["items"].append(c)

    now_ms = int(time.time() * 1000)

    for key, data in groups.items():
        items = data["items"]
        failed = any(i["status"] == "failed" for i in items)
        group_type = data.get("type")

        method, path = (None, None)
        m = re.match(rf"^{METHODS}\s+([^\s]+)", key)
        if m:
            method = m.group(1).upper()
            path = m.group(2)

        operation_id = key if group_type == "OPID" else None
        severity = resolve_severity(severity_cfg, group_type, key, operation_id, method, path)

        fail_txt = ""
        for i in items:
            if i["status"] == "failed":
                fail_txt += f"=== {i['name']} ===\n{(i['message'] or '').strip()}\n\n"

        fail_path = None
        if fail_txt.strip():
            fail_path = os.path.join(a.out, f"failures-{uuid.uuid4().hex}.txt")
            with open(fail_path, "w", encoding="utf-8") as f:
                f.write(redacted(fail_txt))

        har_path = None
        if method and path and har_obj:
            filtered = filter_har(har_obj, method, path)
            if filtered and filtered["log"]["entries"]:
                har_path = os.path.join(a.out, f"har-{uuid.uuid4().hex}.har")
                with open(har_path, "w", encoding="utf-8") as f:
                    f.write(redacted(json.dumps(filtered, indent=2)))

        summary_obj = {
            "group": key,
            "baseUrl": a.base_url,
            "schema": a.schema,
            "counts": {
                "total": len(items),
                "failed": sum(1 for i in items if i["status"] == "failed"),
                "passed": sum(1 for i in items if i["status"] == "passed"),
            },
        }
        summary_path = os.path.join(a.out, f"summary-{uuid.uuid4().hex}.json")
        with open(summary_path, "w", encoding="utf-8") as f:
            json.dump(summary_obj, f, indent=2)

        endpoint_results.append(
            {
                "group": key,
                "severity": severity,
                "status": "failed" if failed else "passed",
                "counts": summary_obj["counts"],
            }
        )

        uid = str(uuid.uuid4())
        result = {
            "uuid": uid,
            "name": key,
            "fullName": key,
            "status": "failed" if failed else "passed",
            "stage": "finished",
            "start": now_ms,
            "stop": now_ms,
            "labels": [
                {"name": "suite", "value": "API Contract"},
                {"name": "feature", "value": "Endpoints"},
                {"name": "framework", "value": "schemathesis"},
                {"name": "severity", "value": severity},
            ],
            "parameters": [
                {"name": "baseUrl", "value": a.base_url},
                {"name": "schema", "value": a.schema},
                {"name": "count.total", "value": str(summary_obj["counts"]["total"])},
                {"name": "count.failed", "value": str(summary_obj["counts"]["failed"])},
                {"name": "count.passed", "value": str(summary_obj["counts"]["passed"])},
            ],
            "attachments": [
                {"name": "Summary", "type": "application/json", "source": os.path.basename(summary_path)}
            ],
        }

        if fail_path:
            result["attachments"].append(
                {
                    "name": "Failures (payloads / diffs)",
                    "type": "text/plain",
                    "source": os.path.basename(fail_path),
                }
            )
        if har_path:
            result["attachments"].append(
                {
                    "name": "HAR (filtered)",
                    "type": "application/json",
                    "source": os.path.basename(har_path),
                }
            )

        with open(os.path.join(a.out, f"{uid}-result.json"), "w", encoding="utf-8") as f:
            json.dump(result, f, indent=2)

    if endpoint_results:
        total = len(endpoint_results)
        failed_critical = [
            e for e in endpoint_results if e["status"] == "failed" and e["severity"] == "critical"
        ]
        failed_normal = [
            e for e in endpoint_results if e["status"] == "failed" and e["severity"] == "normal"
        ]
        failed_low = [
            e for e in endpoint_results if e["status"] == "failed" and e["severity"] == "low"
        ]
        total_failed = len(failed_critical) + len(failed_normal) + len(failed_low)

        health_status = "failed" if failed_critical else "passed"

        health_summary = {
            "baseUrl": a.base_url,
            "schema": a.schema,
            "endpoints": {
                "total": total,
                "failed_total": total_failed,
                "failed_critical": len(failed_critical),
                "failed_normal": len(failed_normal),
                "failed_low": len(failed_low),
                "failed_critical_list": [e["group"] for e in failed_critical],
                "details": endpoint_results,
            },
        }
        health_summary_basename = "schemathesis_summary.json"
        health_summary_path = os.path.join(a.out, health_summary_basename)
        with open(health_summary_path, "w", encoding="utf-8") as f:
            json.dump(health_summary, f, indent=2)

        health_uid = str(uuid.uuid4())
        health_result = {
            "uuid": health_uid,
            "name": "API health check (Schemathesis)",
            "fullName": "API health check (Schemathesis)",
            "status": health_status,
            "stage": "finished",
            "start": now_ms,
            "stop": now_ms,
            "labels": [
                {"name": "suite", "value": "API Health"},
                {"name": "feature", "value": "Schemathesis"},
                {"name": "framework", "value": "schemathesis"},
                {"name": "severity", "value": "critical" if failed_critical else "normal"},
            ],
            "parameters": [
                {"name": "baseUrl", "value": a.base_url},
                {"name": "schema", "value": a.schema},
                {"name": "endpoints.total", "value": str(total)},
                {"name": "endpoints.failed.total", "value": str(total_failed)},
                {"name": "endpoints.failed.critical", "value": str(len(failed_critical))},
                {"name": "endpoints.failed.normal", "value": str(len(failed_normal))},
                {"name": "endpoints.failed.low", "value": str(len(failed_low))},
            ],
            "attachments": [
                {
                    "name": "Health summary",
                    "type": "application/json",
                    "source": os.path.basename(health_summary_path),
                }
            ],
        }
        with open(os.path.join(a.out, f"{health_uid}-result.json"), "w", encoding="utf-8") as f:
            json.dump(health_result, f, indent=2)

    print(f"Wrote aggregated Allure results to: {a.out}")


if __name__ == "__main__":
    main()
