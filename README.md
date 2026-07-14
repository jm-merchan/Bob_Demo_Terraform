## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.14 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | >= 3.2.1 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | 3.2.1 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [kubernetes_deployment_v1.this](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/deployment_v1) | resource |
| [kubernetes_secret_v1.registry](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/secret_v1) | resource |
| [kubernetes_service_v1.this](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/service_v1) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_app_name"></a> [app\_name](#input\_app\_name) | Application name. Used as the base for all resource names, pod-selector labels, and the app.kubernetes.io/name label. Must be a valid RFC 1123 DNS label. | `string` | n/a | yes |
| <a name="input_container_port"></a> [container\_port](#input\_container\_port) | Container port the application listens on. Used for the pod port declaration and health probe HTTP GET target. | `number` | `8080` | no |
| <a name="input_cpu_limit"></a> [cpu\_limit](#input\_cpu\_limit) | CPU resource limit per container pod. Must be >= cpu\_request. Kubernetes quantity string. | `string` | `"500m"` | no |
| <a name="input_cpu_request"></a> [cpu\_request](#input\_cpu\_request) | CPU resource request per container pod. Kubernetes quantity string (e.g., "250m", "0.25"). | `string` | `"250m"` | no |
| <a name="input_enable_liveness_probe"></a> [enable\_liveness\_probe](#input\_enable\_liveness\_probe) | Enable or disable the container liveness probe. When false, the liveness probe block is omitted entirely. | `bool` | `true` | no |
| <a name="input_enable_readiness_probe"></a> [enable\_readiness\_probe](#input\_enable\_readiness\_probe) | Enable or disable the container readiness probe. When false, the readiness probe block is omitted entirely. | `bool` | `true` | no |
| <a name="input_image"></a> [image](#input\_image) | Full OCI image reference including registry and tag (e.g., de.icr.io/san-clients/backend:latest). Must not be empty. | `string` | n/a | yes |
| <a name="input_liveness_path"></a> [liveness\_path](#input\_liveness\_path) | HTTP GET path for the liveness probe. Must start with /. Liveness checks MUST NOT call external dependencies. | `string` | `"/health/live"` | no |
| <a name="input_memory_limit"></a> [memory\_limit](#input\_memory\_limit) | Memory resource limit per container pod. Must be >= memory\_request. Kubernetes quantity string. | `string` | `"512Mi"` | no |
| <a name="input_memory_request"></a> [memory\_request](#input\_memory\_request) | Memory resource request per container pod. Kubernetes quantity string (e.g., "256Mi", "512M"). | `string` | `"256Mi"` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Target Kubernetes namespace. Must exist before apply. Must be a valid RFC 1123 DNS label (lowercase alphanumeric and hyphens, max 63 chars, start and end with alphanumeric). | `string` | n/a | yes |
| <a name="input_readiness_path"></a> [readiness\_path](#input\_readiness\_path) | HTTP GET path for the readiness probe. Must start with /. May check upstream dependency health. | `string` | `"/health/ready"` | no |
| <a name="input_registry_password"></a> [registry\_password](#input\_registry\_password) | Password or API key for registry authentication. Written via data\_wo — never stored in state. | `string` | n/a | yes |
| <a name="input_registry_secret_revision"></a> [registry\_secret\_revision](#input\_registry\_secret\_revision) | Revision counter for the registry pull secret. Increment this value to trigger a credential rotation (replaces data\_wo payload in-place). | `number` | `1` | no |
| <a name="input_registry_server"></a> [registry\_server](#input\_registry\_server) | Hostname of the private container registry (e.g., de.icr.io). Used to construct the .dockerconfigjson auth payload. | `string` | n/a | yes |
| <a name="input_registry_username"></a> [registry\_username](#input\_registry\_username) | Username for registry authentication (e.g., iamapikey for IBM ICR). | `string` | n/a | yes |
| <a name="input_replicas"></a> [replicas](#input\_replicas) | Number of pod replicas to run. Must be between 1 and 100 inclusive. Passed to the provider as a string via tostring(). | `number` | n/a | yes |
| <a name="input_service_type"></a> [service\_type](#input\_service\_type) | Kubernetes service type. Defaults to ClusterIP (no external exposure). Use LoadBalancer only with appropriate cloud annotations. | `string` | `"ClusterIP"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_deployment_name"></a> [deployment\_name](#output\_deployment\_name) | Name of the kubernetes\_deployment\_v1 resource. Used by CI/CD pipelines for kubectl rollout status commands. |
| <a name="output_secret_name"></a> [secret\_name](#output\_secret\_name) | Name of the kubernetes\_secret\_v1 pull-secret resource. Allows consumers to reference the pull secret in additional deployments in the same namespace. |
| <a name="output_service_cluster_ip"></a> [service\_cluster\_ip](#output\_service\_cluster\_ip) | ClusterIP address assigned to the service. Empty string for headless services. Value is plan-unknown until apply. |
| <a name="output_service_name"></a> [service\_name](#output\_service\_name) | Name of the kubernetes\_service\_v1 resource. Used by Ingress resources and other services that reference this workload. |
