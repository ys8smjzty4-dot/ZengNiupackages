#!/usr/bin/env bash
# Tests only the repository's display-metadata transform; never builds a deb.
set -euo pipefail
repository_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repository_root:?}"
work_dir="$(mktemp -d "$repository_root/.repo-build.metadata-test.XXXXXX")"
trap 'rm -rf -- "${work_dir:?}"' EXIT
base='https://ys8smjzty4-dot.github.io/ZengNiupackages/depictions/com.zengniu.splitview/'

# Exercise the actual AWK program in the publishing script, not a second copy.
awk '
  /^awk -v base=/ { inside = 1; next }
  inside && /^\047 "\$work_dir\/Packages"/ { exit }
  inside { print }
' scripts/update-repository.sh > "$work_dir/transform.awk"
test -s "$work_dir/transform.awk"

cat > "$work_dir/fixture" <<'FIXTURE'
Package: com.zengniu.splitview
Version: 0.1.0~alpha61
Architecture: iphoneos-arm64e
Section: Tweaks
Icon: https://example.invalid/old.png
Depiction: https://example.invalid/old
 wrapped old depiction field
SileoDepiction: https://example.invalid/old.json
Description: First target
 continuation must remain
Filename: debs/first.deb
Size: 123
SHA256: unchanged-first

Package: local.zengniu.strawberry
Version: 0.0.7
Architecture: iphoneos-arm64
Section: Tweaks
Icon: https://example.invalid/strawberry.png
Depiction: https://example.invalid/strawberry
Description: Other package
 continuation must remain
SHA256: unchanged-other

Package: com.zengniu.splitview
Version: 0.1.0~alpha64
Architecture: iphoneos-arm64
Section: Tweaks
Description: Target with no existing display fields
SHA256: unchanged-second

Package: com.zengniu.splitview.extra
Version: 1
Icon: https://example.invalid/near-match.png
Description: Must not match a package prefix

FIXTURE

# A comparison projection drops ONLY the target package's three allowed fields.
cat > "$work_dir/project.awk" <<'AWK'
BEGIN { RS = ""; FS = "\n"; ORS = "\n\n" }
{
  target = 0
  for (i = 1; i <= NF; i++) if ($i == "Package: com.zengniu.splitview") target = 1
  if (!target) { print $0; next }
  result = ""; skip = 0
  for (i = 1; i <= NF; i++) {
    if ($i ~ /^(Icon|Depiction|SileoDepiction):/) { skip = 1; continue }
    if ($i ~ /^[ \t]/ && skip) continue
    skip = 0
    result = result (result == "" ? "" : "\n") $i
  }
  print result
}
AWK

check_transform() {
  local input="${1:?}" expected_targets="${2:?}"
  awk -v base="$base" -f "$work_dir/transform.awk" "$input" > "$work_dir/result"
  awk -v base="$base" -f "$work_dir/transform.awk" "$work_dir/result" > "$work_dir/twice"
  cmp "$work_dir/result" "$work_dir/twice"
  awk -f "$work_dir/project.awk" "$input" > "$work_dir/before"
  awk -f "$work_dir/project.awk" "$work_dir/result" > "$work_dir/after"
  cmp "$work_dir/before" "$work_dir/after"
  awk -v base="$base" -v expected="$expected_targets" '
    BEGIN { RS = ""; FS = "\n"; count = 0; failed = 0 }
    {
      target = 0
      for (i = 1; i <= NF; i++) if ($i == "Package: com.zengniu.splitview") target = 1
      if (!target) next
      count++; icon = 0; web = 0; native = 0; fields = 0
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^(Icon|Depiction|SileoDepiction):/) fields++
        if ($i == "Icon: " base "icon.png") icon++
        if ($i == "Depiction: " base "index.html") web++
        if ($i == "SileoDepiction: " base "depiction.json") native++
      }
      if (fields != 3 || icon != 1 || web != 1 || native != 1) failed = 1
    }
    END { if (failed || count != expected) exit 1 }
  ' "$work_dir/result"
}
check_transform "$work_dir/fixture" 2
: > "$work_dir/empty"
check_transform "$work_dir/empty" 0

# Read the current packages without extracting, rebuilding or installing them.
: > "$work_dir/real-controls"
expected_targets=0
shopt -s nullglob
for package in debs/*.deb; do
  dpkg-deb --field "$package" | awk 'NF { print }' >> "$work_dir/real-controls"
  printf 'Filename: %s\n' "$package" >> "$work_dir/real-controls"
  printf 'Size: %s\n' "$(wc -c < "$package" | tr -d ' ')" >> "$work_dir/real-controls"
  printf 'SHA256: %s\n\n' "$(sha256sum "$package" | awk '{ print $1 }')" >> "$work_dir/real-controls"
  if [[ "$(dpkg-deb --field "$package" Package)" == com.zengniu.splitview ]]; then
    expected_targets=$((expected_targets + 1))
  fi
done
check_transform "$work_dir/real-controls" "$expected_targets"
for asset in icon.png index.html depiction.json; do
  test -s "depictions/com.zengniu.splitview/$asset"
done
printf 'PASS: exact package matching, replacement, missing fields, continuations, idempotence, empty index, %s actual target records; other fields/packages unchanged.\n' "$expected_targets"
