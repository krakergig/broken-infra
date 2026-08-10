# Broken Cloud Pipeline

A deliberately-flawed, peer-reviewable AWS deployment pipeline built with **Terraform**,
**Jenkins**, and **Bash**, deployed to **Frankfurt (`eu-central-1`)**. It runs a
public hello-world application and a Jenkins controller as **ECS-on-EC2** containers
across **two peered VPCs**, with ALBs, S3 logging, Route53 health checks, CloudWatch
alarms, and SNS notifications.

Per the challenge, it contains **exactly three subtle, documented flaws** — one each in
Terraform, the Jenkins pipeline, and a script — none of which break core functionality.

---

## Architecture

```
                          Internet (HTTPS :443 only)
                    │                                │
        ┌───────────▼───────────┐        ┌───────────▼────────────┐
        │  App ALB (public)      │        │  Jenkins ALB (public)   │
        │  open to all           │        │  WAF geo-allow: PT      │
        └───────────┬────────────┘        └───────────┬────────────┘
   VPC 10.40.0.0/16 │                 VPC 10.41.0.0/16 │
   ┌────────────────▼──────────────┐  ┌───────────────▼───────────────┐
   │ private subnets                │  │ private subnets                │
   │  ECS cluster (2x t3.micro)     │  │  ECS cluster (2x t3.micro)     │
   │  2x hello-world tasks          │  │  1x jenkins/jenkins:lts        │
   └────────────────────────────────┘  └────────────────────────────────┘
                    └──────── VPC peering (10.40 <-> 10.41) ────────┘

 Shared: ECR • S3 log bucket • SNS (+us-east-1) • CloudWatch alarms • Route53 health checks
```

- **Two VPCs**, 4 subnets each (2 public / 2 private), created with
  `terraform-aws-modules/vpc/aws`, connected by VPC peering.
- **HTTPS-only inbound** enforced by security groups **and** network ACLs.
- **Jenkins ALB geo-restricted** to Portugal via a WAFv2 geo-match web ACL.
- Both workloads deploy through the same reusable [`ecs_service`](terraform/modules/ecs_service) module.
- A self-signed certificate is imported into ACM so the ALBs can serve HTTPS without a
  registered domain (swap for an ACM DNS-validated cert in production).
