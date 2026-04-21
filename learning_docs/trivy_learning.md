# Trivy — Learning Notes

---

## 1. What is Trivy?

Trivy is an open source security scanner by Aqua Security.
It is the most widely used container and code scanner in the industry.

**What makes it special:**
One tool replaces three — it scans dependencies, container images, AND
infrastructure code. Most teams used separate tools before Trivy existed.

**In simple terms:**
> "Point Trivy at anything — code, Docker image, Terraform — it finds vulnerabilities"

---

## 2. What Trivy Scans

| Scan Type | What it checks | Command |
|---|---|---|
| Filesystem (fs) | Dependencies in package.json, requirements.txt etc. | `trivy fs .` |
| Image | OS packages + libraries inside a Docker image | `trivy image myapp:latest` |
| Config | Terraform, Kubernetes YAML misconfigurations | `trivy config ./terraform` |
| Repo | Remote git repository | `trivy repo github.com/org/repo` |

In our pipeline we use **fs mode** and **image mode**.

---

## 3. What Trivy Finds

### In Filesystem mode (SCA — Software Composition Analysis)
Scans dependency files for known CVEs:
```
package.json          → Node.js dependencies
requirements.txt      → Python dependencies
Gemfile.lock          → Ruby dependencies
pom.xml               → Java dependencies
go.sum                → Go dependencies
```

Example finding:
```
lodash 4.17.15   → CVE-2021-23337  → CRITICAL  → Prototype Pollution
axios 0.21.0     → CVE-2021-3749   → HIGH      → ReDoS vulnerability
```

### In Image mode
Scans Docker image layers for:
- OS package vulnerabilities (Ubuntu, Alpine packages)
- Language library vulnerabilities (npm, pip packages baked into image)

Example finding:
```
openssl 1.1.1f   → CVE-2022-0778   → CRITICAL  → Infinite loop in BN_mod_sqrt()
libssl 1.1.1f    → CVE-2021-3711   → CRITICAL  → SM2 Decryption Buffer Overflow
```

---

## 4. Severity Levels

| Severity | Meaning | Action |
|---|---|---|
| CRITICAL | Actively exploited, patch immediately | Block pipeline |
| HIGH | Serious vulnerability | Block pipeline |
| MEDIUM | Moderate risk | Report only |
| LOW | Minor risk | Report only |
| UNKNOWN | Not enough data | Report only |

In our pipeline we **block on CRITICAL** severity only.
Blocking on HIGH would fail too often on Juice Shop.

---

## 5. Trivy in GitHub Actions

### Filesystem scan (SCA):
```yaml
- name: Trivy filesystem scan
  uses: aquasecurity/trivy-action@master
  with:
    scan-type: fs
    scan-ref: ./app
    severity: CRITICAL
    exit-code: 1           # fail pipeline if CRITICAL found
    format: table          # output format
```

### Image scan:
```yaml
- name: Trivy image scan
  uses: aquasecurity/trivy-action@master
  with:
    scan-type: image
    image-ref: myapp:latest
    severity: CRITICAL
    exit-code: 1
    format: table
```

---

## 6. Key Parameters Explained

| Parameter | What it does |
|---|---|
| `scan-type` | fs, image, or config |
| `scan-ref` | what to scan — folder path or image name |
| `severity` | which severities to report (CRITICAL,HIGH,MEDIUM,LOW) |
| `exit-code: 1` | fail the pipeline if vulnerabilities found at that severity |
| `exit-code: 0` | report vulnerabilities but do NOT fail the pipeline |
| `format` | output format — table, json, sarif |
| `ignore-unfixed` | skip vulnerabilities with no fix available |

---

## 7. Trivy in Our Pipeline

```
push to main
     ↓
pipeline-info   ✓
     ↓
secret-scan     ✓  (Gitleaks)
     ↓
sast            ✓  (SonarCloud)
     ↓
sca             ✓  (Trivy filesystem — dependency scan)
     ↓
iac-scan        ✓  (Checkov)
     ↓
build-scan      ✓  (Docker build + Trivy image scan)
```

### Why two separate Trivy jobs?
- `sca` runs early — scans source code dependencies BEFORE building image
- `build-scan` runs later — scans the final Docker image AFTER building
- Catching issues in source is cheaper than catching them after a build

### build-scan job (Phase 7)
```yaml
build-scan:
  runs-on: ubuntu-latest
  needs: iac-scan
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
```

---

## 8. .trivyignore File

Similar to `.gitleaks.toml`, you can create a `.trivyignore` file to
suppress known false positives or accepted risks:

```
# CVE accepted by security team — no fix available
CVE-2022-1234
CVE-2021-5678
```

---

## 9. Key Things to Remember

- Trivy pulls its vulnerability database from the internet on first run
  (adds ~30 seconds to pipeline)
- `exit-code: 1` is what actually FAILS the pipeline — without it Trivy
  just reports and pipeline continues
- Juice Shop has intentional vulnerabilities — CRITICAL findings are expected
- In real projects you fix CRITICAL vulnerabilities before merging
- `ignore-unfixed: true` skips CVEs where no patch exists yet — useful to
  reduce noise in pipeline output
