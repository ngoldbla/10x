# Fastlane match Sub-project 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up a Fastlane foundation with `match`-managed signing and a `beta` lane that builds and uploads **rabbit-ears only** to TestFlight, using manual App Store distribution signing (Approach 2).

**Architecture:** `match` mints a fresh Apple Distribution cert + App Store provisioning profile for `com.couchsuite.rabbitears`, encrypted into the private repo `couch-suite-certificates`. `rabbit-ears/project.yml` switches to manual signing referencing that profile, so `gym` signs the archive with no registered-device requirement. A `beta` lane wires ASC API-key auth → `match --readonly` → `gym` → `pilot`. `scripts/testflight.sh` and the CI workflow are left untouched as the safety net.

**Tech Stack:** Fastlane 2.237.0 (Homebrew), `match`, `gym`, `pilot`, XcodeGen 2.45.4, xcodebuild (Xcode 26 / tvOS SDK), Ruby (Homebrew-bundled with fastlane).

## Global Constraints

- Bundle ID: `com.couchsuite.rabbitears`. Xcode scheme/target: `RabbitEars`. Generated project: `rabbit-ears/RabbitEars.xcodeproj`.
- Apple team read from `COUCH_TEAM_ID` (env / `signing.env`) — never hardcode a team ID in committed files.
- Build number = `git rev-list --count HEAD`, passed as `CURRENT_PROJECT_VERSION`. **Never** use `increment_build_number`; **never** commit a build number back to the repo.
- `match` in the `beta` lane runs `readonly: true` **always** (local and CI). The **only** read-write `match` run is the one-time bootstrap in Task 2.
- `match` config: `storage_mode "git"`, `type "appstore"`, `git_url "git@github.com:ngoldbla/couch-suite-certificates.git"`.
- Reuse the existing App Store Connect API key: `ASC_KEY_ID`, `ASC_ISSUER_ID`, and **either** `ASC_KEY_PATH` (a `.p8` file) **or** `ASC_KEY_P8` (base64 of the `.p8`). Support both.
- Match profile name is deterministic: `match AppStore com.couchsuite.rabbitears`.
- **Do NOT modify** `scripts/testflight.sh` or `.github/workflows/testflight-tvos.yml` in this sub-project.
- SP1 execution uses the Homebrew `fastlane` binary directly (not `bundle exec`). The committed `Gemfile` is a version-pin declaration only; `Gemfile.lock` + `bundle exec` enforcement is deferred to Sub-project 2.
- `signing.env` and `*/dist/` stay gitignored; never commit secrets, `.p8`, `.p12`, or `.mobileprovision`.

## Preconditions (verify before Task 1)

- On macOS with Xcode selected (`xcode-select -p`) and a tvOS SDK available.
- `xcodegen`, `fastlane`, `git`, `gh` (authed as `ngoldbla`) on PATH.
- Network access to `github.com` (certs repo) and App Store Connect.
- The maintainer can supply, at Task 2: `COUCH_TEAM_ID`, the ASC API key material, and a freshly chosen `MATCH_PASSWORD`.

---

### Task 1: Fastlane foundation config (no account mutation)

Creates the Fastlane config files and the ASC API-key helper. Nothing here contacts Apple or mutates signing state — it must be safe to run and re-run.

**Files:**
- Create: `fastlane/Appfile`
- Create: `fastlane/Matchfile`
- Create: `fastlane/Fastfile`
- Create: `Gemfile`
- Modify: `.gitignore`

**Interfaces:**
- Produces: a private helper `asc_api_key` (Ruby method in `Fastfile`) returning the hash from `app_store_connect_api_key(...)`, consumed by Tasks 2, 4, 5.
- Produces: lane `beta` (skeleton this task; full body added in Task 4).

- [ ] **Step 1: Write `fastlane/Appfile`**

```ruby
# Team is read from the COUCH_TEAM_ID env var (or signing.env) — never hardcoded.
# app_identifier is supplied per-lane; Sub-project 1 targets rabbit-ears only.
team_id(ENV["COUCH_TEAM_ID"])
```

- [ ] **Step 2: Write `fastlane/Matchfile`**

```ruby
git_url("git@github.com:ngoldbla/couch-suite-certificates.git")
storage_mode("git")
type("appstore")
app_identifier(["com.couchsuite.rabbitears"])
```

- [ ] **Step 3: Write `fastlane/Fastfile` (helper + beta skeleton)**

