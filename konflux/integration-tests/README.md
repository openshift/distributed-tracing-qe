# Konflux integration tests for the OpenTelemetry ART builds

Tekton pipelines for the Konflux Integration Test Scenarios (ITS) of the Red Hat build of OpenTelemetry in the ART tenant
`art-rhosdt-tenant` (cluster `kflux-ocp-p01`). They run on the FBC (file-based catalog) fragment that ART builds. ART builds
the FBC after the operator, collector and target allocator images are in the stage registry, so the images exist when a
pipeline starts.

The ITS definitions are in `konflux-release-data`
(`tenants-config/cluster/kflux-ocp-p01/tenants/art-rhosdt-tenant/otel-integration-tests.yaml`) and point at the files in this
directory through a git resolver.

| Pipeline | What it does |
|---|---|
| `opentelemetry-operator-e2e-test-fbc-pipeline.yaml` | Installs the operator from the FBC and its dependencies on a new cluster and runs the chainsaw tests of the product branch. Runs the RapiDAST scan when `run_dast` is `"true"`. |
| `opentelemetry-operator-upgrade-test-fbc-pipeline.yaml` | Runs `tests/e2e-openshift-upgrade` of the product branch: installs the released operator from `redhat-operators` and upgrades it to the FBC. |

## Scenarios

All scenarios are optional (label `test.appstudio.openshift.io/optional: "true"`), in the application `fbc-rhosdt-<ART version>`:

| ITS | Pipeline | Params |
|---|---|---|
| `otel-e2e-tests-4-14-<ART version>` | e2e | `ocp_version=4.14` |
| `otel-e2e-tests-4-22-<ART version>` | e2e | `ocp_version=4.22`, `run_dast=true` |
| `otel-upgrade-tests-4-22-<ART version>` | upgrade | `ocp_version=4.22` |

ART starts the scenarios named in the `group.yml` of its `ocp-build-data` branch after each FBC build (one build per OCP
version). The scenario needs `contexts: [{name: disabled}]` for that, so Konflux does not start it on its own. The first
task of each pipeline reads the OCP version from the labels of the FBC image and compares it with `ocp_version`; when they differ,
all other tasks are skipped and the run succeeds. So every scenario sees the FBC of every OCP version and works on its own.

## How a run works

1. `parse-metadata` gets the FBC image of the Snapshot (`component-container-image`).
2. `resolve-ocp-version` reads the OCP version of the FBC (label `com.redhat.fbc.openshift.version`, otherwise the `version`
   label of the operator-registry base image) and skips the rest on a mismatch.
3. `prepare-cluster-env` and `provision-cluster` create a HyperShift hosted cluster of `ocp_version` with the
   `provision-ephemeral-cluster` task of `openshift/konflux-tasks` (OpenShift CI, cluster profile `aws-konflux-prod`). The cluster is mirrored
   from `registry.redhat.io/rhosdt` to `registry.stage.redhat.io/rhosdt`, because the ART images exist only in the stage registry
   until the release is published. It is removed with the PipelineRun.
4. `add-stage-credentials` adds the credentials of the Secret `stage-registry-creds` to the pull secret of the cluster.
5. The e2e pipeline installs the operator (`install-operator-from-fbc`: CatalogSource, OperatorGroup and Subscription in
   `opentelemetry-operator-system`), checks the versions of the images, installs Tempo, AMQ Streams, the Cluster Observability
   Operator, Loki and OpenShift Logging from `redhat-operators`, and runs the tests (`opentelemetry-e2e-tests`), then the DAST scan.
   The upgrade pipeline runs `opentelemetry-upgrade-tests` after step 4.

The tests are cloned from `openshift/open-telemetry-opentelemetry-operator`, branch `otel_tests_branch`.

## Secrets in the tenant

| Secret | Used for |
|---|---|
| `stage-registry-creds` (dockerconfigjson) | pulling the ART images from `registry.stage.redhat.io` (added by ART) |
| `rapidast-sa-rhosdt-key` (key `sa-key`) | uploading the RapiDAST results to GCS (needs a tenant admin) |

## Per-release update

Run `konflux/integration-tests/update-versions.sh <rhosdt-version> <art-version> [ocp-version]`, for example
`update-versions.sh 3.11 0.158`. It sets the per-release defaults of the pipelines (operator, collector and target allocator
versions, tests branch, product version, name of the upgrade CSV in the stable channel of the FBC). Review the diff, then update
the ITS in `konflux-release-data` (application and names carry the ART version) and the `fbc` list in the `group.yml` of the new
`ocp-build-data` branch. The skill `otel-qe-prepare-konflux-tests` describes the full procedure.

## Run by hand

Maintainers of the tenant can manage ITS and patch Snapshots, but cannot create PipelineRuns:

1. Create a test ITS (same as above, `contexts: [{name: disabled}]`, `revision` of the resolver set to your branch of this repo).
2. Label a Snapshot of the FBC application: `oc label snapshot <name> -n art-rhosdt-tenant test.appstudio.openshift.io/run=<its>`.
3. Follow the PipelineRun in the Konflux UI (`https://konflux-ui.apps.kflux-ocp-p01.7ayg.p1.openshiftapps.com/ns/art-rhosdt-tenant`).
   Log in with `oc login --web https://api.kflux-ocp-p01.7ayg.p1.openshiftapps.com:6443/`.
4. Remove the test ITS; the tenant configuration is managed from `konflux-release-data`.

## Not verified yet

- The pipelines have not run in the ART tenant yet. Needed first: `art-rhosdt-tenant` as an owner of the `aws-konflux-prod` cluster
  profile in `openshift/release`.
- How the stage credentials reach the nodes of a HyperShift hosted cluster. `add-stage-credentials` sets the `additional-pull-secret`
  of `kube-system` (hosted clusters with the global pull secret feature) and the pull secret of `openshift-config`; the
  OCP 4.14 hosted cluster may need another way.
