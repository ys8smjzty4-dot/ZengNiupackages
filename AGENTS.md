# Repository maintenance

This workspace is an APT source, not the SplitView tweak source. Do not compile,
install, rebuild or replace its debs as part of depiction work.

## Build and publish the website

- `bash scripts/update-repository.sh` requires `apt-ftparchive` and `xz`.
  GitHub Actions supplies these on Ubuntu and deploys `_site/` to Pages.
- The current device lacks `apt-ftparchive`; do not install tools or claim that
  a complete local APT index build passed when it has not.
- Generated indexes and `_site/` are ignored. Never commit them.
- Publishing is a normal push to `main`, only with user authorization.
  No forced push, package publication or deb rebuild is needed for depictions.

## Checks

- `bash -n scripts/update-repository.sh scripts/test-repository-metadata.sh`
- `bash scripts/test-repository-metadata.sh` tests the exact metadata transform
  used by publishing, synthetic cases and controls read from existing debs.
  It proves only the transform, not the complete apt-ftparchive/Pages pipeline.
- CI also parses the native depiction with `python3 -m json.tool`.
  Python is not installed on the current device. Its bootstrap `plutil` can
  parse JSON via a temporary plist key with `-type json -value`; direct
  `plutil -show` on a JSON file is not a supported JSON lint here.
- Record SHA-256 hashes before edits and compare all existing debs afterwards.
- The HTML page renders the same two tabs from `depiction.json`, using textContent
  rather than HTML injection. Keep native paragraph content plain text.
- Actual browser tab switching, appearance and native package-manager rendering
  require screen testing with user consent. File and JSON checks do not prove UI.

## SplitView assets and version claims

- Assets live under `depictions/com.zengniu.splitview/`: `icon.png`, `index.html`,
  `depiction.json`. The 87×87 icon was copied from the existing alpha64 package;
  the package itself was not altered.
- `scripts/update-repository.sh` replaces only Icon, Depiction, SileoDepiction and the repository-only Chinese Description on exact Package matches for com.zengniu.splitview, before index compression and Release hashing. Other fields must remain unchanged. For exact Package com.zengniu.splitview.compat, replace only Depiction and SileoDepiction with its own depictions/com.zengniu.splitview.compat/ URLs; never point it at the main package page. All other packages remain unchanged.
- The alpha58+ source changes supplied in this conversation have no associated
  build/install/device-validation records and cannot be assumed to match the
  source repository's same-version debs. Do not say existing alpha61/64 packages
  were never published: they are present in the live APT index.
  Alpha57 has build/install records but no confirmed load. Alpha65 in this round
  covers the Icon URL/version metadata and companion pages only; no new deb was
  built or published. Website publication is separate from package publication.
- Do not invent missing iterations or dates. The alpha42 upward-fullscreen
  experiment was disabled in favor of rebound; alpha46 SBS diagnostics were
  withdrawn after SIGTRAP. Do not describe either as a verified working feature.
