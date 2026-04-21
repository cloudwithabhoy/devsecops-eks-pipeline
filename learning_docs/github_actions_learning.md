# GitHub Actions — Learning Notes

---

## 1. What is GitHub Actions?

GitHub Actions is a CI/CD platform built directly into GitHub.
It allows you to automatically run tasks (build, test, scan, deploy) whenever
something happens in your repository — like a code push or a pull request.

Before GitHub Actions, teams used separate tools like Jenkins, CircleCI, or
Travis CI and had to connect them to GitHub manually. GitHub Actions is built-in,
so no extra setup or server needed to get started.

**In simple terms:**
> "Something happens in my repo → GitHub Actions automatically runs a set of tasks"

---

## 2. Core Concepts

### Workflow
- A workflow is an automated process defined in a YAML file
- Stored in `.github/workflows/` folder in your repo
- One repo can have multiple workflows (one for CI, one for deploy, one for security scan)
- Each workflow runs independently

```
.github/
└── workflows/
    ├── ci.yml           ← runs on every push
    ├── security.yml     ← runs security scans
    └── deploy.yml       ← deploys to EKS
```

---

### Event (Trigger)
- An event is what STARTS a workflow
- You define this using the `on:` keyword in the YAML

Common events:

| Event | When it triggers |
|---|---|
| `push` | Every time code is pushed to a branch |
| `pull_request` | When a PR is opened or updated |
| `schedule` | On a cron schedule (e.g. every night at 2am) |
| `workflow_dispatch` | Manually triggered from GitHub UI |

Example:
```yaml
on:
  push:
    branches:
      - main        # only triggers when pushing to main branch
```

---

### Job
- A job is a GROUP of steps that run together on the same machine
- One workflow can have multiple jobs
- By default, jobs run IN PARALLEL
- You can make jobs depend on each other using `needs:`

```yaml
jobs:
  security-scan:      # job 1
    ...

  build:              # job 2 - runs at same time as job 1 by default
    needs: security-scan   # unless you add this - then it waits
    ...
```

---

### Step
- A step is a SINGLE task inside a job
- Steps run IN ORDER, one after another
- A step can either:
  - Run a shell command using `run:`
  - Use a pre-built action using `uses:`

```yaml
steps:
  - name: Print hello        # step 1
    run: echo "Hello World"

  - name: Show current dir   # step 2
    run: pwd

  - name: List files         # step 3
    run: ls -la
```

---

### Runner
- A runner is the MACHINE (server) where your job runs
- GitHub provides free runners (Ubuntu, Windows, Mac)
- You can also host your own runner (called self-hosted runner)

Most common runner used in projects:
```yaml
runs-on: ubuntu-latest    # free GitHub-hosted Ubuntu machine
```

When a workflow triggers:
1. GitHub spins up a fresh Ubuntu VM
2. Runs all your steps on it
3. VM is destroyed after the job finishes

This means every run starts clean — no leftover files from previous runs.

---

### Action
- An action is a PRE-BUILT, reusable step made by the community or GitHub
- You use them with `uses:` keyword
- Think of them like npm packages but for CI/CD steps
- Published on GitHub Marketplace

Example — instead of writing 10 lines to checkout your code, you use:
```yaml
- uses: actions/checkout@v4    # official GitHub action to checkout code
```

Other examples:
```yaml
- uses: actions/setup-node@v4          # install Node.js
- uses: docker/login-action@v3         # login to Docker registry
- uses: aquasecurity/trivy-action@v1   # run Trivy scan
```

---

## 3. Full Workflow Structure

```yaml
name: CI Pipeline          # display name on GitHub UI

on:                        # TRIGGER - what starts this workflow
  push:
    branches:
      - main

jobs:                      # list of jobs

  build:                   # job name (you choose this)
    runs-on: ubuntu-latest # RUNNER - what machine to use

    steps:                 # list of steps inside this job

      - name: Checkout code          # step 1
        uses: actions/checkout@v4    # uses a pre-built action

      - name: Install dependencies   # step 2
        run: npm install             # runs a shell command

      - name: Run tests              # step 3
        run: npm test
```

---

## 4. How Our Pipeline Will Look

In this project, our workflow will have these jobs in order:

```
push to main
     │
     ▼
Job 1: secret-scan      (Gitleaks)
     │
     ▼
Job 2: sast             (SonarQube)
     │
     ▼
Job 3: dependency-scan  (Trivy filesystem)
     │
     ▼
Job 4: iac-scan         (Checkov)
     │
     ▼
Job 5: build-and-scan   (Docker build + Trivy image)
     │
     ▼
Job 6: push-to-ecr      (only if all above pass)
```

Each job WAITS for the previous one using `needs:`.
If any job FAILS, the pipeline stops — image never reaches ECR.

---

## 5. Key Things to Remember

