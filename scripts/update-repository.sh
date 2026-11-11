#!/usr/bin/env bash
# Indexes debs/ into Packages, Packages.xz and Release and writes the site
# GitHub Pages serves to _site/. Run by the workflow on every push to
# main; on Debian or Ubuntu it runs the same by hand.
set -euo pipefail

repository_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repository_root:?}"

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

# A package with no Section is filed under nothing; refuse it here.
awk '
  BEGIN { RS = ""; FS = "\n" }
  {
    package = ""; section = ""
    for (field = 1; field <= NF; field++) {
      if ($field ~ /^Package: /) package = substr($field, 10)
      if ($field ~ /^Section: /) section = substr($field, 10)
    }
    if (package != "" && section == "") {
      printf "Package %s has no Section field, which package managers file it by.\n", package > "/dev/stderr"
      exit 1
    }
  }
' "$work_dir/Packages"

# Swap the target package's display metadata for the repository's own:
# icon and depiction point at the Pages depiction, the Description becomes
# the repository-only Chinese blurb. Exact Package match only, so other
# packages and every other field pass through untouched.
awk -v base="https://ys8smjzty4-dot.github.io/ZengNiupackages/depictions/com.zengniu.splitview/" '
  BEGIN { RS = ""; FS = "\n"; ORS = "" }
  {
    target = 0; compat = 0
    for (i = 1; i <= NF; i++) {
      if ($i == "Package: com.zengniu.splitview") target = 1
      if ($i == "Package: com.zengniu.splitview.compat") compat = 1
    }
    if (compat) {
      compatBase = base
      sub(/com\.zengniu\.splitview\/$/, "com.zengniu.splitview.compat/", compatBase)
      skip = 0
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^(Depiction|SileoDepiction):/) { skip = 1; continue }
        if (skip && $i ~ /^[ \t]/) continue
        skip = 0
        print $i "\n"
      }
      print "Depiction: " compatBase "index.html\n"
      print "SileoDepiction: " compatBase "depiction.json\n\n"
      next
    }
    if (!target) {
      for (i = 1; i <= NF; i++) print (i > 1 ? "\n" : "") $i
      print "\n\n"
      next
    }
    icon = 0; web = 0; native = 0; desc = 0; done = 0
    out = ""
    for (i = 1; i <= NF; i++) {
      line = $i
      if (line ~ /^Icon: /) {
        out = out (done++ ? "\n" : "") "Icon: " base "icon.png"; icon = 1
        while (i < NF && $(i + 1) ~ /^[ \t]/) { i++ }
        continue
      }
      if (line ~ /^Depiction: /) {
        out = out (done++ ? "\n" : "") "Depiction: " base "index.html"; web = 1
        while (i < NF && $(i + 1) ~ /^[ \t]/) { i++ }
        continue
      }
      if (line ~ /^SileoDepiction: /) {
        out = out (done++ ? "\n" : "") "SileoDepiction: " base "depiction.json"; native = 1
        while (i < NF && $(i + 1) ~ /^[ \t]/) { i++ }
        continue
      }
      if (line ~ /^Description: /) {
        out = out (done++ ? "\n" : "") "Description: 真实应用小窗，支持桌面手势、多档空挂与下探取出；需授权启用。"
        desc = 1
        while (i < NF && $(i + 1) ~ /^[ \t]/) { i++ }
        continue
      }
      out = out (done++ ? "\n" : "") line
    }
    print out
    if (!icon) print "\nIcon: " base "icon.png"
    if (!web) print "\nDepiction: " base "index.html"
    if (!native) print "\nSileoDepiction: " base "depiction.json"
    print "\n\n"
  }
' "$work_dir/Packages" > "$work_dir/Packages.new" && mv "$work_dir/Packages.new" "$work_dir/Packages"

xz -9e -c "$work_dir/Packages" > "$work_dir/Packages.xz"
mkdir -p "$work_dir/indexes"
cp "$work_dir/Packages" "$work_dir/Packages.xz" "$work_dir/indexes/"

# Release is written beside the indexes, never among them, so it does
# not hash itself.
apt-ftparchive \
  -o APT::FTPArchive::Release::Origin="$owner" \
  -o APT::FTPArchive::Release::Label="曾牛源（🐮）" \
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
# The home page's QR code: Irisin's add-source link for the address
# Pages serves, which the Camera opens in Irisin. Left out without
# qrencode or an address, and the page shows the card without it.
source_url="${SOURCE_URL:-}"
if [[ -n "$source_url" ]] && command -v qrencode >/dev/null 2>&1; then
  [[ "$source_url" == */ ]] || source_url="$source_url/"
  qrencode -t SVG --svg-path -m 0 --foreground=1F232B -o "$site_dir/qr.svg" \
    "irisin://repository/add?url=$source_url"
fi
if [[ -d depictions ]]; then
  cp -R depictions "$site_dir/depictions"
fi
cp "$work_dir/Packages" "$work_dir/Packages.xz" "$work_dir/Release" "$site_dir/"
# Pages runs no Jekyll over the site.
touch "$site_dir/.nojekyll"

# Never on an empty path: an empty root would make this /_site.
rm -rf -- "${repository_root:?}/_site"
mv "$site_dir" "${repository_root:?}/_site"
echo "Built the APT repository in _site/ (${#packages[@]} packages)"