```ruby
default_platform(:ios)

# Reuse the existing App Store Connect API key for match + pilot.
# Supports either a .p8 file path (ASC_KEY_PATH) or base64 content (ASC_KEY_P8),
# mirroring scripts/testflight.sh so local and CI auth stay identical.
def asc_api_key
  key_id    = ENV.fetch("ASC_KEY_ID")
  issuer_id = ENV.fetch("ASC_ISSUER_ID")
  if (path = ENV["ASC_KEY_PATH"]) && !path.empty?
    app_store_connect_api_key(key_id: key_id, issuer_id: issuer_id, key_filepath: path)
  elsif (content = ENV["ASC_KEY_P8"]) && !content.empty?
    app_store_connect_api_key(
      key_id: key_id, issuer_id: issuer_id,
      key_content: content, is_key_content_base64: true
    )
  else
    UI.user_error!("Set ASC_KEY_PATH (a .p8 file) or ASC_KEY_P8 (base64 of the .p8)")
  end
end

platform :ios do
  desc "Build rabbit-ears and upload to TestFlight (upload:false = dry run, signed .ipa only)"
  lane :beta do |options|
    UI.user_error!("beta lane body is implemented in Task 4") unless ENV["SP1_BETA_READY"]
  end
end
```

- [ ] **Step 4: Write `Gemfile` (version pin only for SP1)**

```ruby
source "https://rubygems.org"

# Version pin for Sub-project 2's CI (`bundle install` on a modern Ruby).
# Sub-project 1 runs the Homebrew fastlane directly; no bundle exec required.
gem "fastlane", "2.237.0"
```

- [ ] **Step 5: Append Fastlane noise to `.gitignore`**

Add these lines to `.gitignore`:

```gitignore
# Fastlane
fastlane/report.xml
fastlane/Preview.html
fastlane/screenshots/**/*.png
fastlane/test_output
*.mobileprovision
*.p12
*.p8
```

- [ ] **Step 6: Verify the Fastfile parses and lists the lane**

Run: `fastlane lanes`
Expected: output lists `ios beta` with the description "Build rabbit-ears and upload to TestFlight ...". No Ruby syntax error.

- [ ] **Step 7: Commit**

```bash
git add fastlane/Appfile fastlane/Matchfile fastlane/Fastfile Gemfile .gitignore
git commit -m "feat(fastlane): scaffold Appfile/Matchfile/Fastfile + ASC key helper"
```

---

### Task 2: One-time `match` bootstrap (account-mutating — GATED)

Mints the distribution cert + App Store profile and pushes them encrypted to the certs repo. **This is the only step that mutates the Apple Developer account. Do not run it without the maintainer's explicit go-ahead in the moment.** It produces no commit in this repo (the certs live in `couch-suite-certificates`; `signing.env` is gitignored).

**Files:**
- Create (gitignored, local only): `signing.env`

**Interfaces:**
- Consumes: `asc_api_key` (Task 1).
- Produces: encrypted `certs/` + `profiles/` in `couch-suite-certificates`; a locally installed cert + the profile `match AppStore com.couchsuite.rabbitears` (name referenced by Task 3).

- [ ] **Step 1: [requires user input] Collect credentials and create `signing.env`**

Ask the maintainer for `COUCH_TEAM_ID`, the ASC key values, and a freshly chosen strong `MATCH_PASSWORD` (store it in a password manager — it becomes a GitHub secret in SP2). Write `signing.env` (gitignored) in the repo root:

```bash
COUCH_TEAM_ID=XXXXXXXXXX
ASC_KEY_ID=XXXXXXXXXX
ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
ASC_KEY_PATH=/absolute/path/AuthKey_XXXXXXXXXX.p8
MATCH_PASSWORD=<the chosen passphrase>
MATCH_GIT_URL=git@github.com:ngoldbla/couch-suite-certificates.git
```

- [ ] **Step 2: Confirm the certs repo is still empty (safe to bootstrap)**

Run: `gh repo view ngoldbla/couch-suite-certificates --json isEmpty`
Expected: `{"isEmpty":true}`. If it is NOT empty, STOP and ask the maintainer — do not overwrite existing signing material.

- [ ] **Step 3: [GATE — explicit go-ahead required] Run the one-time match bootstrap**

This mints a real Apple Distribution certificate. Confirm with the maintainer, then:

```bash
set -a && source signing.env && set +a
fastlane match appstore --app_identifier com.couchsuite.rabbitears --readonly false
```

Expected: fastlane authenticates via the API key, creates (or reuses) an Apple Distribution cert and an App Store profile for `com.couchsuite.rabbitears`, and pushes them encrypted to the repo. Ends with "All required keys, certificates and provisioning profiles are installed 🙌".

- [ ] **Step 4: Verify the certs repo is now populated**

Run: `gh api repos/ngoldbla/couch-suite-certificates/git/trees/HEAD?recursive=1 --jq '.tree[].path' | sort`
Expected: paths under `certs/distribution/` and `profiles/appstore/` (e.g. `profiles/appstore/AppStore_com.couchsuite.rabbitears.mobileprovision`).

- [ ] **Step 5: Verify the profile installed locally**

