#!/usr/bin/env python3
"""
zabbix_to_es_exporter.py - Zabbix Metrics → Elasticsearch Exporter
SOC Platform Phase 2 - Data Analytics & Log Correlation Layer

Exports Zabbix host metrics to Elasticsearch for unified log + metrics dashboards.
Supports: CPU, Memory, Disk, Network, Load Average metrics.

Usage:
    python3 zabbix_to_es_exporter.py --config config.yaml
    python3 zabbix_to_es_exporter.py --config config.yaml --once
    python3 zabbix_to_es_exporter.py --config config.yaml --host web-server-01
"""

import argparse
import json
import logging
import sys
import time
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

import requests
import yaml

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)-8s %(name)s: %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S",
)
logger = logging.getLogger("zabbix-es-exporter")


# ---------------------------------------------------------------------------
# Zabbix API Client
# ---------------------------------------------------------------------------
class ZabbixClient:
    """Thin Zabbix JSON-RPC 2.0 client."""

    def __init__(self, url: str, user: str, password: str, timeout: int = 30) -> None:
        self.url = url.rstrip("/") + "/api_jsonrpc.php"
        self.user = user
        self.password = password
        self.timeout = timeout
        self.auth_token: Optional[str] = None
        self._id = 1
        self.session = requests.Session()

    def _call(self, method: str, params: Dict[str, Any]) -> Any:
        payload = {
            "jsonrpc": "2.0",
            "method": method,
            "params": params,
            "id": self._id,
        }
        if self.auth_token and method != "user.login":
            payload["auth"] = self.auth_token
        self._id += 1
        try:
            resp = self.session.post(
                self.url,
                json=payload,
                headers={"Content-Type": "application/json"},
                timeout=self.timeout,
            )
            resp.raise_for_status()
            data = resp.json()
        except requests.RequestException as exc:
            logger.error("Zabbix API request failed: %s", exc)
            raise

        if "error" in data:
            raise RuntimeError(f"Zabbix API error: {data['error']}")
        return data.get("result")

    def login(self) -> None:
        logger.info("Authenticating with Zabbix at %s", self.url)
        self.auth_token = self._call("user.login", {"user": self.user, "password": self.password})
        logger.info("Authenticated successfully.")

    def logout(self) -> None:
        if self.auth_token:
            self._call("user.logout", {})
            self.auth_token = None

    def get_hosts(self, group_names: Optional[List[str]] = None) -> List[Dict]:
        params: Dict[str, Any] = {
            "output": ["hostid", "host", "name", "status"],
            "filter": {"status": 0},  # 0 = enabled
        }
        if group_names:
            params["groupids"] = self._get_group_ids(group_names)
        return self._call("host.get", params) or []

    def _get_group_ids(self, names: List[str]) -> List[str]:
        groups = self._call("hostgroup.get", {"output": ["groupid", "name"], "filter": {"name": names}}) or []
        return [g["groupid"] for g in groups]

    def get_items(self, host_ids: List[str], key_patterns: List[str]) -> List[Dict]:
        params: Dict[str, Any] = {
            "output": ["itemid", "hostid", "key_", "name", "lastvalue", "lastclock", "value_type", "units"],
            "hostids": host_ids,
            "search": {},
            "searchWildcardsEnabled": True,
            "filter": {"status": 0},  # 0 = enabled
        }
        all_items: List[Dict] = []
        for pattern in key_patterns:
            params["search"] = {"key_": pattern}
            items = self._call("item.get", params) or []
            all_items.extend(items)
        # Deduplicate by itemid
        seen = set()
        unique = []
        for item in all_items:
            if item["itemid"] not in seen:
                seen.add(item["itemid"])
                unique.append(item)
        return unique

    def get_history(self, item_ids: List[str], value_type: int, time_from: int, time_till: int) -> List[Dict]:
        return self._call("history.get", {
            "output": "extend",
            "itemids": item_ids,
            "value_type": value_type,
            "time_from": time_from,
            "time_till": time_till,
            "limit": 10000,
            "sortfield": "clock",
            "sortorder": "ASC",
        }) or []


