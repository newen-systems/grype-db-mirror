#!/usr/bin/env bash
# Mirror the latest grype v6 DB from Anchore into a GitHub release.
#
# One release per distinct upstream DB, tagged v6-<built>. Assets: the archive,
# SHA256SUMS, and latest.json and listing.json (both upstream latest.json with
# path set to the archive's asset name, for GRYPE_DB_UPDATE_URL). Keeps the newest
# KEEP_RELEASES releases. DRY_RUN=1 stops after download and verify.
set -euo pipefail

SOURCE_URL="${GRYPE_DB_SOURCE_URL:-https://grype.anchore.io/databases/v6/latest.json}"
KEEP="${KEEP_RELEASES:-7}"
REPO="${GITHUB_REPOSITORY:-}"

die() { echo "ERROR: $*" >&2; exit 1; }
[[ "$KEEP" =~ ^[1-9][0-9]*$ ]] || die "KEEP_RELEASES must be 1 or more: $KEEP"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"

curl -fsSL "$SOURCE_URL" -o latest.json
path=$(jq -r '.path // empty' latest.json)
sum=$(jq -r '.checksum // empty' latest.json)
built=$(jq -r '.built // empty' latest.json)

# path is used as a local file name and asset name, so reject anything odd.
[[ "$path" =~ ^[A-Za-z0-9._:-]+\.tar\.zst$ ]] || die "unexpected path: $path"
[[ "$sum" =~ ^sha256:[0-9a-f]{64}$ ]] || die "unexpected checksum: $sum"
[[ "$built" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || die "unexpected built: $built"
tag="v6-${built//[-:]/}"
echo "upstream: $path ($sum) -> $tag"

if [ "${DRY_RUN:-0}" != 1 ]; then
  [ -n "$REPO" ] || die "GITHUB_REPOSITORY must be set"
  # Drafts have no tag ref, so a run that failed mid-upload is retried.
  if gh api "repos/$REPO/git/ref/tags/$tag" >/dev/null 2>&1; then
    echo "already mirrored, nothing to do"
    exit 0
  fi
fi

curl -fsSL "${SOURCE_URL%/*}/$path" -o "$path"
echo "${sum#sha256:}  $path" | sha256sum -c -
# GitHub renames ':' in asset names to '.', so upload under that name up front.
asset="${path//:/.}"
[ "$asset" = "$path" ] || mv "$path" "$asset"
# grype resolves path relative to the listing URL, so point it at the asset.
# latest.json and listing.json are the same file: listing.json for clients
# already configured with it. checksum and built stay upstream's.
jq --arg p "$asset" '.path = $p' latest.json > listing.json
cp listing.json latest.json
sha256sum "$asset" latest.json > SHA256SUMS
cat SHA256SUMS

[ "${DRY_RUN:-0}" = 1 ] && { echo "DRY_RUN: verified, not publishing"; exit 0; }

gh release delete "$tag" --repo "$REPO" --yes >/dev/null 2>&1 || true # leftover draft
gh release create "$tag" "$asset" latest.json SHA256SUMS listing.json --repo "$REPO" --latest \
  --title "$tag" --notes "Grype v6 vulnerability DB built $built by Anchore, mirrored unchanged from $SOURCE_URL.
Verify: \`sha256sum -c SHA256SUMS\`. The archive hash equals \`checksum\` in latest.json.
Data is compiled by Anchore from upstream sources (NVD, GitHub Advisory Database, distribution feeds and others) under their own terms. This product uses data from the NVD API but is not endorsed or certified by the NVD."

# Compare GitHub's server-side asset digests with what was uploaded.
gh api "repos/$REPO/releases/tags/$tag" \
  --jq '.assets[] | "\(.digest // "none" | ltrimstr("sha256:"))  \(.name)"' | sort > published
{ cat SHA256SUMS; sha256sum SHA256SUMS listing.json; } | sort > expected
if ! cmp -s expected published; then
  diff expected published >&2 || true
  # Remove the bad release so the next run retries instead of skipping.
  gh release delete "$tag" --repo "$REPO" --cleanup-tag --yes
  die "asset digests differ from upload"
fi
echo "published digests verified"

gh api "repos/$REPO/releases?per_page=100" \
  --jq "[.[] | select(.draft | not) | .tag_name | select(startswith(\"v6-\"))] | sort | reverse | .[$KEEP:][]" |
while read -r old; do
  echo "pruning $old"
  gh release delete "$old" --repo "$REPO" --cleanup-tag --yes
done
