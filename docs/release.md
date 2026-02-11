# Beta Release Setup (`0.1.x`)

This repo ships prerelease builds from `main` using semantic-release tags:

- `v0.1.0-beta.1`
- `v0.1.0-beta.2`
- etc.

All releases are patch-oriented while you stay on the `0.1` line.

## 1) GitHub repository settings

Set these repository **Variables**:

- `APP_BUNDLE_ID` (example: `com.yourname.typist`)
- `TAP_REPO` (example: `yourname/homebrew-typist`)
- `TAP_DEFAULT_BRANCH` (usually `main`)

Set these repository **Secrets**:

- `APPLE_DEVELOPER_ID_CERT_P12_BASE64`
- `APPLE_DEVELOPER_ID_CERT_PASSWORD`
- `DEVELOPER_ID_APPLICATION` (optional but recommended; exact signing identity string)
- `APPLE_API_KEY_ID`
- `APPLE_API_ISSUER_ID`
- `APPLE_API_PRIVATE_KEY_P8`
- `TAP_REPO_TOKEN` (PAT with write access to the tap repo)

## 2) Apple signing + notarization bootstrap

1. Join Apple Developer Program.
2. Create a **Developer ID Application** certificate.
3. Export certificate + key as `.p12` and base64 encode it:
   ```bash
   base64 -i developer_id.p12 | pbcopy
   ```
4. Create an App Store Connect API key (for `notarytool`).
5. Add the resulting key identifiers and private key to repo secrets.

## 3) Homebrew tap repository (`homebrew-typist`)

Create a separate GitHub repository:

- Name: `homebrew-typist`
- Initialize with a README on `main`
- Ensure `TAP_REPO_TOKEN` can push to it

Release workflow updates `Casks/typist.rb` automatically after each published beta.

## 4) Running a release

1. Merge release-ready commits to `main` using conventional commits (`feat:`, `fix:`, etc.).
2. In GitHub, run workflow: **release-beta**.
3. (Optional) leave `run_tests = true`.
4. Workflow will:
   - calculate next semantic prerelease version,
   - build + sign + notarize DMG,
   - publish GitHub prerelease with DMG asset,
   - update Homebrew tap cask.

## 5) Install paths for users

Direct download:

- `https://github.com/<owner>/typist/releases`

Homebrew:

```bash
brew tap <owner>/typist
brew install --cask typist
```