# ---------------------------------------------------------------------------
# Elasticsearch Client (minimal, no extra deps)
# ---------------------------------------------------------------------------
class ESClient:
    """Minimal Elasticsearch client using requests."""

    def __init__(self, url: str, user: str, password: str, timeout: int = 30) -> None:
        self.url = url.rstrip("/")
        self.auth = (user, password)
        self.timeout = timeout
        self.session = requests.Session()

    def index(self, index: str, doc: Dict) -> bool:
        try:
            resp = self.session.post(
                f"{self.url}/{index}/_doc",
                json=doc,
                auth=self.auth,
                headers={"Content-Type": "application/json"},
                timeout=self.timeout,
            )
            resp.raise_for_status()
            return True
        except requests.RequestException as exc:
            logger.error("ES index failed: %s", exc)
            return False

    def bulk(self, index: str, docs: List[Dict]) -> int:
        """Bulk index documents. Returns number of successfully indexed docs."""
        if not docs:
            return 0

        lines = []
        for doc in docs:
            meta = json.dumps({"index": {"_index": index}})
            lines.append(meta)
            lines.append(json.dumps(doc))
        body = "\n".join(lines) + "\n"

        try:
            resp = self.session.post(
                f"{self.url}/_bulk",
                data=body,
                auth=self.auth,
                headers={"Content-Type": "application/x-ndjson"},
                timeout=self.timeout,
            )
            resp.raise_for_status()
            result = resp.json()
            errors = [
                item["index"]
                for item in result.get("items", [])
                if item.get("index", {}).get("error")
            ]
            if errors:
                logger.warning("Bulk index had %d errors: %s", len(errors), errors[:3])
            return len(docs) - len(errors)
        except requests.RequestException as exc:
            logger.error("ES bulk failed: %s", exc)
            return 0

    def ensure_index_exists(self, alias: str) -> None:
        """Ensure the write alias/index exists (bootstrap if needed)."""
        try:
            resp = self.session.get(f"{self.url}/{alias}", auth=self.auth, timeout=self.timeout)
            if resp.status_code == 404:
                logger.info("Creating bootstrap index for alias: %s", alias)
                boot_index = f"{alias}-000001"
                self.session.put(
                    f"{self.url}/{boot_index}",
                    json={"aliases": {alias: {"is_write_index": True}}},
                    auth=self.auth,
                    headers={"Content-Type": "application/json"},
                    timeout=self.timeout,
                )
        except requests.RequestException as exc:
            logger.warning("Could not verify index existence: %s", exc)


# ---------------------------------------------------------------------------
# Document Builder
# ---------------------------------------------------------------------------
METRIC_FIELD_MAP = {
    # CPU
    "system.cpu.util": ("system.cpu.total.pct", 0.01),
    "system.cpu.load[percpu,avg1]": ("system.load.1", 1.0),
    "system.cpu.load[percpu,avg5]": ("system.load.5", 1.0),
    "system.cpu.load[percpu,avg15]": ("system.load.15", 1.0),
    # Memory — Zabbix reports available (free) bytes; store as-is under the correct ECS field
    "vm.memory.size[available]": ("system.memory.free", 1.0),
    "vm.memory.size[total]": ("system.memory.total", 1.0),
    # pavailable = percent of memory available (e.g., 40 means 40% free); stored as 0-1 fraction
    "vm.memory.size[pavailable]": ("system.memory.actual.free.pct", 0.01),
    # Disk
    "vfs.fs.size[/,used]": ("system.disk.used.bytes", 1.0),
    "vfs.fs.size[/,total]": ("system.disk.total", 1.0),
    "vfs.fs.size[/,pused]": ("system.disk.used.pct", 0.01),
    # Network
    "net.if.in[eth0]": ("system.network.in.bytes", 1.0),
    "net.if.out[eth0]": ("system.network.out.bytes", 1.0),
}


def build_es_document(
    item: Dict,
    history_entry: Dict,
    host_map: Dict[str, Dict],
    index_prefix: str,
) -> Dict:
    """Convert a Zabbix history entry to an ECS-aligned Elasticsearch document."""
    host_id = item["hostid"]
    host = host_map.get(host_id, {"host": "unknown", "name": "unknown"})
    clock = int(history_entry["clock"])
    ts = datetime.fromtimestamp(clock, tz=timezone.utc).isoformat()

    try:
        value = float(history_entry["value"])
    except (ValueError, KeyError):
        value = 0.0

    item_key = item.get("key_", "unknown")
    item_name = item.get("name", item_key)
    units = item.get("units", "")

    # Map to ECS-style metric field path
    field_path, multiplier = METRIC_FIELD_MAP.get(item_key, ("metric.value", 1.0))
    mapped_value = value * multiplier

    doc: Dict[str, Any] = {
        "@timestamp": ts,
        "host": {
            "name": host.get("host", "unknown"),
            "hostname": host.get("name", host.get("host", "unknown")),
            "id": host_id,
        },
        "metric": {
            "name": item_key,
            "value": value,
            "unit": units,
        },
        "zabbix": {
            "host_id": host_id,
            "item_id": item["itemid"],
            "item_key": item_key,
            "item_name": item_name,
            "value_type": item.get("value_type", "0"),
        },
        "tags": ["zabbix", "metrics", index_prefix],
    }

    # Set ECS metric field using dot notation path
    _set_nested(doc, field_path, mapped_value)

    return doc


