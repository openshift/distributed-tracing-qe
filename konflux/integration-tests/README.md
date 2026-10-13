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

Every ART build of the FBC (one build per OCP version) makes a Konflux Snapshot with one component, and Konflux starts the
scenarios on it (context `push`, like the other scenarios). The first task of each pipeline reads the OCP version from the labels of the FBC image and compares it with `ocp_version`; when they differ,
all other tasks are skipped and the run succeeds. So every scenario sees the FBC of every OCP version and works on its own.

## How a run works

1. `parse-metadata` gets the application (`fbc-rhosdt-<ART version>`) and the FBC image (`component-container-image`) of the Snapshot.
2. `resolve-ocp-version` reads the OCP version of the FBC (label `com.redhat.fbc.openshift.version`, otherwise the `version`
   label of the operator-registry base image) and skips the rest on a mismatch.
3. `resolve-release` reads everything that depends on the release, so the pipelines have no per-release parameters (see
   [Where the values come from](#where-the-values-come-from)). It fails with a message before a cluster is requested when one
   of its sources is missing.
4. `prepare-cluster-env` and `provision-cluster` create a HyperShift hosted cluster of `ocp_version` with the
   `provision-ephemeral-cluster` task of `openshift/konflux-tasks` (OpenShift CI, cluster profile `aws-konflux-prod`). The cluster is mirrored
   from `registry.redhat.io/rhosdt` to `registry.stage.redhat.io/rhosdt`, because the ART images exist only in the stage registry
   until the release is published. It is removed with the PipelineRun. Provisioning takes 20 to 55 minutes and the wait is 75 minutes.
5. `add-stage-credentials` adds the credentials of the Secret `stage-registry-creds` to the pull secret of the cluster.
6. The e2e pipeline installs the operator (`install-operator-from-fbc`: CatalogSource, OperatorGroup and Subscription in
   `opentelemetry-operator-system`), checks the versions of the images, installs Tempo, AMQ Streams, the Cluster Observability
   Operator, Loki and OpenShift Logging from `redhat-operators`, runs the DAST scan (`dast-test`, only when `run_dast` is `"true"`) on the cluster with the operators installed, and then runs the tests (`opentelemetry-e2e-tests`).
   The upgrade pipeline runs `opentelemetry-upgrade-tests` after step 5.

The tests are cloned from `openshift/open-telemetry-opentelemetry-operator`, from the branch of the release.

## Where the values come from

The pipelines read the release from the FBC under test, so nothing is edited for a release.

| Value | Source |
|---|---|
| ART version, for example `0.158` | the application of the Snapshot, `fbc-rhosdt-0-158` |
| Branch of the tests, `rhosdt-0.158` | `rhosdt-<ART version>` |
| Versions of the operator, the collector it expects and the target allocator | `operator`, `opentelemetry-collector` and `targetallocator` in `versions.txt` of that branch of `openshift/open-telemetry-opentelemetry-operator` |
| Version of the Red Hat build of the collector | `dist.version` in `manifest.yaml` of the same branch of `openshift/redhat-opentelemetry-collector` |
| CSV of the upgrade | the newest entry of the `stable` channel of the FBC (ART adds an entry for every build, `-1`, `-2`, `-3`) |
| Folder of the DAST results in GCS, `rhosdt/<version>` | the ART version |

These conventions must hold: the application name `fbc-rhosdt-<major>-<minor>`, the same `rhosdt-<ART version>` branch name in both
repositories, and the keys of `versions.txt`. `resolve-release` fails with a message when one is missing.

The versions are read from the branch as it is now, not from the commit of the build. When the FBC of an older build installs another
operator version than `versions.txt` names, `resolve-release` stops with a message, and the next build is tested.

The optional parameters `otel_tests_branch` and `rhosdt_version` override the branch and the version of the DAST results folder. They
are empty by default and are meant for testing a pipeline change or another branch. `otel_tests_branch` applies to the operator
repository only: the collector version is always read from the `rhosdt-<ART version>` branch of the collector repository. The DAST
results are uploaded to `rhosdt/<ART version>/otel` in the GCS bucket, not to a folder of the product version, unless `rhosdt_version` is set. `skip_tests` lists the tests that are skipped
and is the one policy list of the pipeline.

## Secrets in the tenant

| Secret | Used for |
|---|---|
| `stage-registry-creds` (dockerconfigjson, key `.dockerconfigjson`) | pulling the ART images from `registry.stage.redhat.io` (added by ART) |
| `rapidast-sa-rhosdt-key` (key `sa-key`) | uploading the RapiDAST results to GCS (needs a tenant admin) |

`add-stage-credentials` fails with a message that names the Secret when it or its key is missing.

## Releases

ART builds only the latest release and it is the only one that is supported and tested, so the scenarios of the previous release are
removed when a new one is added.

- **New ART group** (a new `rhosdt-*` branch, for example `0.159`): replace the scenarios in `konflux-release-data` with the new
  application and names (`fbc-rhosdt-0-159`, `otel-e2e-tests-4-14-0-159`, and so on). Nothing in these pipelines changes.
- **Patch release or a new ART build of the same group:** nothing to do. Konflux starts the scenarios on every FBC build, and the
  pipelines read the versions and the CSV of that build.
- **The supported OCP versions change:** change `ocp_version` of the scenarios.

The skill `otel-qe-prepare-ci` describes the steps.

## Run by hand

Maintainers of the tenant can manage ITS and patch Snapshots, but cannot create or cancel PipelineRuns, and cannot read events or Secrets:

1. Create a test ITS (same as above, `contexts: [{name: disabled}]` so Konflux does not start it on its own, `revision` of the resolver set to your branch of this repo).
2. Label a Snapshot of the FBC application: `oc label snapshot <name> -n art-rhosdt-tenant test.appstudio.openshift.io/run=<its>`.
   The Snapshot of an OCP version is the one whose `test.appstudio.openshift.io/result-image-url` annotation ends with `.ocp<version>`.
   The label is removed when the run starts. Konflux does not start a second run of the same scenario on a Snapshot while one is in
   progress, and only an admin of the tenant can cancel it.
3. Follow the PipelineRun in the Konflux UI (`https://konflux-ui.apps.kflux-ocp-p01.7ayg.p1.openshiftapps.com/ns/art-rhosdt-tenant`).
   Log in with `oc login --web https://api.kflux-ocp-p01.7ayg.p1.openshiftapps.com:6443/`.
4. Remove the test ITS; the tenant configuration is managed from `konflux-release-data`.

Only the last 3 PipelineRuns are kept. The result of every scenario is kept on the Snapshot, in the annotation
`test.appstudio.openshift.io/status`.

## Troubleshooting

A run for another OCP version than the one of the scenario ends in seconds with success. For a failed run, look at the task that failed:

| Task | Meaning |
|---|---|
| `resolve-release` | a convention above does not hold, the message names the file or the key |
| `provision-cluster` | OpenShift CI did not give a cluster in time, run it again |
| `add-stage-credentials` | the Secret `stage-registry-creds` or its key is missing in the tenant |
| `install-operator-from-fbc`, `check-opentelemetry-version` | the FBC or the images are not installable, see the log of the task |
| `dast-test` | with a message that names the Secret: `rapidast-sa-rhosdt-key` or its key `sa-key` is missing in the tenant. Otherwise look at the log of the task: the clone of the repository and the Secret manifest are set up before the scan, so the error can come from the setup or from the scan |
| `opentelemetry-e2e-tests`, `opentelemetry-upgrade-tests` | a failure of the tests of the product branch |
