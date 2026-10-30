# Example Voting App (DevOps capstone)

A fork of [dockersamples/example-voting-app](https://github.com/dockersamples/example-voting-app) with Terraform, Helm, and GitHub Actions added so the app can run on Amazon EKS.

You vote in a Python web app. A background worker stores that vote. A Node.js page shows the live score. Redis is the queue in the middle; PostgreSQL is the database.

## How a vote moves through the system

1. **vote** (Python / Flask) — the ballot page. A POST writes a JSON payload onto a Redis list named `votes`.
2. **Redis** — holds votes until the worker is ready.
3. **worker** (.NET) — pops items from Redis and writes them to PostgreSQL.
4. **PostgreSQL** — stores one row per voter (`voter_id` + choice).
5. **result** (Node.js) — reads the counts from PostgreSQL and streams them to the browser.

Vote talks only to Redis. Result and worker talk to PostgreSQL. They find each other by the Kubernetes (or Compose) service names `redis` and `db`.

## Architecture overview

A push to `main` is tested, scanned, published, then deployed. GitHub Actions logs into AWS with OIDC (no long-lived access keys). Helm installs one release on EKS. Two AWS load balancers expose vote and result.

![Architecture](docs/architecture.png)

The diagram source is [`docs/architecture.mmd`](docs/architecture.mmd). If the PNG is not in the repo yet, see [`docs/architecture.md`](docs/architecture.md) (GitHub renders the Mermaid there) and the export command in that file.

## Repository layout

| Path | What it is |
| --- | --- |
| `vote/`, `result/`, `worker/` | App code and Dockerfiles |
| `docker-compose.yml` | Local (and CI integration-test) stack |
| `helm/voting-app/` | Kubernetes chart used in AWS |
| `terraform/` | EKS cluster, node group, GitHub OIDC deploy role |
| `.github/workflows/capstone-ci.yaml` | Test → scan → publish → deploy |

## Prerequisites

- **Docker** with Compose, so you can run the app locally
- **AWS CLI** with a profile named `devops-capstone` (this is what Terraform uses)
- **Terraform** 1.5 or newer
- **kubectl**
- **Helm**
- A GitHub repo you can push to (`basitol/example-voting-app` in this fork)

## Run locally

From the repo root:

```bash
docker compose up
```

- Vote: [http://localhost:8080](http://localhost:8080)
- Result: [http://localhost:8081](http://localhost:8081)

Compose builds **vote** and **result** with their `dev` Dockerfile stages (live reload). **worker** uses the production-style final stage. Redis and PostgreSQL use public images.

Stop with `Ctrl+C`, then `docker compose down -v` if you want to drop the local database volume.

## Infrastructure (Terraform)

Terraform does **not** install the voting app. It creates:

- An EKS cluster named `voting-app-capstone` in **eu-west-1**, Kubernetes version **1.36**, on the **default VPC**
- A managed node group: 2 × `m7i-flex.large`
- An IAM OIDC provider for GitHub Actions and a deploy role that can describe the cluster and edit the `default` namespace

State is **local** (`terraform/*.tfstate` is gitignored). Run apply and destroy from the same machine.

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

When apply finishes, copy the `github_deploy_role_arn` output into the GitHub repository **variable** `AWS_ROLE_ARN` (Settings → Secrets and variables → Actions → Variables). The workflow reads `${{ vars.AWS_ROLE_ARN }}`, not a secret.

Point kubectl at the cluster (needed for Helm on your laptop):

```bash
aws eks update-kubeconfig --region eu-west-1 --name voting-app-capstone --profile devops-capstone
```

The IAM role trust policy only accepts GitHub OIDC tokens whose subject matches `github_oidc_subject` in `terraform/oidc.tf` (this repository’s `main` branch).

## CI/CD

Workflow: [`.github/workflows/capstone-ci.yaml`](.github/workflows/capstone-ci.yaml).

It runs on **push** and **pull_request** to `main`. Deploy runs only on **push** to `main`.

| Job | When | What it does |
| --- | --- | --- |
| **Integration Test** | PR and push | `docker compose up -d --build`, then [`.github/scripts/integration-test.sh`](.github/scripts/integration-test.sh): wait for vote and result, POST a vote, assert the count increased in PostgreSQL |
| **Build, Scan and Publish** | After tests pass | For **vote**, **result**, and **worker** in parallel: build the production image, scan it with Trivy (CRITICAL and HIGH; unfixed findings are ignored), and on push to `main` push `ghcr.io/<owner>/voting-app-<service>:<git-sha>` |
| **Deploy to EKS** | Push to `main` only, after images publish | Assume the IAM role with OIDC, `aws eks update-kubeconfig`, then `helm upgrade --install` with `--atomic` |

Production Dockerfile targets used in that second job:

- vote → `final`
- result → `production`
- worker → default (final) stage

### How OIDC authentication works

1. Terraform registered GitHub (`token.actions.githubusercontent.com`) as an IAM OIDC identity provider.
2. Role `voting-app-capstone-github-deploy` may be assumed only with `sts:AssumeRoleWithWebIdentity` when the token audience is `sts.amazonaws.com` and the subject matches this repo’s `main` branch.
3. The deploy job sets `permissions: id-token: write` and calls `aws-actions/configure-aws-credentials` with `role-to-assume: ${{ vars.AWS_ROLE_ARN }}`.
4. GitHub issues a short-lived token; AWS exchanges it for temporary credentials. There is no `AWS_ACCESS_KEY_ID` stored in GitHub Secrets.
5. Those credentials can call `eks:DescribeCluster` and, via an EKS access entry, edit the `default` namespace (`AmazonEKSEditPolicy`).

## Deploying and rolling back with Helm

CI deploys with:

```bash
helm upgrade --install voting-app ./helm/voting-app \
  --set imageTag=${{ github.sha }} \
  --atomic --timeout 5m
```

`--set imageTag=...` makes every app image use the commit that just landed in GHCR (`ghcr.io/basitol/voting-app-<service>:<sha>`). Redis and PostgreSQL still use the tags in `helm/voting-app/values.yaml`.

**`--atomic`:** if the new pods are not ready within 5 minutes, Helm marks the revision **failed** and rolls back to the last successful revision by itself.

The chart creates:

- Deployments: `vote` (2 replicas), `result` (1 replica — websockets, no session stickiness), `worker`, `redis`, `db`
- Services: `vote` and `result` are **LoadBalancer** (AWS creates a public load balancer for each); `redis` and `db` are ClusterIP only
- Secret `db-credentials` from values in Git (demo user/password)

Public URLs:

```bash
kubectl get svc vote result
```

Use the `EXTERNAL-IP` / hostname on port 80.

### History and manual rollback

```bash
helm history voting-app
```

Each number is a revision. `deployed` is live. `superseded` was live before a later upgrade. `failed` never became live.

To go back to a known-good revision (for this project, revision 5 was used after a bad image tag failed):

```bash
helm rollback voting-app 5
```

A failed `--atomic` upgrade should already have returned you to the previous good revision. Manual `helm rollback` is for when you want a specific older revision, or when a failed revision did not clean up the way you expected.

The chart has **no `imagePullSecrets`**. The cluster must be able to pull from GHCR (packages left public is the usual way this works).

## Security notes

- **Image tags, not `:latest`:** production Dockerfiles use `python:3.11-slim`, `node:22-bookworm-slim`, and `mcr.microsoft.com/dotnet/sdk|runtime:8.0-bookworm-slim`. Helm uses `redis:7-alpine` and `postgres:15-alpine`. These are version tags, not digest pins (`@sha256:...`).
- **Non-root app containers:** vote `final` runs as `app`, result `production` as `node`, worker as `app`. Helm does not set `securityContext`. Compose **dev** stages for vote/result do not set `USER`.
- **Trivy:** the pipeline fails the build on fixable **CRITICAL** or **HIGH** OS/library findings (`exit-code: "1"`, `ignore-unfixed: true`).
- **No stored AWS keys:** deploy uses GitHub OIDC and the `AWS_ROLE_ARN` **variable**. GHCR login uses the automatic `GITHUB_TOKEN`.

## Known limitations

- **Demo database credentials are hard-coded in the apps.** `worker/Program.cs` uses `Username=postgres;Password=postgres`. `result/server.js` uses `postgres://postgres:postgres@db/postgres`. Changing the Helm secret alone will not change what those processes send. Vote does not talk to PostgreSQL.
- **Those same values live in Git** in `helm/voting-app/values.yaml` and become Secret `db-credentials`. A production setup would create the Secret **outside** Git (and teach the apps to read it).
- **PostgreSQL uses `emptyDir`.** Votes disappear if the `db` pod is rescheduled. A PersistentVolumeClaim would need an EBS CSI driver (or similar) on the cluster; that is not installed here.
- **Capstone scale.** One small node group, default VPC, result pinned to 1 replica, no TLS on the load balancers.

## Cost and teardown

Load balancers from the `vote` and `result` Services keep billing until they are deleted. Remove the app **before** destroying the cluster:

```bash
helm uninstall voting-app
kubectl get svc          # wait until vote and result (and their load balancers) are gone
cd terraform
terraform destroy
```

If you skip Helm uninstall, AWS load balancers can remain, and Terraform may fail to delete networking that those balancers still hold.
