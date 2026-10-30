# Architecture

Path from a git push to users hitting the voting app. The Mermaid source of truth is [`architecture.mmd`](architecture.mmd).

```mermaid
flowchart LR
  Dev[Developer] -->|git push to main| GHA[GitHub Actions]

  subgraph jobs [Pipeline jobs]
    Test[1. Integration test]
    Build[2. Build + Trivy]
    Push[2. Push images]
    Deploy[3. Helm deploy]
  end

  GHA --> Test
  Test --> Build
  Build --> Push
  Push --> GHCR[(GHCR<br/>voting-app-*:commit SHA)]
  Push --> Deploy
  Deploy -->|OIDC assume role<br/>no stored AWS keys| AWS[AWS IAM]
  AWS --> EKS[EKS cluster<br/>eu-west-1]

  subgraph release [Helm release: voting-app]
    Vote[vote]
    Result[result]
    Worker[worker]
    Redis[redis]
    DB[db PostgreSQL]
    Vote -->|enqueue| Redis
    Redis -->|pop votes| Worker
    Worker -->|save| DB
    Result -->|read counts| DB
  end

  GHCR -->|imageTag = SHA| release
  EKS --> release

  Users[Users] --> LBv[Vote LoadBalancer] --> Vote
  Users --> LBr[Result LoadBalancer] --> Result
```

GitHub and many Markdown previews render the diagram above automatically.

## Export to PNG

The README expects `docs/architecture.png`. Generate it from the `.mmd` file with [Mermaid CLI](https://github.com/mermaid-js/mermaid-cli):

```bash
npx --yes @mermaid-js/mermaid-cli -i docs/architecture.mmd -o docs/architecture.png
```

Or paste `docs/architecture.mmd` into [mermaid.live](https://mermaid.live), then use **Actions → PNG**. Save the file as `docs/architecture.png`.