- Workflow files MUST be in `.github/workflows/` — anywhere else and GitHub ignores them
- File extension must be `.yml` or `.yaml`
- Indentation in YAML matters — use 2 spaces, never tabs
- Each workflow run has logs visible on GitHub under the "Actions" tab
- Free tier gives 2000 minutes/month for private repos (public repos are unlimited)
- Environment variables are set using `env:` keyword
- Secrets (API keys, passwords) are stored in GitHub repo Settings → Secrets — never hardcode them in YAML

---

## 6. First Workflow — ci.yml Explained

This is the first workflow written for the `devsecops-eks-pipeline` project.

```yaml
name: DevSecOps pipeline        # display name on GitHub Actions tab

on:
  push:
    branches:
      - main                    # triggers only when code is pushed to main branch

jobs:
  pipeline-info:                # job name — you choose this
    runs-on: ubuntu-latest      # GitHub spins up a fresh Ubuntu VM for this job

    steps:
      - name: checkout code
        uses: actions/checkout@v4   # checks out repo code onto the VM
                                    # without this, VM has no access to your files

      - name: show branch name
        run: echo "Running on branch ${{ github.ref_name }}"
        # ${{ github.ref_name }} is a GitHub context variable
        # automatically filled with the branch name at runtime

      - name: show commit details
        run: |                      # | means multi-line command
          echo "Commit SHA : ${{ github.sha }}"        # hash of the commit that triggered this
          echo "Triggered by : ${{ github.actor }}"    # GitHub username who pushed
          echo "Repository : ${{ github.repository }}" # username/repo-name

      - name: List project structure
        run: ls -la                 # lists all files checked out from your repo on the VM
```

### What happens when you push to main:
1. GitHub detects the push event
2. Spins up a fresh Ubuntu VM
3. Runs all 4 steps in order
4. You can see the output logs in GitHub → Actions tab
5. VM is destroyed after job finishes

### Common mistake made:
- `brances:` instead of `branches:` — GitHub ignores the trigger silently
- Always double check spelling of YAML keys

---

## 7. secret-scan Job — ci.yml Explained

This is the second job added to `ci.yml` for Gitleaks secret scanning.

```yaml
  secret-scan:
    runs-on: ubuntu-latest
    needs: pipeline-info                # waits for pipeline-info to finish first
                                        # if pipeline-info fails, this never runs
    env:
      FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true

    steps:
      - name: Checkout code
        uses: actions/checkout@v4.2.2
        with:
          fetch-depth: 0                # fetch FULL git history, not just latest commit
                                        # Gitleaks needs this to scan all past commits
                                        # without this, it only sees the latest commit

      - name: Run Gitleaks
        uses: gitleaks/gitleaks-action@v2    # official Gitleaks action from marketplace
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}   # auto-created by GitHub for every repo
                                                      # you never need to create this manually
```

### Why fetch-depth: 0 matters
- By default GitHub Actions does a shallow clone — only fetches the latest commit
- Gitleaks needs full history to scan ALL previous commits
- Without it, a secret committed 10 commits ago would never be caught

### Pipeline flow after adding secret-scan:
```
push to main
     ↓
pipeline-info runs
     ↓ (only if pipeline-info passes)
secret-scan runs
     ↓ secret found        ↓ no secrets found
  PIPELINE FAILS        pipeline continues
```

---

## 8. build-scan Job — ci.yml Explained

This is the sixth job added to `ci.yml`. It builds the Docker image and scans it with Trivy.

```yaml
  build-scan:                          # job name
    runs-on: ubuntu-latest             # fresh Ubuntu VM for this job
    needs: iac-scan                    # only runs if Checkov passes
                                       # no point building image if IaC is broken
    env:
      FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true   # suppress Node.js deprecation warnings

    steps:
      - name: Checkout code
        uses: actions/checkout@v4.2.2  # downloads repo files onto the VM
                                       # needed so Docker can find app/Dockerfile

      - name: Build Docker image
        run: docker build -t juice-shop:${{ github.sha }} ./app
        # docker build     → builds the image using app/Dockerfile
        # -t               → tag flag, gives the image a name
        # juice-shop:      → image name
        # ${{ github.sha }} → commit SHA used as the image tag (e.g. juice-shop:a3f9c12...)
        #                     every commit gets a unique tag — no ambiguity about which build
        # ./app            → build context — Docker looks for Dockerfile here

      - name: Trivy image scan
        uses: aquasecurity/trivy-action@master   # official Trivy action
        with:
          scan-type: image             # scans a Docker image (not filesystem)
                                       # checks OS packages + libraries baked into image layers
          image-ref: juice-shop:${{ github.sha }}  # must match the -t tag from build step exactly
          severity: CRITICAL           # only report CRITICAL findings
                                       # Juice Shop has many HIGH/MEDIUM intentionally
          exit-code: 1                 # if CRITICAL found → job fails → pipeline stops
                                       # without this, Trivy just prints and pipeline continues
          format: table                # output as readable table in GitHub Actions logs
          ignore-unfixed: true         # skip CVEs with no patch available — can't fix what has no fix
```

