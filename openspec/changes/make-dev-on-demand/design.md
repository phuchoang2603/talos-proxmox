## Context

- `terraform.yml` runs the Provision job for `[dev, prod]` on every push to `main`. `manual.yml` already dispatches `provision.yml` for one environment with `apply` or `destroy`, on `main` only.
- A destroy runs the cluster root with `-destroy`, then empties the platform state, because everything the platform root manages lived in the destroyed cluster.
- Dev's cluster workspace `talos-cluster-dev` has been locked since a run whose apply found no changes but could not release the lock ("state version upload is still pending"). Every dev run since has failed to acquire it. Prod runs succeeded throughout.
- `pve` has 8 threads (Xeon W-2123, 4 cores) and 62 GiB. It runs prod-server1 (6 vCPUs, 22 GiB, GPU passthrough), dev-server1 (4, 16 GiB), `nixos-server` (4, 8 GiB), and `truenas-scale` (2, 8 GiB).
- The `bpg/proxmox` VM resource defaults to `reboot_after_update = true`, so a CPU or memory change reboots the VM during apply.

## Goals / Non-Goals

**Goals:**
- No dev cluster unless an operator asks for one, and no CI run that touches dev on push.
- A rebuilt dev matches what Git defines today.
- prod-server1 gets 8 vCPUs and 32 GiB.

**Non-Goals:**
- Removing dev's definitions, overlays, or Doppler config.
- Raising ClickHouse's own memory limit. That is a separate change once the node has room.
- A local development cluster for microservices.

## Decisions

### Dev applies only on dispatch

The push workflow runs Provision for prod alone. The matrix is removed rather than reduced to one entry, so the job name and concurrency group stay `provision-prod`. The Manual Provision workflow already offers `dev` with `apply` and `destroy`, so it needs no change. Lint keeps rendering dev overlays, so a dispatch does not find broken charts that pushes never checked.

A dispatched dev apply builds from the current `main`. Nothing reconciles dev between dispatches, but dev is expected to be destroyed again after each rehearsal.

### Destroy through the workflow

Dev is destroyed by dispatching Manual Provision with `dev` and `destroy`, which removes dev's Proxmox VM, AWS resources, and the generated credentials the cluster root wrote to Doppler, then resets dev's platform state. Doing it in CI keeps the same credentials and ordering as a normal destroy. Before dispatching, the stale lock on `talos-cluster-dev` is force-unlocked through the HCP Terraform API. The run that left it found no changes, so no state is lost.

Foundation-owned dev keys in Doppler (the secret-store tokens) stay. A rebuild needs them, and the foundation root, not the cluster root, owns them.

### No telemetry link between environments

Dev's telemetry agents were its only dependency on prod. They sent to the gateway's LAN LoadBalancer with a shared bearer token. Dev now exists only for short rehearsals, so its telemetry is not worth that link. `otel-agent` targets prod only, with prod's cluster name, environment, and in-cluster gateway address as chart defaults, and its environment overlays go away.

Prod's agents reach the gateway through its in-cluster Service, so the gateway becomes ClusterIP and drops `bearertokenauth`. Prod's in-cluster agents already accept OTLP from any pod without credentials, so a token on the gateway alone added nothing inside the cluster. The foundation root stops generating `OTEL_INGEST_TOKEN`, which deletes it from both Doppler configs. That apply runs after Argo CD removes the ExternalSecrets that read it, so no ExternalSecret reports a missing key.

### Resize after dev is gone

prod-server1 has a passthrough GPU, so all of its memory is pinned on `pve`. Growing it to 32 GiB while dev still runs would need about 64 GiB on a 62 GiB host. The resize is pushed only after the dev destroy succeeds. With dev gone, guests on `pve` total 48 GiB, leaving about 14 GiB for the host and TrueNAS.

Eight vCPUs equals every thread on `pve`, so prod-server1 shares them with the nixos and TrueNAS VMs (14 vCPUs on 8 threads). That suits bursty work like this and needs no pinning.

The apply reboots prod-server1. It is one of three control-plane nodes, so etcd keeps quorum. ClickHouse, Grafana, and GPU workloads on that node are down until it returns.

## Risks / Trade-offs

- [Dev definitions drift unnoticed between dispatches] → Lint still renders dev overlays on every PR; a dispatch surfaces anything lint cannot catch.
- [The force-unlock hides an upload that later completes] → The run that held the lock changed nothing. The next plan from a dispatch compares against real infrastructure.
- [prod-server1 does not come back after the reboot] → Proxmox keeps the previous config until the apply succeeds. Reverting `k8s_nodes.json` and pushing restores the old size.
- [The host runs low on memory with prod-server1 at 32 GiB] → 14 GiB remains for the host and TrueNAS. Lower `memory_mb` if TrueNAS's cache needs more.

## Migration Plan

1. Merge the workflow change. The push apply runs for prod only and changes nothing.
2. Force-unlock `talos-cluster-dev`, dispatch Manual Provision `dev`/`destroy`, and confirm VM 1111 and dev's AWS resources are gone.
3. Merge the resize. The push apply reboots prod-server1 with 8 vCPUs and 32 GiB.
4. Merge the telemetry decoupling. Argo CD removes dev's `otel-agent` Application, the gateway's LoadBalancer, and both token ExternalSecrets. Then apply the foundation root locally to delete `OTEL_INGEST_TOKEN`.

Rollback: dispatch Manual Provision `dev`/`apply` to rebuild dev, after reverting the resize if `pve` lacks memory for both.
