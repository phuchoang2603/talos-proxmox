# Kubeflow rollout (prod)

The rollout is staged. The first GitOps Application owns the shared Argo Workflows controller and CRDs, creates the `kubeflow` namespace, and watches workflows in that namespace. It uses the pinned `argo-workflows` chart 1.0.24 (Argo Workflows v4.0.8), compatible with the Argo 4.0 line listed by KFP 2.17.2. The Argo Server UI is disabled. Dev has no Argo Workflows Application.

No Kubeflow UI or API is published in this stage. The Kubeflow Central Dashboard requires working Profiles/KFAM integration and an authenticated ingress before public routes are added; a Cloudflare TunnelBinding alone does not provide authentication. Do not expose Pipelines, Notebooks, Katib or the Dashboard without that boundary.

## GPU preflight

On October 6, 2026, the bounded Job `default/kubeflow-gpu-smoke-20261006` requested `nvidia.com/gpu: 1` through the DRA-backed DeviceClass. Kubernetes scheduled it onto `prod-server1`. The image `docker.io/nvidia/cuda@sha256:0eee3094c71518ad31d011a594ae6ed6de72959ee07e318cb31cffe71690e90c` compiled and ran a CUDA 13.0.2 `sm_120` kernel; its output was `CUDA result: 42` and the Job completed successfully at 15:10 UTC. Its 20-minute active deadline and 10-minute completion TTL prevent a lingering test workload.

This proves GPU-requesting Job scheduling and CUDA execution, not Katib Trial or notebook GPU integration. Before adding those workloads, verify that their scheduling and concurrency do not compete with ClickStack and other production services.