### What Trivy image scan checks (vs filesystem scan)

| | `sca` job (fs scan) | `build-scan` job (image scan) |
|---|---|---|
| What it scans | `package.json` source deps | Every layer inside the built Docker image |
| Catches | Vulnerable npm packages in code | OS packages + npm packages baked into image |
| Runs | Before Docker build | After Docker build |
| Why both? | Cheap early check | Final check on the actual artifact that gets deployed |

### Pipeline flow after adding build-scan:
```
push to main
     ↓
pipeline-info  ✓
     ↓
secret-scan    ✓  (Gitleaks)
     ↓
sast           ✓  (SonarCloud)
     ↓
sca            ✓  (Trivy filesystem)
     ↓
iac-scan       ✓  (Checkov)
     ↓
build-scan     ✓  (Docker build + Trivy image scan)
     ↓ CRITICAL found    ↓ no CRITICAL found
  PIPELINE FAILS      pipeline continues → push-to-ecr (next)
```

---

## 9. build-scan-push Job — Push to ECR Explained

Phase 8 extended the `build-scan` job into `build-scan-push` — build, scan, and push all in one job.

### Why one job and not separate?
Each job runs on a **separate fresh VM**. The Docker image built in one job does not exist on the next job's VM. Build + scan + push must share the same VM.

```yaml
  build-scan-push:
    runs-on: ubuntu-latest
    needs: iac-scan
    env:
      FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true
    steps:
      - name: Checkout code
        uses: actions/checkout@v4.2.2

      - name: Build Docker image
        run: docker build -t juice-shop:${{ github.sha }} ./app

      - name: Trivy image scan
        uses: aquasecurity/trivy-action@master
        with:
          scan-type: image
          image-ref: juice-shop:${{ github.sha }}
          severity: CRITICAL
          exit-code: 1
          format: table
          ignore-unfixed: true

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ap-south-1

      - name: Login to Amazon ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v2

      - name: Tag and push image to ECR
        run: |
          ECR_URL=${{ secrets.AWS_ACCOUNT_ID }}.dkr.ecr.ap-south-1.amazonaws.com/devsecops-eks-dev
          docker tag juice-shop:${{ github.sha }} $ECR_URL:${{ github.sha }}
          docker push $ECR_URL:${{ github.sha }}
```

### New steps explained

**Configure AWS credentials:**
- `aws-actions/configure-aws-credentials@v4` — official AWS action that sets up AWS auth on the runner VM
- Reads `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` from GitHub Secrets
- Without this, no AWS CLI or SDK command works
- `aws-region` must match the region where ECR was created (ap-south-1)

**Login to ECR:**
- `aws-actions/amazon-ecr-login@v2` — runs `docker login` against your private ECR automatically
- After this step, Docker is authenticated and can push to ECR
- `id: login-ecr` — names this step so other steps can reference its outputs

**Tag and push:**
- `ECR_URL` — full ECR repo address: `{account_id}.dkr.ecr.{region}.amazonaws.com/{repo_name}`
- `AWS_ACCOUNT_ID` stored as a secret — account ID never exposed in code
- `docker tag` — adds the ECR URL as a new tag on the locally built image
- SHA-only tag — no `latest` tag because:
  - ECR has `image_tag_mutability = IMMUTABLE` — `latest` would be rejected on second push
  - SHA is immutable — always traceable to exact commit
  - SHA will be auto-updated in Helm values by CI (GitOps pattern, Phase 9)
- `docker push` — sends the image layers to ECR

### GitHub Secrets required
| Secret | Value |
|---|---|
| `AWS_ACCESS_KEY_ID` | IAM user access key |
| `AWS_SECRET_ACCESS_KEY` | IAM user secret key |
| `AWS_ACCOUNT_ID` | 12-digit AWS account number |

Add these in: GitHub repo → Settings → Secrets and variables → Actions

### Full pipeline after Phase 8:
```
push to main
     ↓
pipeline-info  ✓
     ↓
secret-scan    ✓  (Gitleaks)
     ↓
sast           ✓  (SonarCloud)
     ↓
sca            ✓  (Trivy filesystem)
     ↓
iac-scan       ✓  (Checkov)
     ↓
build-scan-push ✓  (Docker build → Trivy scan → push to ECR)
     ↓
[ArgoCD detects new image → deploys to EKS — Phase 9]
```

---

## 10. Useful Terms Cheatsheet

| Term | One Line Explanation |
|---|---|
| Workflow | The full automation file (.yml) |
| Event | What triggers the workflow (push, PR, schedule) |
| Job | A group of steps running on one machine |
| Step | A single command or action inside a job |
| Runner | The machine (VM) that runs the job |
| Action | A reusable pre-built step from the marketplace |
| `needs:` | Makes a job wait for another job to finish |
| `env:` | Sets environment variables |
| `secrets:` | Secure way to use passwords/tokens in workflows |
| `uses:` | Uses a pre-built action |
| `run:` | Runs a raw shell command |