def _set_nested(d: Dict, path: str, value: Any) -> None:
    """Set a nested dict value using dot-notation path."""
    keys = path.split(".")
    for key in keys[:-1]:
        d = d.setdefault(key, {})
    d[keys[-1]] = value


# ---------------------------------------------------------------------------
# Exporter Core
# ---------------------------------------------------------------------------
class ZabbixToESExporter:
    def __init__(self, config: Dict) -> None:
        self.config = config
        self.zabbix = ZabbixClient(
            url=config["zabbix"]["url"],
            user=config["zabbix"]["user"],
            password=config["zabbix"]["password"],
            timeout=config["zabbix"].get("timeout", 30),
        )
        self.es = ESClient(
            url=config["elasticsearch"]["url"],
            user=config["elasticsearch"].get("user", "elastic"),
            password=config["elasticsearch"].get("password", ""),
            timeout=config["elasticsearch"].get("timeout", 30),
        )
        self.index_prefix = config["elasticsearch"].get("index_prefix", "metrics-zabbix")
        self.interval = config.get("export_interval_seconds", 60)
        self.lookback_seconds = config.get("lookback_seconds", 120)
        self.batch_size = config.get("batch_size", 500)
        self.host_filter = config["zabbix"].get("host_groups", [])
        self.key_patterns = config["zabbix"].get("item_key_patterns", ["system.cpu*", "vm.memory*", "vfs.fs*", "net.if*"])

    def export_once(self, target_host: Optional[str] = None) -> int:
        """Run a single export cycle. Returns number of documents indexed."""
        self.zabbix.login()
        try:
            hosts = self.zabbix.get_hosts(self.host_filter)
            if target_host:
                hosts = [h for h in hosts if h["host"] == target_host or h["name"] == target_host]
            if not hosts:
                logger.warning("No hosts found matching filter.")
                return 0

            host_map = {h["hostid"]: h for h in hosts}
            host_ids = list(host_map.keys())
            logger.info("Exporting metrics for %d host(s).", len(host_ids))

            items = self.zabbix.get_items(host_ids, self.key_patterns)
            if not items:
                logger.warning("No items found for the configured key patterns.")
                return 0

            now = int(time.time())
            time_from = now - self.lookback_seconds

            # Separate float (0) vs unsigned int (3) items
            float_ids = [i["itemid"] for i in items if i.get("value_type") in ("0", "3")]
            history = self.zabbix.get_history(float_ids, 0, time_from, now) if float_ids else []

            # Build documents
            item_map = {i["itemid"]: i for i in items}
            docs: List[Dict] = []
            for entry in history:
                item = item_map.get(entry["itemid"])
                if not item:
                    continue
                doc = build_es_document(item, entry, host_map, self.index_prefix)
                docs.append(doc)

            if not docs:
                logger.info("No history entries in the last %ds window.", self.lookback_seconds)
                return 0

            # Bulk index in batches
            total_indexed = 0
            for i in range(0, len(docs), self.batch_size):
                batch = docs[i: i + self.batch_size]
                indexed = self.es.bulk(self.index_prefix, batch)
                total_indexed += indexed
                logger.info("Indexed batch %d/%d: %d/%d documents.", i // self.batch_size + 1,
                            -(-len(docs) // self.batch_size), indexed, len(batch))

            logger.info("Export cycle complete. Total documents indexed: %d", total_indexed)
            return total_indexed

        finally:
            self.zabbix.logout()

    def run_continuous(self, target_host: Optional[str] = None) -> None:
        """Run the exporter in a continuous loop."""
        logger.info("Starting continuous export with interval=%ds", self.interval)
        while True:
            try:
                self.export_once(target_host)
            except Exception as exc:
                logger.error("Export cycle failed: %s", exc, exc_info=True)
            time.sleep(self.interval)


# ---------------------------------------------------------------------------
# Entry Point
# ---------------------------------------------------------------------------
def load_config(path: str) -> Dict:
    with open(path) as f:
        return yaml.safe_load(f)


def main() -> None:
    parser = argparse.ArgumentParser(description="Zabbix → Elasticsearch Metrics Exporter")
    parser.add_argument("--config", required=True, help="Path to config.yaml")
    parser.add_argument("--once", action="store_true", help="Run a single export cycle and exit")
    parser.add_argument("--host", help="Export metrics for a specific host only")
    parser.add_argument("--debug", action="store_true", help="Enable debug logging")
    args = parser.parse_args()

    if args.debug:
        logging.getLogger().setLevel(logging.DEBUG)

    try:
        config = load_config(args.config)
    except Exception as exc:
        logger.error("Failed to load config: %s", exc)
        sys.exit(1)

    exporter = ZabbixToESExporter(config)

    if args.once:
        count = exporter.export_once(args.host)
        logger.info("Single export complete: %d documents indexed.", count)
    else:
        exporter.run_continuous(args.host)


if __name__ == "__main__":
    main()
