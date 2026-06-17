# hack/cleanup-gcp-resources.py

Deletes orphaned GCP resources created by OpenShift CI jobs (`ci-op` prefix) that are older than a configurable age threshold (default: 6 hours). Designed to supplement the DPP team's automated pruning, which misses certain resource types.

## Prerequisites

### 1. Python 3.9 or later

```bash
python3 --version   # must be 3.9+
```

### 2. Google Cloud SDK (`gcloud`)

Install from the [official docs](https://cloud.google.com/sdk/docs/install) or via a package manager:

```bash
# macOS
brew install google-cloud-sdk

# Verify
gcloud --version
```

### 3. Authentication

Authenticate as a user with sufficient permissions:

```bash
gcloud auth login
gcloud auth application-default login
```

Or point to a service account key file:

```bash
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json
```

### 4. GCP IAM Permissions

The principal (user or service account) running the script needs the following roles on the target project, or equivalent custom permissions:

| Role | Purpose |
|------|---------|
| `roles/compute.admin` | List and delete Compute Engine resources (instances, disks, networks, firewall rules, load balancer components, etc.) |
| `roles/dns.admin` | List and delete Cloud DNS managed zones and record sets |
| `roles/storage.admin` | List and delete Cloud Storage buckets and their contents |
| `roles/iam.serviceAccountAdmin` | List and delete IAM service accounts |
| `roles/iam.serviceAccountKeyAdmin` | List service account keys (used as a creation-time proxy) |

To verify your current permissions:

```bash
gcloud projects get-iam-policy openshift-observability \
  --flatten="bindings[].members" \
  --filter="bindings.members:$(gcloud config get-value account)"
```

### 5. Active Project

Confirm access to the target project:

```bash
gcloud projects describe openshift-observability
```

## Usage

Always run from the repository root.

```bash
# Dry run — print what would be deleted without touching anything
python3 hack/cleanup-gcp-resources.py --project openshift-observability --dry-run

# Live run with default 6-hour age threshold
python3 hack/cleanup-gcp-resources.py --project openshift-observability

# Tighten the threshold to 4 hours
python3 hack/cleanup-gcp-resources.py --project openshift-observability --max-age-hours 4

# Enable verbose output (prints every gcloud command)
python3 hack/cleanup-gcp-resources.py --project openshift-observability --debug
```

The project can also be set via an environment variable:

```bash
export GCP_PROJECT=openshift-observability
python3 hack/cleanup-gcp-resources.py --dry-run
```

## Options

| Flag | Default | Description |
|------|---------|-------------|
| `--project` | `$GCP_PROJECT` | GCP project ID (required if env var not set) |
| `--dry-run` | off | Print planned deletions without executing them |
| `--max-age-hours N` | `6` | Skip resources newer than N hours (minimum 1) |
| `--debug` | off | Enable DEBUG-level logging (every gcloud call printed) |

## Resource Types Covered

The script deletes resources in dependency order to avoid deletion failures. Each stage must complete before the next begins.

| Step | Resource type | Scope | Notes |
|------|--------------|-------|-------|
| 1 | ForwardingRule | global + regional | Must precede TargetTcpProxy |
| 2 | TargetTcpProxy | global | External API load balancer proxy |
| 3 | BackendService | global + regional | After TCP proxy is released |
| 4 | HealthCheck | global + regional | After BackendService |
| 5 | Address | global + regional | Freed after ForwardingRule is gone |
| 6 | DNS ManagedZone | global | Non-NS/SOA records deleted first |
| 7 | Storage Bucket | global | Recursive deletion of contents |
| 8 | FirewallRule | global | |
| 9 | ManagedInstanceGroup | zonal + regional | Auto-deletes its worker instances |
| 10 | ComputeInstance | zonal | Master nodes, bastion, remaining workers |
| 11 | Disk | zonal + regional | Orphaned boot disks |
| 12 | InstanceTemplate | global | Worker templates (after MIGs) |
| 13 | UnmanagedInstanceGroup | zonal | Master instance groups (now empty) |
| 14 | Router | regional | Cloud NAT must be removed before Subnetwork |
| 15 | Subnetwork | regional | After all instances and routers are gone |
| 16 | Network | global | After all subnets are deleted |
| 17 | IAM ServiceAccount | global | Age proxied via oldest user-managed key |

### Service Account age proxy

GCP does not expose a creation timestamp for service accounts. The script uses the `validAfterTime` of the oldest user-managed key as an age proxy. Service accounts with no user-managed keys (worker and master compute SAs that authenticate via GCE instance metadata) are always skipped to avoid deleting credentials for a potentially live cluster.

## How It Selects Resources

A resource is targeted for deletion only when **both** conditions are true:

1. **Name prefix**: the resource name starts with `ci-op` (the OpenShift CI job prefix).
2. **Age**: the resource's creation timestamp is older than `--max-age-hours`.

Resources that fail either check are logged as `Skip` and counted in the `skipped` total.

## Output and Exit Codes

The script logs one line per resource:

```text
[INFO] Skip ci-op-<id>-apiserver    (newer than 6h)
[INFO] Deleting ForwardingRule/global/ci-op-<id>-apiserver
[WARN] Already gone ForwardingRule/… (resource not found — likely cleaned by CI)
[ERROR] FAILED to delete BackendService/… : <error excerpt>
```

Final summary line:

```text
Done — deleted=6  skipped=219  warnings=0  errors=0
```

| Counter | Meaning |
|---------|---------|
| `deleted` | Resources successfully removed (or would-be in dry-run) |
| `skipped` | Resources excluded by name or age filter |
| `warnings` | Resources already gone before the script reached them (normal in shared CI) |
| `errors` | Real deletion failures that need investigation |

**Exit code 0** when `errors == 0`; **exit code 1** otherwise.

## Running in CI

For automated/non-interactive execution, authenticate via a service account key:

```bash
export GOOGLE_APPLICATION_CREDENTIALS=/path/to/sa-key.json
export GCP_PROJECT=openshift-observability
python3 hack/cleanup-gcp-resources.py
```

The script never prompts for input and is safe to run concurrently with OpenShift CI jobs. Concurrent cleanup races are handled gracefully — "resource not found" responses are counted as `warnings`, not `errors`.
