# SonarQube — Learning Notes

---

## 1. What is SonarQube?

SonarQube is a SAST (Static Application Security Testing) tool.
It analyzes your SOURCE CODE without running it — looking for:

- Security vulnerabilities (SQL injection, XSS, hardcoded passwords)
- Bugs (null pointer, logic errors)
- Code smells (bad practices, duplicated code)
- Coverage gaps (untested code)

**In simple terms:**
> "Read the code line by line, find problems before the app ever runs"

---

## 2. SonarQube vs SonarCloud

| | SonarQube | SonarCloud |
|---|---|---|
| Hosting | Self-hosted (your server) | Cloud (SaaS) |
| Cost | Free Community Edition | Free for public repos |
| Setup | Install + configure server | Just sign up |
| Used in | Enterprise (private infra) | Startups, open source, learning |

**We use SonarCloud** — same concepts as SonarQube, no server to manage,
free for public repos. In interviews, knowing SonarCloud = knowing SonarQube.

---

## 3. How SAST Works

```
Source Code
     ↓
SonarQube parses the code into AST (Abstract Syntax Tree)
     ↓
Applies 3000+ rules against the AST
     ↓
Reports: Vulnerabilities, Bugs, Code Smells
     ↓
Quality Gate: PASS or FAIL
```

It never runs the application — purely reads and analyzes code.

---

## 4. Quality Gate

A Quality Gate is a set of conditions that must pass for the pipeline to continue.

Default quality gate conditions:
- 0 new bugs
- 0 new vulnerabilities
- Code coverage > 80%
- Duplicated lines < 3%

If any condition fails → Quality Gate FAILS → Pipeline stops.

In our project we use the default quality gate.

---

## 5. Key Concepts

### Issue Severity Levels

| Severity | Meaning |
|---|---|
| BLOCKER | Must fix — app will likely crash or have critical security hole |
| CRITICAL | Must fix — serious security vulnerability |
| MAJOR | Should fix — significant bug or vulnerability |
| MINOR | Nice to fix — small issue |
| INFO | Just informational |

### Issue Types

| Type | Meaning |
|---|---|
| Vulnerability | Security issue that can be exploited |
| Bug | Code that will produce wrong result |
| Code Smell | Bad practice that makes code hard to maintain |
| Security Hotspot | Code that needs manual security review |

---

## 6. sonar-project.properties

This file tells SonarQube what to scan and how.
It lives at the root of your repo.

```properties
sonar.projectKey=your-org_your-repo       # unique identifier on SonarCloud
sonar.organization=your-org               # your SonarCloud organization name
sonar.projectName=DevSecOps EKS Pipeline  # display name on SonarCloud dashboard

sonar.sources=app                         # which folder to scan
sonar.exclusions=**/node_modules/**,**/test/**   # what to skip
sonar.javascript.lcov.reportPaths=coverage/lcov.info  # test coverage report path
```

---

## 7. SonarQube in GitHub Actions

```yaml
- name: SonarCloud Scan
  uses: SonarSource/sonarcloud-github-action@master
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}  # for PR decoration
    SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}    # from SonarCloud — add to GitHub secrets
```

`SONAR_TOKEN` — you generate this from SonarCloud dashboard and store it
in GitHub repo Settings → Secrets. SonarQube uses it to authenticate and
push scan results to your SonarCloud project.

---

## 8. Setup Steps (One Time)

1. Go to sonarcloud.io → Sign up with GitHub
2. Create organization (use your GitHub username)
3. Create new project → select your repo
4. Copy the `projectKey` and `organization` values
5. Go to SonarCloud → My Account → Security → Generate Token
6. Copy the token
7. Go to GitHub repo → Settings → Secrets → New secret
8. Name: `SONAR_TOKEN`, Value: paste the token
9. Add `sonar-project.properties` file to repo root
10. Add SonarCloud step to `ci.yml`

---

## 9. SonarQube in Our Pipeline

```
push to main
     ↓
pipeline-info   ✓
     ↓
secret-scan     ✓  (Gitleaks)
     ↓
sast            ←  NEW (SonarCloud)
     ↓ quality gate fails   ↓ quality gate passes
  PIPELINE FAILS         pipeline continues
```

---

## 10. Reading the SonarCloud Dashboard

### Quality Gate Status
- Shows PASS or FAIL
- FAIL means one or more conditions were not met
- In our project it FAILED — expected because Juice Shop is intentionally vulnerable

### Open Issues
- Total count of bugs + vulnerabilities + code smells found
- Our scan found 486 issues across Juice Shop

### Duplications
- Percentage of duplicated code
- 4.8% in our project — acceptable but worth improving in real projects

### Coverage
- Percentage of code covered by tests
- 0.0% — we have not configured test coverage reports yet

### Security Rating
- Grades from A (best) to E (worst)
- Our project got E — because of 32 security vulnerabilities
- In a real project, target should be A or B

### Security Issues
- Actual security vulnerabilities found in the code
- Our scan found 32 security issues:
  - 81% Blocker (26 issues) — SQL injection, XSS, hardcoded secrets
  - 19% Medium (6 issues)

### In a Real Project Workflow
```
SonarCloud scan runs
     ↓ issues found
Developer fixes BLOCKER and CRITICAL issues
     ↓
Re-scan
     ↓ quality gate passes
Pipeline continues to next stage
```

---

## 11. Key Things to Remember

- SONAR_TOKEN must be stored in GitHub Secrets — never hardcode it in YAML
- sonar-project.properties must be at the repo ROOT — not inside app/
- SonarCloud is free for public repos — no credit card needed
- Juice Shop is intentionally vulnerable — SonarQube WILL find issues
  This is expected and actually makes the project more realistic
- Quality Gate failing on Juice Shop is normal — shows the tool is working
- In real projects you fix the issues — here you understand what was found
