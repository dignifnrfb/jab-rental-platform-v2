# Security Policy

## Reporting a Vulnerability

Please **do not** file public issues for security problems.

To report a vulnerability:

- Open a private security advisory under **Security → Report a vulnerability** on this repository, or
- Reach out to the maintainer through the contact details on their GitHub profile.

You'll get an acknowledgement within 7 days. Confirmed issues will be patched, the patch tagged, and the reporter credited (with permission) in the release notes.

## Known Issues / Audit Notes

### `.env` previously tracked in git

A `.env` file with development-grade credentials was committed in the initial revision of this repository. It is now gitignored, but the file (and its contents) remains in git history.

**Severity:** Medium. The file mostly contains placeholder values (e.g. `your_amap_api_key`, `your_app_password`), but the following fields used **predictable defaults** that should be considered burned:

- `DATABASE_URL` / `DB_PASSWORD` — `jab_secure_2024`
- `REDIS_PASSWORD` — `redis_secure_2024`
- `NEXTAUTH_SECRET` — `jab_nextauth_secret_key_ubuntu_2024_production`
- `JWT_SECRET` — `jab_jwt_secret_key_ubuntu_2024_production`

If these values are reused in any deployed environment, **rotate them immediately**.

### Remediation Steps

If you are an operator of a JAB rental deployment, follow these steps:

1. **Rotate every secret** that ever lived in this `.env`:

   ```sql
   -- PostgreSQL
   ALTER USER jab_user WITH PASSWORD '<new strong random>';
   ```

   ```bash
   # Redis
   redis-cli CONFIG SET requirepass '<new strong random>'
   redis-cli CONFIG REWRITE
   ```

2. **Generate fresh app secrets**:

   ```bash
   openssl rand -base64 48   # NEXTAUTH_SECRET
   openssl rand -base64 48   # JWT_SECRET
   ```

   Update your deployment's `.env` (which must remain untracked) with the new values.

3. **Untrack the file in the working tree** (one-time, by maintainer):

   ```bash
   git rm --cached .env
   git commit -m "security: untrack .env (already gitignored)"
   git push
   ```

4. **Optional — scrub history.** If you want to remove the file from past commits, use [`git-filter-repo`](https://github.com/newren/git-filter-repo):

   ```bash
   pip install git-filter-repo
   git filter-repo --path .env --invert-paths
   git push --force-with-lease origin main
   ```

   Note: this rewrites history, so all clones must re-pull. GitHub also caches blob views in PRs / forks for some time.

5. **Verify**:

   ```bash
   git log --all --full-history --diff-filter=A -- .env
   git ls-files | grep -E '^\.env$'   # should print nothing
   ```

## Supported Versions

This project is in early-stage development. Only the `main` branch is supported; all fixes land there first.

| Version | Supported |
| ------- | --------- |
| `main`  | ✅        |
| Older tags | ❌    |
