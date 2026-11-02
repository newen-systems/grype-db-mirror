# grype-db-mirror

Hourly mirror of the [grype](https://github.com/anchore/grype) v6 vulnerability
database from `grype.anchore.io` into GitHub releases, for networks that reach
GitHub but not Anchore.

## How it works

`.github/workflows/sync.yml` runs `sync.sh` every hour at minute 55, and by hand
(`workflow_dispatch`). Anchore publishes once a day, between 06:53 and 07:47 UTC,
so a new build is here within about an hour. Each run first re-enables the
workflow, so GitHub's [60-day inactivity rule](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/disable-and-enable-workflows)
does not switch the schedule off.
Then `sync.sh`:

1. Fetch upstream `latest.json`. Skip if tag `v6-<built>` already exists.
2. Download the archive and verify it against the listing `checksum`.
3. Publish a release with the archive, `latest.json` (unchanged), `SHA256SUMS`
   and `listing.json` (`latest.json` with `path` set to the archive's asset name).
4. Compare GitHub's asset digests with the uploaded files.
5. Delete all but the newest `KEEP_RELEASES` (7) releases and their tags.

Local check without publishing: `DRY_RUN=1 ./sync.sh`.

## Use

The repo is public, so no token is needed to read releases.

Point grype straight at the latest release:

```sh
export GRYPE_DB_UPDATE_URL=https://github.com/<owner>/grype-db-mirror/releases/latest/download/listing.json
grype db update
```

GitHub replaces `:` in asset names with `.`, so the upstream `latest.json`
names an archive that does not exist under that name in the release.
`listing.json` names the uploaded asset instead, and grype resolves it relative
to the listing URL. To pin one build, use
`https://github.com/<owner>/grype-db-mirror/releases/download/<tag>/listing.json`.

Or download and import by hand:

```sh
gh release download --repo <owner>/grype-db-mirror --pattern '*' --dir grype-db
cd grype-db
sha256sum -c SHA256SUMS
grep -q "$(sha256sum ./*.tar.zst | cut -d' ' -f1)" latest.json
grype db import ./*.tar.zst
GRYPE_DB_AUTO_UPDATE=false grype <target>
```

## Data terms

The database is built by Anchore from upstream sources with their own terms
(NVD, GitHub Advisory Database, distribution feeds and others). This repo
redistributes it unchanged. This product uses data from the NVD API but is not
endorsed or certified by the NVD.
