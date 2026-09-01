# infra/terraform

Two independent Terraform stacks live here. They do not reference each other
and are never applied together.

| Stack | Root | Target | Status |
|-------|------|--------|--------|
| AKS   | `./` (this dir's `main.tf`) | Kubernetes on AKS | Original design, not used for the current test environment — kept as-is, not called |
| Container Apps | `./container-apps/` | Azure Container Apps (test env) | Active — see `docs/release-test-deploy.md` |

## Container Apps stack (`./container-apps/`)

Provisions the TEST environment: Resource Group, ACR, Container Apps
Environment + Log Analytics, 7 Container Apps (gateway + 6 services),
Postgres Flexible Server (B1ms), Azure Cache for Redis (Basic C0), Storage
Account + blob containers, Service Bus namespace (Basic), Key Vault (JWT
keys + connection strings).

### Prerequisites

- Azure CLI logged in (`az login`) with a subscription set, or `ARM_*`
  service principal env vars — same as any `azurerm` provider usage.
- A JWT RSA key pair. Generate one outside Terraform, e.g.:
  ```bash
  openssl genrsa -out jwt-private.pem 2048
  openssl rsa -in jwt-private.pem -pubout -out jwt-public.pem
  ```
- A Postgres admin password of your choosing.

**None of these go in git.** Pass them as `TF_VAR_*` environment variables,
or in a `*.auto.tfvars` file (gitignored — see repo `.gitignore`):

```bash
export TF_VAR_postgres_admin_password='...'
export TF_VAR_jwt_private_key_pem="$(cat jwt-private.pem)"
export TF_VAR_jwt_public_key_pem="$(cat jwt-public.pem)"
```

### Commands

```bash
cd infra/terraform/container-apps
terraform init
terraform validate
terraform plan  -var-file=environments/test.tfvars
terraform apply -var-file=environments/test.tfvars
```

### Bootstrapping order (why the first apply looks odd)

Every Container App is created with a public placeholder image
(`mcr.microsoft.com/k8se/quickstart:latest`) because Container Apps needs a
pullable image at creation time, and on a brand-new environment nothing has
been pushed to the ACR yet. Terraform is told to ignore further changes to
the image (`lifecycle.ignore_changes`), so it never fights the deploy
pipeline, which flips each app to its real image via `az containerapp
update`. In short: `terraform apply` creates the skeleton, the deploy
pipeline (Agent 3) fills in the real images.

### Outputs the deploy pipeline needs

| Output | Used for |
|--------|----------|
| `acr_login_server` | `docker push` / `az acr build` target |
| `resource_group_name` | scope for `az containerapp` / `az acr` commands |
| `container_app_names` | map `{gateway, auth, file, storage, sync, photo, notification} -> Container App name`, target of `az containerapp update --name <name> --image <image>` |
| `gateway_fqdn` | public URL for the post-deploy smoke test (`curl https://<gateway_fqdn>/health/ready`) |
| `key_vault_uri` | reference if any pipeline step needs to read/rotate a secret directly |

Read them after apply with:

```bash
terraform output -json
# or a single value, e.g.:
terraform output -raw gateway_fqdn
```

### Known gaps a human must handle before/at real `apply`

- **Global name collisions.** ACR, Storage Account, Key Vault and Redis
  names are derived from `prefix`+`environment` (e.g. `acrzdrivetest`) and
  must be globally unique in Azure. If `apply` fails on a name conflict,
  change `prefix` in `environments/test.tfvars` and re-apply.
- **Service Bus has no queues/topics.** No service in `src/services` uses
  Service Bus yet (checked — no `ServiceBusClient`/queue/topic references
  anywhere). The namespace is provisioned per the infra decision list;
  add queues/topics in `modules/service_bus` once a service needs them,
  named after what that service's code expects.
- **Redis and Service Bus connection strings are Key-Vault-only.** They're
  stored as secrets but not wired into any Container App env var, because
  no service currently reads `REDIS_CONNECTION_STRING` /
  `SERVICE_BUS_CONNECTION_STRING`. Wire them into the relevant app's `secret`
  + `env` blocks in `modules/container_apps` when that changes.
- **Gateway → service routing env var names are a best-effort guess.**
  They mirror `ApiGateway/appsettings.json`'s current `ReverseProxy:Clusters`
  keys verbatim (`auth-cluster`/`auth-service`, etc.) turned into
  `ReverseProxy__Clusters__auth-cluster__Destinations__auth-service__Address`
  style env vars. Agent 1's task (making these configurable from env) runs
  in parallel — if it renames the config keys, update
  `modules/container_apps/main.tf`'s `local.gateway_clusters` to match.
