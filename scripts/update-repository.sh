#!/usr/bin/env bash
# Indexes debs/ into Packages, Packages.xz and Release and writes the site
# GitHub Pages serves to _site/. Run by the workflow on every push to
# main; on Debian or Ubuntu it runs the same by hand.
set -euo pipefail

repository_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repository_root"

for command_name in apt-ftparchive xz; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name" >&2
    exit 69
  fi
done

name="${REPOSITORY_NAME:-$(basename "$repository_root")}"
owner="${REPOSITORY_OWNER:-$name}"
work_dir="$(mktemp -d "$repository_root/.repo-build.XXXXXX")"
trap 'rm -rf -- "${work_dir:?}"' EXIT
site_dir="$work_dir/site"
mkdir -p "$site_dir"

shopt -s nullglob
packages=(debs/*.deb)
shopt -u nullglob

# Running from the root keeps each Filename relative: debs/<file>.deb.
if ((${#packages[@]} > 0)); then
  apt-ftparchive packages debs > "$work_dir/Packages"
else
  : > "$work_dir/Packages"
fi

# Repository-only display metadata for SplitView. Never rewrite the debs.
# Do this before compression and Release hashing. Keep every other field,
# especially Filename, Size and package digests, exactly as apt-ftparchive wrote it.
awk -v base="https://ys8smjzty4-dot.github.io/ZengNiupackages/depictions/com.zengniu.splitview/" '
  BEGIN { RS = ""; FS = "\n"; ORS = "\n\n" }
  {
    target = 0
    for (i = 1; i <= NF; i++) {
      if ($i == "Package: com.zengniu.splitview") target = 1
    }
    if (!target) { print $0; next }
    result = ""; skip = 0
    for (i = 1; i <= NF; i++) {
      if ($i ~ /^(Icon|Depiction|SileoDepiction|Description):/) { skip = 1; continue }
      if ($i ~ /^[ \t]/ && skip) continue
      skip = 0
      result = result $i "\n"
    }
    result = result "Icon: " base "icon.png\n"
    result = result "Depiction: " base "index.html\n"
    result = result "SileoDepiction: " base "depiction.json\n"
    result = result "Description: 真实应用小窗，支持桌面手势、多档空挂与下探取出；需授权启用。"
    print result
  }
' "$work_dir/Packages" > "$work_dir/Packages.with-depictions"
mv "$work_dir/Packages.with-depictions" "$work_dir/Packages"

# Sileo files a package with no Section under nothing; refuse it here.
awk '
  BEGIN { RS = ""; FS = "\n" }
  {
    package = ""; section = ""
    for (field = 1; field <= NF; field++) {
      if ($field ~ /^Package: /) package = substr($field, 10)
      if ($field ~ /^Section: /) section = substr($field, 10)
    }
    if (package != "" && section == "") {
      printf "Package %s has no Section field, which Sileo needs.\n", package > "/dev/stderr"
      exit 1
    }
  }
' "$work_dir/Packages"

xz -9e -c "$work_dir/Packages" > "$work_dir/Packages.xz"
mkdir -p "$work_dir/indexes"
cp "$work_dir/Packages" "$work_dir/Packages.xz" "$work_dir/indexes/"

# Release is written beside the indexes, never among them, so it does
# not hash itself.
apt-ftparchive \
  -o APT::FTPArchive::Release::Origin="$owner" \
  -o APT::FTPArchive::Release::Label="曾牛源" \
  -o APT::FTPArchive::Release::Suite="stable" \
  -o APT::FTPArchive::Release::Version="1.0" \
  -o APT::FTPArchive::Release::Codename="$name" \
  -o APT::FTPArchive::Release::Architectures="iphoneos-arm iphoneos-arm64 iphoneos-arm64e" \
  -o APT::FTPArchive::Release::Components="main" \
  -o APT::FTPArchive::Release::Description="Packages from $owner" \
  release "$work_dir/indexes" > "$work_dir/Release"

if ((${#packages[@]} > 0)); then
  mkdir -p "$site_dir/debs"
  cp "${packages[@]}" "$site_dir/debs/"
fi
for file in index.html CydiaIcon.png sileo-featured.json; do
  if [[ -f "$file" ]]; then
    cp "$file" "$site_dir/"
  fi
done
if [[ -d depictions ]]; then
  cp -R depictions "$site_dir/depictions"
fi
cp "$work_dir/Packages" "$work_dir/Packages.xz" "$work_dir/Release" "$site_dir/"
# Pages runs no Jekyll over the site.
touch "$site_dir/.nojekyll"

rm -rf -- "${repository_root:?}/_site"
mv "${site_dir:?}" "${repository_root:?}/_site"
echo "Built the APT repository in _site/ (${#packages[@]} packages)"
