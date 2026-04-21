# Gitleaks — Learning Notes

---

## 1. What is Gitleaks?

Gitleaks is an open source tool that scans your code and git history for
hardcoded secrets — API keys, passwords, tokens, private keys etc.

**The problem it solves:**
Developers sometimes accidentally commit secrets into code:
```javascript
const dbPassword = "MySecret123"          // hardcoded password
const apiKey = "sk-1234abcd..."           // hardcoded API key
const awsSecret = "wJalrXUtnFEMI/K7MD"   // AWS secret key
```
Once pushed to GitHub (especially a public repo), these secrets are exposed
and can be used by attackers. Gitleaks catches these BEFORE they cause damage.

**In simple terms:**
> "Scan every file and every commit for anything that looks like a secret — block the pipeline if found"

---

## 2. How Gitleaks Works

Gitleaks uses **regex patterns** to detect secrets. It has a built-in ruleset
of 150+ patterns covering:

| What it detects | Example pattern it looks for |
|---|---|
| AWS Access Keys | `AKIA[0-9A-Z]{16}` |
| GitHub Tokens | `ghp_[a-zA-Z0-9]{36}` |
| Stripe API Keys | `sk_live_[0-9a-zA-Z]{24}` |
| Google API Keys | `AIza[0-9A-Za-z-_]{35}` |
| Private Keys | `-----BEGIN RSA PRIVATE KEY-----` |
| Passwords in URLs | `https://user:password@host` |
| Generic secrets | `password = "..."`, `secret = "..."` |

---

## 3. Two Scan Modes

### detect mode
Scans the current state of the code (all files as they exist now)
```bash
gitleaks detect --source .
```

### protect mode
Scans only the changes in the latest commit (used in pre-commit hooks)
```bash
gitleaks protect --staged
```

In our CI pipeline we use **detect mode** — scans everything on every push.

---

## 4. Gitleaks in GitHub Actions

We use the official Gitleaks GitHub Action:
```yaml
- uses: gitleaks/gitleaks-action@v2
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

`GITHUB_TOKEN` is a special secret that GitHub automatically creates for every
repo — you do not need to create it manually. It allows Gitleaks to post
scan results back to GitHub.

### What happens when Gitleaks finds a secret:
- Pipeline **fails immediately**
- GitHub Actions step turns red
- Gitleaks prints exactly which file and line number contains the secret
- No further jobs run — image never gets built or pushed

### What happens when no secrets found:
- Step passes with exit code 0
- Pipeline continues to next job

---

## 5. .gitleaks.toml — Custom Config File

You can configure Gitleaks using a `.gitleaks.toml` file in your repo root.
Common uses:

### Allow known false positives
Juice Shop is intentionally vulnerable — it has demo secrets that are NOT real.
Without configuration, Gitleaks would fail on these every time.
We tell Gitleaks to ignore them:

```toml
[allowlist]
  description = "Allowlist for known false positives in Juice Shop"
  paths = [
    '''app/data/static''',        # demo challenge data
    '''app/frontend/src/assets''' # frontend assets
  ]
```

### Add custom rules
```toml
[[rules]]
  id = "custom-internal-token"
  description = "Detects internal API tokens"
  regex = '''INT-[0-9a-f]{32}'''
  severity = "ERROR"
```

---

## 6. Gitleaks in Our Pipeline

```
push to main
     │
     ▼
Job 1: secret-scan  (Gitleaks)   ← NEW
     │
     ▼
Job 2: sast         (SonarQube)  ← coming next
     ...
```

Gitleaks runs FIRST — before any build or scan.
Reason: no point running expensive scans if there are exposed secrets.

---

## 7. Key Things to Remember

- Gitleaks scans file contents AND git history — old commits are also checked
- `GITHUB_TOKEN` is auto-created by GitHub, you never need to create it
- `.gitleaks.toml` is how you manage false positives
- Juice Shop has intentional demo secrets — always needs an allowlist
- If Gitleaks fails, fix the secret BEFORE pushing again
- Never fix by just deleting the secret from the file — it's still in git history
  - Correct fix: use `git filter-repo` to remove from history, then rotate the secret

---

## 8. Our .gitleaks.toml Implementation

```toml
[allowlist]
  description = "Allowlist for known false positives in OWASP Juice Shop"
  paths = [
    '''app/data/static''',          # challenge data files — contain fake demo secrets
    '''app/frontend/src/assets''',  # frontend assets — contain demo keys for CTF challenges
    '''app/data/datacreator.ts''',  # seeds the database with demo users/passwords
    '''app/lib/insecurity.ts'''     # intentionally insecure helper — has hardcoded demo JWTs
  ]
```

**Why we need this:**
Juice Shop is intentionally vulnerable. It has fake secrets hardcoded on purpose
for CTF challenges. Without this file, Gitleaks would detect those fake secrets
and fail every single pipeline run.

**Without .gitleaks.toml:**
```
Gitleaks found: hardcoded JWT in app/lib/insecurity.ts → PIPELINE FAILS
```

**With .gitleaks.toml:**
```
Gitleaks skipped app/lib/insecurity.ts → scans everything else → PASSES
```

---

## 9. Real World Usage

In enterprise, Gitleaks is used at two levels:
1. **Pre-commit hook** — catches secrets on developer machine before push
2. **CI pipeline** — catches anything that slipped through pre-commit

Our project uses it at the CI level (Phase 1 of the security pipeline).
