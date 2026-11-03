# grype-db-mirror

Republishes each Anchore grype v6 vulnerability database build as a GitHub release, for networks
that reach GitHub but not Anchore.

## Requirements

- A public GitHub repository with Actions enabled. The `sync` workflow runs on `ubuntu-24.04`.
- `sync.sh` by hand: `bash`, `curl`, `jq`, `sha256sum` and an authenticated `gh` CLI.
- Clients: a grype release that reads schema v6 databases (tested with 0.114.0).

## Environment

Mirror rows are read by `sync.sh`. Client rows are grype's own settings on the machine that scans
(`grype config` prints all of them). Each `GRYPE_*` variable maps to the config key after the prefix,
for example `GRYPE_DB_AUTO_UPDATE` is `db.auto-update`.

| Req | Name | Default | Purpose |
|---|---|---|---|
| Optional | `GRYPE_DB_SOURCE_URL` | `https://grype.anchore.io/databases/v6/latest.json` | Upstream listing. The archive is fetched from the same directory |
| Optional | `KEEP_RELEASES` | `7` | Releases kept, newest first. An integer of 1 or more. The workflow's `keep` input sets it on a manual run |
| Optional | `DRY_RUN` | `0` | `1` downloads and verifies the newest build, then stops. It skips the release check and needs no token or repository |
| Required | `GITHUB_REPOSITORY` | set by Actions | `<owner>/<repo>` to publish to. Required unless `DRY_RUN=1` |
| Required | `GH_TOKEN` | set by the workflow | Token for `gh`, with `contents: write` on the repository |
| Client | `GRYPE_DB_UPDATE_URL` | `https://grype.anchore.io/databases` | Where grype gets its listing. Set it to this repository's `listing.json` (see [Usage](#usage)). A URL ending in `.json` is used as is, any other URL gets `/v6/latest.json` appended |
| Client | `GRYPE_DB_AUTO_UPDATE` | `true` | `true` checks for a newer database before each scan. `false` scans with the cached database, for a host with no route to the listing |
| Client | `GRYPE_CHECK_FOR_APP_UPDATE` | `true` | `true` asks Anchore for a newer grype release on each run. Set `false` where Anchore is unreachable, or each run logs `failed to fetch latest version` |
| Client | `SYFT_CHECK_FOR_APP_UPDATE` | `true` | The same check in syft. Set `false` with the grype one |
| Client | `GRYPE_DB_CACHE_DIR` | `~/.cache/grype/db` (Linux) | Where the database is stored. A job directory keeps it per job |
| Client | `GRYPE_DB_CA_CERT` | system roots | PEM bundle for a listing server with a private CA |
| Client | `GRYPE_DB_VALIDATE_AGE` | `true` | `true` refuses a database older than `GRYPE_DB_MAX_ALLOWED_BUILT_AGE`. Leave it on |
| Client | `GRYPE_DB_MAX_ALLOWED_BUILT_AGE` | `120h` | Oldest database grype accepts. Raise it where a copy arrives days late, for example `336h` |
| Client | `GRYPE_DB_REQUIRE_UPDATE_CHECK` | `false` | `true` fails the run when the update check fails, instead of scanning with the cached database |
| Client | `GRYPE_DB_MAX_UPDATE_CHECK_FREQUENCY` | `2h` | Minimum time between update checks with `GRYPE_DB_AUTO_UPDATE=true` |
| Client | `GRYPE_DB_VALIDATE_BY_HASH_ON_START` | `true` | Checks the cached database file against its stored hash before a scan |
| Client | `GRYPE_DB_UPDATE_AVAILABLE_TIMEOUT` | `30s` | Timeout for fetching the listing |
| Client | `GRYPE_DB_UPDATE_DOWNLOAD_TIMEOUT` | `5m` | Timeout for downloading the archive |

## Usage

The repository is public, so reading releases needs no token. On the scanning host:

```sh
export GRYPE_DB_UPDATE_URL=https://github.com/<owner>/grype-db-mirror/releases/latest/download/listing.json
export GRYPE_CHECK_FOR_APP_UPDATE=false SYFT_CHECK_FOR_APP_UPDATE=false
grype db update && grype db status
```

To pin one build, use `releases/download/<tag>/listing.json` instead of `releases/latest/download/listing.json`.

For a host with no route to GitHub, download the release on a host that has one, verify it, carry the
directory across, then import it:

```sh
gh release download --repo <owner>/grype-db-mirror --pattern '*' --dir grype-db
cd grype-db && sha256sum -c SHA256SUMS
grep -q "$(sha256sum ./*.tar.zst | cut -d' ' -f1)" latest.json
# on the closed host
grype db import ./*.tar.zst
GRYPE_DB_AUTO_UPDATE=false GRYPE_CHECK_FOR_APP_UPDATE=false grype <target>
```

Check without publishing: `DRY_RUN=1 ./sync.sh`.

## Behaviour

- `.github/workflows/sync.yml` runs `sync.sh` hourly at minute 55 and on `workflow_dispatch`. Anchore
  publishes once a day, between about 06:50 and 07:50 UTC, so a new build is released within about an hour.
- Each run first re-enables the workflow, so GitHub's 60-day inactivity rule for public repositories
  does not turn the schedule off.
- A run skips when tag `v6-<built>` exists. A draft left by a failed upload has no tag, so the next run retries it.
- The archive is checked against the listing `checksum` before upload. After upload, GitHub's asset
  digests are compared with the local files. A mismatch deletes the release and fails the run.
- GitHub replaces `:` in asset names with `.`. The upstream `latest.json` therefore names a file the
  release does not have. `listing.json` is the same listing with `path` set to the uploaded asset name,
  and grype resolves `path` relative to the listing URL.
- Releases beyond `KEEP_RELEASES` are deleted with their tags.

## Out of scope

- Moving the database into a closed network. Carry the release assets yourself, as in [Usage](#usage).
- Building or changing the database. The archive is Anchore's, byte for byte.
- Scanning. grype and syft run where you scan, not here.

## Expected result

A release `v6-<YYYYMMDDTHHMMSSZ>`, marked latest, with four assets: the archive
`vulnerability-db_v6.<x>.<y>_<built>_<n>.tar.zst`, `latest.json` (upstream, unchanged), `listing.json`
and `SHA256SUMS`. Verify a client sees it:

```sh
GRYPE_DB_UPDATE_URL=https://github.com/<owner>/grype-db-mirror/releases/latest/download/listing.json grype db check
```

## Data terms

Anchore builds the database from upstream sources under their own terms (NVD, GitHub Advisory
Database, distribution feeds and others). This repository redistributes it unchanged. This product
uses data from the NVD API but is not endorsed or certified by the NVD.