- **Monitoring** (per service, via a `services` map): Route53 health check + CloudWatch
  alarms for **5xx** (any occurrence), **4xx** (spike > threshold), **CPU** and **memory**
  utilization, plus a health-check-status alarm; and one account-wide **daily
  estimated-charges** alarm (metric math: day-over-day `DIFF()` of `EstimatedCharges`,
  so it reflects a single day's spend rather than the month-to-date total). All notify
  by email through SNS.

---

## Repository layout

```
terraform-chal/
├── docker/
│   └── hello-world/
│       └── Dockerfile         # customises infrastructureascode/hello-world
├── Jenkinsfile                # manual pipeline: build → push → deploy → verify
├── scripts/verify_health.sh   # post-deploy smoke test
├── .pre-commit-config.yaml    # pre-commit-hooks, terraform, checkov, detect-secrets
├── .secrets.baseline          # detect-secrets baseline
└── terraform/
    ├── environments/
    │   └── dev/                # root config: wires the modules for the dev env
    │       ├── versions.tf providers.tf variables.tf locals.tf
    │       ├── main.tf         # module composition + WAF↔ALB association
    │       ├── iam.tf          # service-specific ECS task roles (passed into services)
    │       └── outputs.tf
    └── modules/
        ├── vpc/                # ONE VPC: subnets + NACLs (pure network fabric, used x2)
        ├── peering/            # connects two VPCs (peering + routes) — reused per env
        ├── waf/                # regional geo-restriction web ACL — reused per env
        ├── platform/           # S3 logs + ECR + ACM cert (shared platform resources)
        ├── monitoring/         # SNS + Route53 health checks + CloudWatch alarms
        └── ecs_service/        # ECS-on-EC2 + ALB + SGs + instance/execution roles (used x2)
```

### Terraform layout & file-splitting standard
Terraform is organised in two tiers:

1. **Reusable modules** (`modules/*`) each own **one thing** and are instantiated as
   needed: `vpc` and `ecs_service` are each stood up twice (app + Jenkins); `peering`
   and `waf` are reused by every environment (dev/staging/prod); `platform` and
   `monitoring` are single-purpose units. There is no "workload"/"networking" wrapper
   module — grouping instantiations is the composition layer's job. Resources that are
   genuinely singular *and* environment-specific stay in the composition layer: the
   service task roles (`iam.tf`) and the WAF↔ALB association glue (in `main.tf`).
2. **Environments** (`environments/dev`) are the composition/root layer: they wire the
   modules together, own genuinely one-off or multi-module concerns (the WAF web ACL and
   its ALB association), and set environment-specific inputs — so standing up
   `staging`/`prod` later means adding a sibling folder, not copying resources.

**Within a module**, files are split **by concern**, one topic per file. Cross-cutting
config uses conventional filenames (`versions.tf`, `providers.tf`, `variables.tf`,
`locals.tf`, `outputs.tf`). This keeps diffs small, makes each file's blast radius
obvious, and lets reviewers jump straight to a layer. Every resource carries a brief
`#` comment explaining its purpose.

---

## The three intentional flaws

All flaws are cost-themed and **interlinked** (senior-level), and each is tagged with a
`FLAW` comment in-code. None impair core functionality; the pipeline is theoretically
executable once they are fixed.

| # | Location | Flaw | Effect | Fix |
|---|----------|------|--------|-----|
| 1 | **Terraform** — `environments/dev/main.tf` (app `ecs_service` call) | App is over-provisioned: `cpu = 2048` (both vCPUs of a `t3.micro`) **and** a `500 GiB` EBS volume per host, mounted at `/data` but only ~10 GiB would ever be used | Pins one task per instance and pays for ~490 GiB of idle disk — wasted spend, no functional impact | Set `cpu = 256` and `extra_ebs_volume_size_gb = 0` (or right-size to ~10) |
| 2 | **Pipeline** — `Jenkinsfile` (`dockerLogged`) | Every docker command’s full output is uploaded to its own S3 object every build | Redundant multi-KB log objects inflate S3 storage + PUT costs | Log to console/CloudWatch; archive one consolidated log per build |
| 3 | **Script** — `scripts/verify_health.sh` | Endpoint probed 3× per attempt when 1 probe suffices | Triples request + log volume (feeds flaw #2) with no reliability gain | Probe once per attempt |

**How they interlink:** the over-allocated CPU (1) spins up more/underused EC2 capacity;
the redundant health probes (3) generate extra command output; and the pipeline (2)
faithfully ships every byte of that output to S3 — so a single deploy compounds cost
across compute, logging, and requests.

---

## Design decisions (cost / speed / complexity)

- **ECS-on-EC2 with `t3.micro`** rather than Fargate: free-tier eligible and cheapest
  for a couple of always-on containers; a single shared NAT gateway per VPC keeps egress
  costs down while still allowing image pulls from private subnets.
- **Reusable module** for both workloads: less duplication, consistent security posture,
  faster to review and extend. Jenkins vs app differ only by inputs (image, port,
  count, health path, task role).
- **Bridge networking + dynamic ports**: lets multiple tasks share a host and keeps the
  target group simple; avoids the ENI-per-task limits that would bite `t3.micro` with
  `awsvpc`.
- **WAF for geo-restriction** instead of SG CIDR lists: security groups can’t match on
  country; a WAFv2 geo-match is the correct, low-maintenance control.
- **Self-signed ACM cert**: satisfies HTTPS-only with zero cost and no domain
  dependency, keeping the stack self-contained for review.
- **`us-east-1` provider alias**: AWS publishes Billing and Route53 health-check metrics
  only in `us-east-1`, so the cost + health-check alarms (and their SNS topic) live there.
- **30-day S3 log expiry + ECR image pruning**: bounds storage cost automatically.

---

## Usage

### Prerequisites
- Terraform >= 1.5, AWS credentials for `eu-central-1`, Docker (for the pipeline).

### Deploy the infrastructure
```bash
cd terraform/environments/dev
cp terraform.tfvars.example terraform.tfvars   # edit alarm_email etc.
terraform init
terraform plan
terraform apply
```
Confirm the **SNS subscription email** (two topics: regional + `us-east-1`) so alarms
deliver. Enable AWS billing alerts in the account for the cost alarm to receive data.

### Build & deploy the app (Jenkins)
Run the pipeline manually, supplying the parameters from Terraform outputs:
```bash
terraform output ecr_repository_url app_ecs_cluster app_ecs_service app_url log_bucket_name
```

### Pre-commit
```bash
pip install pre-commit && pre-commit install
pre-commit run --all-files
```

### Secrets
Sensitive credentials are managed with **Transcrypt** (git-crypt-style transparent
encryption): `.gitattributes` maps `secrets/**` and `*.enc` to Transcrypt's `crypt`
filter (see `secrets/README.md` for the one-time `transcrypt` init). Decrypted copies
are never committed (see `.gitignore`). As a second layer, **`detect-secrets`** runs as
a pre-commit hook against `.secrets.baseline` to block accidental plaintext secrets. The
two coexist cleanly: detect-secrets `exclude`s the Transcrypt paths (`secrets/**`,
`*.enc`), since encrypted ciphertext is high-entropy and would otherwise trip the
entropy detectors — so it only guards against *unencrypted* leaks elsewhere.

---

## Notes / caveats
- The self-signed certificate means clients must accept an untrusted cert; the health
  script uses `curl -k` accordingly.
- Route53 health checks probe the public ALB DNS directly (no hosted zone required).
- This is a **challenge artifact**: the three flaws are intentional and documented — do
  not "fix" them without noting it, as they are the point of the review.