Run: `security find-identity -v -p codesigning | grep -i "Apple Distribution"`
Expected: at least one valid "Apple Distribution" identity is listed.

No commit in this task (nothing committable belongs to this repo).

---

### Task 3: Switch rabbit-ears to manual App Store distribution signing

**Files:**
- Modify: `rabbit-ears/project.yml` (the `settings.base` block, currently line ~29 `CODE_SIGN_STYLE: Automatic`)

**Interfaces:**
- Consumes: the profile name `match AppStore com.couchsuite.rabbitears` (Task 2).
- Produces: a generated `RabbitEars.xcodeproj` whose build settings use manual Apple Distribution signing (relied on by Task 4's `gym`).

- [ ] **Step 1: Edit `rabbit-ears/project.yml` signing settings**

Replace the single line `        CODE_SIGN_STYLE: Automatic` in the `settings.base` block with:

```yaml
        CODE_SIGN_STYLE: Manual
        CODE_SIGN_IDENTITY: "Apple Distribution"
        DEVELOPMENT_TEAM: ${COUCH_TEAM_ID}
        PROVISIONING_PROFILE_SPECIFIER: "match AppStore com.couchsuite.rabbitears"
```

Note: XcodeGen expands `${COUCH_TEAM_ID}` from the environment at generate time, so the team ID is never committed. Keep every other line in `settings.base` unchanged.

- [ ] **Step 2: Regenerate the Xcode project**

Run: `set -a && source signing.env && set +a && cd rabbit-ears && xcodegen generate && cd ..`
Expected: "Created project at rabbit-ears/RabbitEars.xcodeproj".

- [ ] **Step 3: Verify the build settings resolved correctly**

Run:
```bash
xcodebuild -project rabbit-ears/RabbitEars.xcodeproj -scheme RabbitEars \
  -showBuildSettings 2>/dev/null | grep -E "CODE_SIGN_STYLE|CODE_SIGN_IDENTITY|PROVISIONING_PROFILE_SPECIFIER|DEVELOPMENT_TEAM"
```
Expected: `CODE_SIGN_STYLE = Manual`, `CODE_SIGN_IDENTITY = Apple Distribution`, `PROVISIONING_PROFILE_SPECIFIER = match AppStore com.couchsuite.rabbitears`, and `DEVELOPMENT_TEAM` = your team ID.

- [ ] **Step 4: Commit (project.yml only — the generated .xcodeproj is gitignored)**

```bash
git add rabbit-ears/project.yml
git commit -m "feat(rabbit-ears): manual App Store distribution signing via match profile"
```

---

### Task 4: Implement the `beta` lane and verify a signed build (dry run)

**Files:**
- Modify: `fastlane/Fastfile` (replace the `beta` lane skeleton from Task 1)

**Interfaces:**
- Consumes: `asc_api_key` (Task 1), the installed cert + profile (Task 2), the manually-signed project (Task 3).
- Produces: a signed `.ipa` at `rabbit-ears/dist/RabbitEars.ipa` when run with `upload:false`.

- [ ] **Step 1: Replace the `beta` lane body in `fastlane/Fastfile`**

```ruby
  desc "Build rabbit-ears and upload to TestFlight (upload:false = dry run, signed .ipa only)"
  lane :beta do |options|
    do_upload = options.fetch(:upload, true)
    app_id = "com.couchsuite.rabbitears"
    build  = sh("git rev-list --count HEAD").strip

    key = asc_api_key
    setup_ci # temp keychain on CI; no-op locally

    match(type: "appstore", app_identifier: app_id, api_key: key, readonly: true)

    sh("cd #{File.expand_path('../rabbit-ears', __dir__)} && xcodegen generate")

    gym(
      project: File.expand_path("../rabbit-ears/RabbitEars.xcodeproj", __dir__),
      scheme: "RabbitEars",
      export_method: "app-store",
      output_directory: File.expand_path("../rabbit-ears/dist", __dir__),
      output_name: "RabbitEars.ipa",
      xcargs: "CURRENT_PROJECT_VERSION=#{build}",
      export_options: {
        signingStyle: "manual",
        provisioningProfiles: { app_id => "match AppStore com.couchsuite.rabbitears" }
      }
    )

    if do_upload
      pilot(api_key: key, app_identifier: app_id, skip_waiting_for_build_processing: true)
      UI.success("rabbit-ears build #{build} uploaded to TestFlight")
    else
      UI.success("rabbit-ears build #{build} exported (dry run): rabbit-ears/dist/RabbitEars.ipa")
    end
  end
```

Also delete the Task 1 skeleton guard line (`UI.user_error!("beta lane body ...") unless ENV["SP1_BETA_READY"]`) — it is fully replaced by the body above.

- [ ] **Step 2: Verify the Fastfile still parses**

Run: `fastlane lanes`
Expected: `ios beta` listed, no Ruby syntax error.

- [ ] **Step 3: Run the dry run (build + sign, no upload)**

Run: `set -a && source signing.env && set +a && fastlane ios beta upload:false`
Expected: match installs the profile (readonly), gym archives + exports, ends with "build N exported (dry run)". An `.ipa` exists at `rabbit-ears/dist/RabbitEars.ipa`.

- [ ] **Step 4: Verify the .ipa is signed with the distribution identity + match profile**

Run:
```bash
cd /tmp && rm -rf ipacheck && mkdir ipacheck && cd ipacheck && \
unzip -q "$OLDPWD/rabbit-ears/dist/RabbitEars.ipa" && \
codesign -dv --verbose=4 Payload/RabbitEars.app 2>&1 | grep -E "Authority|TeamIdentifier" && \
cd "$OLDPWD"
```
Expected: `Authority=Apple Distribution: ...` and the `TeamIdentifier` matches `COUCH_TEAM_ID`. (Confirms Approach 2 archive-time distribution signing worked — no unsigned-archive/re-sign hack needed.)

- [ ] **Step 5: Commit**

```bash
git add fastlane/Fastfile
git commit -m "feat(fastlane): implement beta lane (match + gym) for rabbit-ears"
```

**If Step 3 or 4 fails on signing** (e.g. tvOS rejects archive-time distribution signing): stop and fall back to Approach 3 per the spec — keep the unsigned archive + ad-hoc re-sign from `testflight.sh`'s pattern, but pin the match profile at export. Re-plan Task 4 accordingly before proceeding.

---

### Task 5: End-to-end TestFlight upload + docs

**Files:**
- Modify: `TESTFLIGHT.md` (add a short "Fastlane (rabbit-ears)" note)

**Interfaces:**
- Consumes: the working `beta` lane (Task 4).
- Produces: a rabbit-ears build visible in App Store Connect → TestFlight.

- [ ] **Step 1: [GATE — consumes a TestFlight build number] Run the full lane**

Confirm with the maintainer (this uploads a real build), then:

Run: `set -a && source signing.env && set +a && fastlane ios beta`
Expected: gym builds + signs, pilot uploads, ends with "build N uploaded to TestFlight".

- [ ] **Step 2: Verify the build reached App Store Connect**

Run: `fastlane pilot builds --api_key_path <(echo) 2>/dev/null || echo "check ASC UI"`
Primary check: in App Store Connect → Apps → Rabbit Ears → TestFlight, the new build number appears with "Processing" then "Ready to Test" (5–15 min). Confirm the build number equals `git rev-list --count HEAD`.

- [ ] **Step 3: Add a Fastlane note to `TESTFLIGHT.md`**

Append this section to `TESTFLIGHT.md`:

```markdown
## Fastlane (rabbit-ears — Sub-project 1)

rabbit-ears can now ship via Fastlane with match-managed signing:

    set -a && source signing.env && set +a
    fastlane ios beta upload:false   # dry run: signed .ipa in rabbit-ears/dist/
    fastlane ios beta                # build, sign, upload to TestFlight

Signing assets live encrypted in the private repo couch-suite-certificates
(managed by `fastlane match appstore`). The beta lane always runs
`match(readonly: true)`; only the one-time bootstrap mints certs. The other
four apps still ship via scripts/testflight.sh until Sub-project 2.
```

- [ ] **Step 4: Commit**

```bash
git add TESTFLIGHT.md
git commit -m "docs(testflight): document the Fastlane beta lane for rabbit-ears"
```

---

## Self-Review (completed during planning)

- **Spec coverage:** foundation files (Task 1), fresh-cert bootstrap into the certs repo (Task 2), manual-signing project change (Task 3), beta lane with git-derived build number + dry run (Task 4), end-to-end TestFlight upload + docs (Task 5), Approach 3 fallback documented (Task 4). CI workflow and `testflight.sh` explicitly untouched (Global Constraints). ✓
- **Deviations from spec:** (1) SP1 runs the Homebrew `fastlane`, not `bundle exec`; `Gemfile.lock` + bundler enforcement deferred to SP2 — forced by system Ruby 2.6.10. (2) `signing.env` is created in this workspace in Task 2 because it was absent (gitignored). Both flagged to the maintainer.
- **Type/name consistency:** `asc_api_key` helper, lane `beta` with `upload:` option, profile name `match AppStore com.couchsuite.rabbitears`, scheme `RabbitEars`, and bundle id `com.couchsuite.rabbitears` are used identically across Tasks 1–5. ✓
- **Placeholder scan:** no TBD/TODO; the only intentional guard (Task 1 skeleton) is explicitly deleted in Task 4 Step 1. ✓
