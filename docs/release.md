# Beta Release Setup (`0.1.x`)

This project ships beta releases from `main` using tags like:

- `v0.1.0-beta.1`
- `v0.1.0-beta.2`
- `v0.1.0-beta.3`

Patch-style beta increments continue on the `0.1.x` line.

## 1) GitHub repository settings

Set these repository **Variables**:

- `APP_BUNDLE_ID` (example: `com.yourname.typist`, optional for unsigned path)
- `TAP_REPO` (example: `yourname/homebrew-typist`)
- `TAP_DEFAULT_BRANCH` (usually `main`)

Set these repository **Secrets**:

- `TAP_REPO_TOKEN` (PAT with write access to the tap repo)

Optional Apple signing/notarization secrets (only needed if you later enroll in Apple Developer Program):

- `APPLE_DEVELOPER_ID_CERT_P12_BASE64`
- `APPLE_DEVELOPER_ID_CERT_PASSWORD`
- `DEVELOPER_ID_APPLICATION` (optional but recommended)
- `APPLE_API_KEY_ID`
- `APPLE_API_ISSUER_ID`
- `APPLE_API_PRIVATE_KEY_P8`

## 2) No-paid-account distribution behavior

Without Apple Developer signing credentials:

- Release workflow publishes an **unsigned DMG**.
- Homebrew cask updates still work and point to that DMG.
- Homebrew does **not** add notarization/trust metadata.

If macOS blocks launch, users can:

1. Right-click `Typist.app` and choose **Open**.
2. Or run:
   ```bash
   xattr -dr com.apple.quarantine /Applications/Typist.app
   ```

## 3) Homebrew tap repository (`homebrew-typist`)

Use a separate public repository for the tap:

- Name: `homebrew-typist`
- Branch: `main`
- Cask path managed automatically: `Casks/typist.rb`

Release workflow updates `Casks/typist.rb` with:

- `version`
- `sha256`
- release asset `url`

## 4) DMG layout and design

DMG creation script now generates a styled drag-to-Applications window with:

- fixed Finder window size
- aligned app and Applications icons
- auto-generated background image with direction arrow

Script controls (optional env vars):

- `DMG_WINDOW_WIDTH`, `DMG_WINDOW_HEIGHT`
- `DMG_APP_ICON_X`, `DMG_APP_ICON_Y`
- `DMG_APPLICATIONS_ICON_X`, `DMG_APPLICATIONS_ICON_Y`
- `DMG_RENDER_BACKGROUND` (`1`/`0`)

## 5) Running a release

1. Merge release-ready commits to `main`.
2. Trigger workflow: **release-beta**.
3. Keep `run_tests = true` unless intentionally skipping.
4. Workflow will:
   - compute next `v0.1.0-beta.N` version
   - build `.app` bundle and DMG
   - apply DMG layout automation
   - sign+notarize only if Apple secrets are set
   - publish GitHub prerelease
   - update Homebrew tap cask

## 6) Install paths for users

Homebrew (recommended):

```bash
brew tap <owner>/typist
brew install --cask typist
```

Direct download:

- `https://github.com/<owner>/typist/releases`
