# SonarCloud Setup Guide

---

## Prerequisites
- GitHub account
- Public GitHub repository

---

## Step 1 — Sign up on SonarCloud

- Go to sonarcloud.io
- Click **Log in with GitHub**
- Authorize SonarCloud to access your GitHub account
- Confirm access on GitHub (use password or GitHub Mobile)

---

## Step 2 — Create Organization

- Click **"Create organization"** (top right)
- Select **"Import from GitHub"**
- Select your GitHub username/organization
- Choose **Free plan**
- Click **Create organization**

---

## Step 3 — Create Project

- Click **"Analyze new project"**
- Select your repo
- Click **Set up**
- Choose **Free plan**
- Select **"Previous version"** as new code definition
- Click **Create project**

---

## Step 4 — Get Project Key and Organization Key

- **Organization Key** — visible in the browser URL:
  ```
  sonarcloud.io/organizations/<your-org-key>/projects
  ```
- **Project Key** — visible in the browser URL on project page:
  ```
  sonarcloud.io/project/overview?id=<your-project-key>
  ```

---

## Step 5 — Generate SONAR_TOKEN

- SonarCloud → top right avatar → **My Account**
- Click **Security**
- Under **Generate Tokens**:
  - Name: `github-actions`
  - Type: `Global Analysis Token`
- Click **Generate**
- **Copy the token immediately** — it is shown only once

---

## Step 6 — Add SONAR_TOKEN to GitHub Secrets

- Go to GitHub → your repo
- **Settings → Secrets and variables → Actions**
- Click **New repository secret**
- Name: `SONAR_TOKEN`
- Value: paste the copied token
- Click **Add secret**

---

## Step 7 — Add sonar-project.properties

Create `sonar-project.properties` at the repo root:

```properties
sonar.projectKey=<your-project-key>
sonar.organization=<your-org-key>
sonar.projectName=<your-project-name>

sonar.sources=app
sonar.exclusions=**/node_modules/**,**/test/**,**/*.spec.ts,**/dist/**
```

---

## Step 8 — Add sast job to ci.yml

```yaml
  sast:
    runs-on: ubuntu-latest
    needs: secret-scan
    env:
      FORCE_JAVASCRIPT_ACTIONS_TO_NODE24: true

    steps:
      - name: Checkout code
        uses: actions/checkout@v4.2.2
        with:
          fetch-depth: 0

      - name: SonarCloud Scan
        uses: SonarSource/sonarcloud-github-action@master
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
```

---

## Verification

After pushing, check:
- GitHub Actions → `sast` job should pass
- SonarCloud dashboard → project should show scan results with vulnerabilities found
