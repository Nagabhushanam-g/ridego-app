# RideGo test APK installation and evidence guide

## Choose a matching build

1. Open [Build RideGo Payment Test APKs](https://github.com/Nagabhushanam-g/ridego-app/actions/workflows/build-payment-test-apks.yml?query=branch%3Afeature%2Fpayments-from-tested-build).
2. Select a **successful** run on branch `feature/payments-from-tested-build`. Confirm its commit matches a **successful** [Validate RideGo Payment Branch](https://github.com/Nagabhushanam-g/ridego-app/actions/workflows/validate-payments.yml?query=branch%3Afeature%2Fpayments-from-tested-build) run.
3. Under the build run's **Artifacts**, download both `ridego-payment-test-rider-apk` and `ridego-payment-test-partner-apk`. Artifact download may require GitHub sign-in.
4. Unzip each artifact and install its APK on the respective Android test device. Both APKs must come from the **same workflow run**. Do not combine APKs from different commits.
5. If Android refuses an update because of a signing mismatch, **do not uninstall until test data and account access are confirmed**. Record the exact error; verify the release signing setup first.

## Confirm basic operation

- Sign in to both apps using authorized test accounts. Verify maps, permissions, Firebase connectivity and Partner profile.
- Complete the tests in [RIDEGO_FINAL_ACCEPTANCE_CHECKLIST.md](RIDEGO_FINAL_ACCEPTANCE_CHECKLIST.md).
- The Partner Documents tab supports manual DL number/expiry and RC JPG/PNG image submission, **not** official DigiLocker verification.
- A successful build or automated test does not mean the application is approved for production or the Play Store.

## Evidence to record

| Field | Test record |
| --- | --- |
| Branch and commit | |
| APK workflow run URL | |
| Validation workflow run URL | |
| Rider version/device/Android version | |
| Partner version/device/Android version | |
| Firebase test environment | |
| Ride ID and test fare (non-sensitive) | |
| Steps passed / failed | |
| Error message and approximate timestamp | |
| Screenshots (redact phone, licence, RC, PIN and personal data) | |

## If an APK artifact is missing

Check the build's conclusion and its **Upload Rider APK** / **Upload Driver APK** steps. A run still in progress may have no artifacts yet. Do not claim an artifact is available until the upload step completes. Do not use an earlier APK as a substitute without clearly recording its commit.

**Release gate:** No production Firebase deployment, DigiLocker activation or Play Store publication without separate explicit approval.
