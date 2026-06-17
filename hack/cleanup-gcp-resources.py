#!/usr/bin/env python3
"""
GCP CI Resource Cleanup

Deletes GCP resources created by OpenShift CI jobs (ci-op prefix) that are
older than --max-age-hours (default: 6). Follows the dependency order
required to avoid deletion failures.

Deletion sequence:
   1. ForwardingRule (global + regional)   — must precede TargetTcpProxy
   2. TargetTcpProxy                       — global only (OpenShift IPI)
   3. BackendService (global + regional)   — after TCP proxy is released
   4. HealthCheck (global + regional)
   5. Address (global + regional)          — freed after ForwardingRule is gone
   6. DNS ManagedZone  (non-NS/SOA record sets first, then the zone)
   7. Storage Buckets
   8. FirewallRule
   9. ManagedInstanceGroup (zonal + regional) — auto-deletes worker instances
  10. ComputeInstance (zonal)              — master, bastion, remaining workers
  11. Disk (zonal + regional)             — orphaned boot disks
  12. InstanceTemplate (global)           — worker templates
  13. UnmanagedInstanceGroup (zonal)      — master groups, now empty
  14. Router (regional)                   — Cloud NAT must go before Subnetwork
  15. Subnetwork (regional)
  16. Network (global)
  17. IAM ServiceAccount  (age proxy: oldest user-managed key creation time)

Usage:
  # See what would be deleted without touching anything
  python3 hack/cleanup-gcp-resources.py --project openshift-observability --dry-run

  # Live run
  python3 hack/cleanup-gcp-resources.py --project openshift-observability

  # Adjust age threshold and enable verbose output
  python3 hack/cleanup-gcp-resources.py --project openshift-observability --max-age-hours 4 --debug

Environment (for CI / non-interactive use):
  GOOGLE_APPLICATION_CREDENTIALS  Path to a GCP service-account JSON key file.
  GCP_PROJECT                     Project ID (overrides --project when set).
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import subprocess
import sys
from datetime import datetime, timedelta, timezone

CI_NAME_PREFIX = "ci-op"
DEFAULT_MAX_AGE_HOURS = 6

# Phrases that gcloud emits when a resource no longer exists.  These races are
# normal in a shared CI environment where CI jobs clean up their own resources
# concurrently.  We treat them as warnings, not errors.
_NOT_FOUND_PHRASES = frozenset([
    "was not found",
    "does not exist",
    "resource not found",
])

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%SZ",
)
log = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Low-level helpers
# ---------------------------------------------------------------------------

def _run(cmd: list[str]) -> tuple[str, str, int]:
    """Run *cmd* and return (stdout, stderr, returncode). Never raises."""
    log.debug("+ %s", " ".join(cmd))
    try:
        result = subprocess.run(cmd, capture_output=True, text=True)
    except FileNotFoundError:
        log.error("Command not found: %s — is gcloud installed and on PATH?", cmd[0])
        return "", "", 127
    if result.returncode != 0:
        log.debug("stderr: %s", result.stderr.strip())
    return result.stdout.strip(), result.stderr.strip(), result.returncode


def gcloud_list(*args, project: str, fmt: str = "json") -> list[dict]:
    """Run a `gcloud … list` command and return the parsed JSON array.

    *fmt* defaults to ``json`` but can be overridden with a gcloud format
    projection (e.g. ``json(name,timeCreated)``) to request specific fields
    that are not included in the default output.
    """
    cmd = ["gcloud", *args, f"--format={fmt}", "--quiet", "--project", project]
    stdout, _stderr, rc = _run(cmd)
    if rc != 0:
        msg = _stderr.splitlines()[0] if _stderr else "(no output)"
        log.error("gcloud list failed (rc=%d): %s", rc, msg)
        raise RuntimeError(f"gcloud list (rc={rc}): {msg}")
    if not stdout:
        return []
    try:
        return json.loads(stdout)
    except json.JSONDecodeError as exc:
        log.debug("JSON parse error from gcloud: %s", exc)
        return []


def url_last_segment(url: str) -> str:
    """Return the last path component of a GCP resource URL (e.g. zone, region)."""
    return url.split("/")[-1] if url else ""


def parse_timestamp(value: str | None) -> datetime | None:
    """Parse an RFC-3339 / ISO-8601 timestamp into a UTC-aware datetime."""
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except (ValueError, TypeError):
        return None


def is_older_than(timestamp_str: str | None, hours: int) -> bool:
    """
    Return True when the resource is older than *hours*.
    Resources with unparseable timestamps are skipped (treated as new).
    """
    ts = parse_timestamp(timestamp_str)
    if ts is None:
        log.warning("Unable to parse timestamp %r; treating as new (skipped)", timestamp_str)
        return False
    return datetime.now(timezone.utc) - ts > timedelta(hours=hours)


def is_ci_resource(name: str) -> bool:
    return name.startswith(CI_NAME_PREFIX)


# ---------------------------------------------------------------------------
# Cleaner
# ---------------------------------------------------------------------------

class GCPCleaner:
    def __init__(self, project: str, dry_run: bool, max_age_hours: int) -> None:
        self.project = project
        self.dry_run = dry_run
        self.max_age_hours = max_age_hours
        self.deleted = 0
        self.skipped = 0
        self.warnings = 0
        self.errors = 0

    # -- stage runner --------------------------------------------------------

    def _run_clean(self, fn) -> None:
        """Run a clean_* stage; catch list-API failures and record them as errors."""
        try:
            fn()
        except RuntimeError as exc:
            log.error("List operation failed, stage aborted: %s", exc)
            self.errors += 1

    # -- eligibility ---------------------------------------------------------

    def _eligible(self, name: str, timestamp_str: str | None) -> bool:
        """Return True when this resource should be targeted for deletion."""
        if not is_ci_resource(name):
            log.debug("Skip %-55s  (not a CI resource)", name)
            self.skipped += 1
            return False
        if not is_older_than(timestamp_str, self.max_age_hours):
            log.info("Skip %-55s  (newer than %dh)", name, self.max_age_hours)
            self.skipped += 1
            return False
        return True

    # -- deletion ------------------------------------------------------------

    def _delete(self, label: str, cmd: list[str], include_project: bool = True) -> bool:
        """
        Execute *cmd* (or simulate it when dry_run is set).
        *cmd* must NOT include --quiet or --project; those are appended here.
        Pass include_project=False for commands (e.g. gcloud storage rm) that
        do not accept the --project flag.
        """
        full_cmd = [*cmd, "--quiet", *(["--project", self.project] if include_project else [])]
        if self.dry_run:
            log.info("[DRY-RUN] Would delete %s", label)
            self.deleted += 1
            return True
        log.info("Deleting %s", label)
        _, stderr, rc = _run(full_cmd)
        if rc != 0:
            stderr_lower = stderr.lower()
            if any(phrase in stderr_lower for phrase in _NOT_FOUND_PHRASES):
                # Resource was already deleted (by CI cleanup or a concurrent run).
                # This is normal in a shared environment — treat as a benign warning.
                log.warning("Already gone %s (resource not found — likely cleaned by CI)", label)
                self.warnings += 1
                return True
            excerpt = stderr[:300].replace("\n", " | ") if stderr else "(no message)"
            log.error("FAILED to delete %s: %s", label, excerpt)
            self.errors += 1
            return False
        self.deleted += 1
        return True

    # -- resource handlers (called in dependency order) ----------------------

    def clean_forwarding_rules(self) -> None:
        log.info("=== ForwardingRule (global) ===")
        for item in gcloud_list("compute", "forwarding-rules", "list", "--global",
                                project=self.project):
            name = item.get("name", "")
            if self._eligible(name, item.get("creationTimestamp")):
                self._delete(
                    f"ForwardingRule/global/{name}",
                    ["gcloud", "compute", "forwarding-rules", "delete", name, "--global"],
                )

        log.info("=== ForwardingRule (regional) ===")
        for item in gcloud_list("compute", "forwarding-rules", "list", project=self.project):
            if item.get("region") is None:
                continue
            name = item.get("name", "")
            region = url_last_segment(item.get("region", ""))
            if not region:
                log.warning("ForwardingRule %s has no region, skipping", name)
                continue
            if self._eligible(name, item.get("creationTimestamp")):
                self._delete(
                    f"ForwardingRule/{region}/{name}",
                    ["gcloud", "compute", "forwarding-rules", "delete", name, "--region", region],
                )

    def clean_target_tcp_proxies(self) -> None:
        log.info("=== TargetTcpProxy ===")
        for item in gcloud_list("compute", "target-tcp-proxies", "list", project=self.project):
            name = item.get("name", "")
            if self._eligible(name, item.get("creationTimestamp")):
                self._delete(
                    f"TargetTcpProxy/{name}",
                    ["gcloud", "compute", "target-tcp-proxies", "delete", name],
                )

    def clean_backend_services(self) -> None:
        # Global backend services (most CI-created LBs use global)
        log.info("=== BackendService (global) ===")
        for item in gcloud_list("compute", "backend-services", "list", "--global", project=self.project):
            name = item.get("name", "")
            if self._eligible(name, item.get("creationTimestamp")):
                self._delete(
                    f"BackendService/global/{name}",
                    ["gcloud", "compute", "backend-services", "delete", name, "--global"],
                )

        # Regional backend services (internal LBs land here)
        log.info("=== BackendService (regional) ===")
        for item in gcloud_list("compute", "backend-services", "list", project=self.project):
            # gcloud returns both global and regional without --global; skip any already handled globally
            if item.get("region") is None:
                continue
            name = item.get("name", "")
            region = url_last_segment(item.get("region", ""))
            if not region:
                log.warning("BackendService %s has no region, skipping", name)
                continue
            if self._eligible(name, item.get("creationTimestamp")):
                self._delete(
                    f"BackendService/{region}/{name}",
                    ["gcloud", "compute", "backend-services", "delete", name, "--region", region],
                )

    def clean_health_checks(self) -> None:
        log.info("=== HealthCheck ===")
        for item in gcloud_list("compute", "health-checks", "list", project=self.project):
            name = item.get("name", "")
            if self._eligible(name, item.get("creationTimestamp")):
                self._delete(
                    f"HealthCheck/{name}",
                    ["gcloud", "compute", "health-checks", "delete", name],
                )

    def clean_addresses(self) -> None:
        log.info("=== Address (global) ===")
        for item in gcloud_list("compute", "addresses", "list", "--global",
                                project=self.project):
            name = item.get("name", "")
            if self._eligible(name, item.get("creationTimestamp")):
                self._delete(
                    f"Address/global/{name}",
                    ["gcloud", "compute", "addresses", "delete", name, "--global"],
                )

        log.info("=== Address (regional) ===")
        for item in gcloud_list("compute", "addresses", "list", project=self.project):
            if item.get("region") is None:
                continue
            name = item.get("name", "")
            region = url_last_segment(item.get("region", ""))
            if not region:
                log.warning("Address %s has no region, skipping", name)
                continue
            if self._eligible(name, item.get("creationTimestamp")):
                self._delete(
                    f"Address/{region}/{name}",
                    ["gcloud", "compute", "addresses", "delete", name, "--region", region],
                )

    def clean_dns_zones(self) -> None:
        log.info("=== DNS ManagedZone ===")
        for zone in gcloud_list("dns", "managed-zones", "list", project=self.project):
            name = zone.get("name", "")
            if not self._eligible(name, zone.get("creationTime")):
                continue
            # Record sets must be fully removed before the zone can be deleted.
            # Only proceed with zone deletion when all records were cleaned up.
            records_ok = self._delete_dns_records(name)
            if records_ok:
                self._delete(
                    f"ManagedZone/{name}",
                    ["gcloud", "dns", "managed-zones", "delete", name],
                )
            else:
                log.warning("Skipping zone deletion for %s — some record sets could not be removed", name)

    def _delete_dns_records(self, zone: str) -> bool:
        """Delete all non-NS/SOA records from *zone*. Returns True when all succeeded."""
        try:
            records = gcloud_list("dns", "record-sets", "list", "--zone", zone, project=self.project)
        except RuntimeError as exc:
            log.error("Failed to list DNS records for zone %s: %s", zone, exc)
            self.errors += 1
            return False
        all_ok = True
        for record in records:
            rtype = record.get("type", "")
            if rtype in ("NS", "SOA"):
                continue
            rname = record.get("name", "")
            ok = self._delete(
                f"DNSRecord/{zone}/{rtype}/{rname}",
                ["gcloud", "dns", "record-sets", "delete", rname, "--zone", zone, "--type", rtype],
            )
            if not ok:
                all_ok = False
        return all_ok

    def clean_storage_buckets(self) -> None:
        log.info("=== Storage Bucket ===")
        # gcloud storage uses snake_case: creation_time, NOT timeCreated.
        # Request it explicitly since it is absent from the default projection.
        items = gcloud_list(
            "storage", "buckets", "list",
            project=self.project,
            fmt="json(name,creation_time)",
        )
        for item in items:
            # Strip gs:// prefix defensively; modern gcloud returns bare names.
            name = item.get("name", "").removeprefix("gs://")
            ts = item.get("creation_time")
            if not self._eligible(name, ts):
                continue
            # gcloud storage rm does not accept --project; pass include_project=False.
            self._delete(
                f"Bucket/{name}",
                ["gcloud", "storage", "rm", "--recursive", f"gs://{name}"],
                include_project=False,
            )

    def clean_firewall_rules(self) -> None:
        log.info("=== FirewallRule ===")
        for item in gcloud_list("compute", "firewall-rules", "list", project=self.project):
            name = item.get("name", "")
            if self._eligible(name, item.get("creationTimestamp")):
                self._delete(
                    f"FirewallRule/{name}",
                    ["gcloud", "compute", "firewall-rules", "delete", name],
                )

    def clean_managed_instance_groups(self) -> None:
        log.info("=== InstanceGroup (managed) ===")
        for item in gcloud_list("compute", "instance-groups", "managed", "list",
                                project=self.project):
            name = item.get("name", "")
            zone = url_last_segment(item.get("zone", ""))
            region = url_last_segment(item.get("region", ""))
            if zone:
                scope_flag = ["--zone", zone]
                label = f"ManagedInstanceGroup/{zone}/{name}"
            elif region:
                scope_flag = ["--region", region]
                label = f"ManagedInstanceGroup/{region}/{name}"
            else:
                log.warning("ManagedInstanceGroup %s has no zone or region, skipping", name)
                continue
            if self._eligible(name, item.get("creationTimestamp")):
                self._delete(
                    label,
                    ["gcloud", "compute", "instance-groups", "managed", "delete",
                     name, *scope_flag],
                )

    def clean_compute_instances(self) -> None:
        log.info("=== ComputeInstance ===")
        for item in gcloud_list("compute", "instances", "list", project=self.project):
            name = item.get("name", "")
            zone = url_last_segment(item.get("zone", ""))
            if not zone:
                log.warning("ComputeInstance %s has no zone, skipping", name)
                continue
            if self._eligible(name, item.get("creationTimestamp")):
                self._delete(
                    f"ComputeInstance/{zone}/{name}",
                    ["gcloud", "compute", "instances", "delete", name, "--zone", zone],
                )

    def clean_disks(self) -> None:
        log.info("=== Disk ===")
        for item in gcloud_list("compute", "disks", "list", project=self.project):
            name = item.get("name", "")
            zone = url_last_segment(item.get("zone", ""))
            region = url_last_segment(item.get("region", ""))
            if zone:
                scope_flag = ["--zone", zone]
                label = f"Disk/{zone}/{name}"
            elif region:
                scope_flag = ["--region", region]
                label = f"Disk/{region}/{name}"
            else:
                log.warning("Disk %s has no zone or region, skipping", name)
                continue
            if self._eligible(name, item.get("creationTimestamp")):
                self._delete(
                    label,
                    ["gcloud", "compute", "disks", "delete", name, *scope_flag],
                )

    def clean_instance_templates(self) -> None:
        log.info("=== InstanceTemplate ===")
        for item in gcloud_list("compute", "instance-templates", "list",
                                project=self.project):
            name = item.get("name", "")
            if self._eligible(name, item.get("creationTimestamp")):
                self._delete(
                    f"InstanceTemplate/{name}",
                    ["gcloud", "compute", "instance-templates", "delete", name],
                )

    def clean_unmanaged_instance_groups(self) -> None:
        log.info("=== InstanceGroup (unmanaged) ===")
        for item in gcloud_list("compute", "instance-groups", "unmanaged", "list",
                                project=self.project):
            name = item.get("name", "")
            zone = url_last_segment(item.get("zone", ""))
            if not zone:
                log.warning("UnmanagedInstanceGroup %s has no zone, skipping", name)
                continue
            if self._eligible(name, item.get("creationTimestamp")):
                self._delete(
                    f"UnmanagedInstanceGroup/{zone}/{name}",
                    ["gcloud", "compute", "instance-groups", "unmanaged", "delete",
                     name, "--zone", zone],
                )

    def clean_subnetworks(self) -> None:
        log.info("=== Subnetwork ===")
        for item in gcloud_list("compute", "networks", "subnets", "list", project=self.project):
            name = item.get("name", "")
            region = url_last_segment(item.get("region", ""))
            if not region:
                log.warning("Subnetwork %s has no region, skipping", name)
                continue
            if self._eligible(name, item.get("creationTimestamp")):
                self._delete(
                    f"Subnetwork/{region}/{name}",
                    ["gcloud", "compute", "networks", "subnets", "delete", name, "--region", region],
                )

    def clean_routers(self) -> None:
        log.info("=== Router ===")
        for item in gcloud_list("compute", "routers", "list", project=self.project):
            name = item.get("name", "")
            region = url_last_segment(item.get("region", ""))
            if not region:
                log.warning("Router %s has no region, skipping", name)
                continue
            if self._eligible(name, item.get("creationTimestamp")):
                self._delete(
                    f"Router/{region}/{name}",
                    ["gcloud", "compute", "routers", "delete", name, "--region", region],
                )

    def clean_networks(self) -> None:
        log.info("=== Network ===")
        for item in gcloud_list("compute", "networks", "list", project=self.project):
            name = item.get("name", "")
            if name == "default":
                log.debug("Skip default network (never deleted)")
                continue
            if self._eligible(name, item.get("creationTimestamp")):
                self._delete(
                    f"Network/{name}",
                    ["gcloud", "compute", "networks", "delete", name],
                )

    def clean_service_accounts(self) -> None:
        log.info("=== IAM ServiceAccount ===")
        # Pre-filter at the API level to avoid fetching keys for every account.
        accounts = gcloud_list(
            "iam", "service-accounts", "list",
            f"--filter=email:{CI_NAME_PREFIX}*",
            project=self.project,
        )
        for item in accounts:
            email = item.get("email", "")
            if not is_ci_resource(email):
                # Defense-in-depth: API filter uses a prefix glob; Python check
                # ensures we never act on a non-CI account if the glob misfires.
                continue
            ts = self._oldest_sa_key_time(email)
            if ts is None:
                # Compute-node SAs (worker/master) authenticate via GCE instance
                # metadata — they never have user-managed keys. We cannot
                # distinguish an orphaned compute SA from one belonging to an
                # active cluster without a creation timestamp, so we skip these
                # rather than risk deleting credentials for a live cluster.
                log.info("Skip %-55s  (no user-managed keys — compute SA, skipping)", email)
                self.skipped += 1
                continue
            if not is_older_than(ts, self.max_age_hours):
                log.info("Skip %-55s  (newer than %dh)", email, self.max_age_hours)
                self.skipped += 1
                continue
            self._delete(
                f"ServiceAccount/{email}",
                ["gcloud", "iam", "service-accounts", "delete", email],
            )

    def _oldest_sa_key_time(self, email: str) -> str | None:
        """Return the creation timestamp of the oldest user-managed key for *email*.

        Returns None when no user-managed keys exist. The caller skips such
        accounts: compute-node SAs (worker/master) authenticate via GCE instance
        metadata and never have user-managed keys, so absence of keys does not
        mean the account is unused or orphaned.

        Limitation: if an old SA has had all of its keys rotated to new ones,
        the oldest remaining key will appear recent and the SA will be skipped
        until the new key ages past the threshold.
        """
        try:
            keys = gcloud_list(
                "iam", "service-accounts", "keys", "list",
                "--iam-account", email, "--managed-by=user",
                project=self.project,
            )
        except RuntimeError as exc:
            log.error("Failed to list keys for SA %s: %s", email, exc)
            self.errors += 1
            return None
        if not keys:
            return None
        times = [k.get("validAfterTime") for k in keys if k.get("validAfterTime")]
        parsed = [parse_timestamp(t) for t in times if t]
        valid = [t for t in parsed if t is not None]
        if not valid:
            return None
        return min(valid).isoformat()

    # -- entry point ---------------------------------------------------------

    def run(self) -> bool:
        log.info(
            "Starting cleanup  project=%s  dry_run=%s  max_age=%dh",
            self.project, self.dry_run, self.max_age_hours,
        )

        # Dependency-ordered: each group must finish before the next starts.
        # _run_clean catches RuntimeError from gcloud list failures so one bad
        # stage does not abort subsequent independent stages.
        self._run_clean(self.clean_forwarding_rules)           # before TargetTcpProxy
        self._run_clean(self.clean_target_tcp_proxies)
        self._run_clean(self.clean_backend_services)
        self._run_clean(self.clean_health_checks)
        self._run_clean(self.clean_addresses)                  # after ForwardingRule releases IPs
        self._run_clean(self.clean_dns_zones)
        self._run_clean(self.clean_storage_buckets)
        self._run_clean(self.clean_firewall_rules)
        self._run_clean(self.clean_managed_instance_groups)    # auto-deletes worker instances
        self._run_clean(self.clean_compute_instances)          # master, bastion, remaining workers
        self._run_clean(self.clean_disks)                      # orphaned boot disks
        self._run_clean(self.clean_instance_templates)         # worker templates
        self._run_clean(self.clean_unmanaged_instance_groups)  # master groups, now empty
        self._run_clean(self.clean_routers)                    # Cloud NAT must precede Subnetwork
        self._run_clean(self.clean_subnetworks)
        self._run_clean(self.clean_networks)
        self._run_clean(self.clean_service_accounts)

        log.info(
            "Done — deleted=%d  skipped=%d  warnings=%d  errors=%d",
            self.deleted, self.skipped, self.warnings, self.errors,
        )
        return self.errors == 0


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--project",
        default=os.environ.get("GCP_PROJECT", ""),
        help="GCP project ID (or set GCP_PROJECT env var). Default: %(default)r",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print what would be deleted without making any changes.",
    )
    parser.add_argument(
        "--max-age-hours",
        type=int,
        default=DEFAULT_MAX_AGE_HOURS,
        metavar="N",
        help="Skip resources newer than N hours (must be ≥ 1). Default: %(default)s",
    )
    parser.add_argument(
        "--debug",
        action="store_true",
        help="Enable DEBUG-level logging (prints every gcloud command).",
    )
    args = parser.parse_args()

    if args.debug:
        logging.getLogger().setLevel(logging.DEBUG)

    if not args.project:
        parser.error("--project is required (or set the GCP_PROJECT environment variable)")
    if args.max_age_hours < 1:
        parser.error("--max-age-hours must be at least 1 (got %d)" % args.max_age_hours)

    cleaner = GCPCleaner(args.project, args.dry_run, args.max_age_hours)
    sys.exit(0 if cleaner.run() else 1)


if __name__ == "__main__":
    main()
