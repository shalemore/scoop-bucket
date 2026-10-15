# scoop-bucket

[![CI](https://github.com/shalemore/scoop-bucket/actions/workflows/ci.yml/badge.svg)](https://github.com/shalemore/scoop-bucket/actions/workflows/ci.yml)

A [Scoop](https://scoop.sh) bucket for my own tools.

```sh
scoop bucket add shalemore https://github.com/shalemore/scoop-bucket
scoop install <app>
```

## Apps

<!-- apps:start -->
| App | Description |
| --- | --- |
| [outbound](https://github.com/shalemore/outbound) | Tray app that moves files from local folders to a Linux server over ssh |
<!-- apps:end -->

The table is written by the import described below. Do not edit it by hand.

## How an app gets here

An app does not need a manifest written by hand. When it publishes a release on GitHub, the release workflow of the app does two things:

1. It puts a file called `<app>.scoop.json` into the release. The app makes it itself, from its own metadata (name, version, description, license and homepage) and from the file it built (the download and its hash), so nothing is written down a second time. [outbound](https://github.com/shalemore/outbound) does this with `scripts/package.ps1`, which is a good example to copy.
2. It starts the `Import manifest` workflow of this bucket, which downloads that file and opens a pull request:
   - If the app is new, the manifest is created. If it is already here, the manifest is updated.
   - The table of apps above is written again.
   - Scoop's own checks run before the pull request is opened, because a pull request that the workflow token opens does not start the `CI` workflow.
   - Nothing is merged by itself. Look at the pull request and merge it.

The manifest is checked before it is used: it must be named `<app>.scoop.json`, its version must be the release tag, its download must come from that same release, and its hash must be a sha256. Everything it carries (a shortcut, a notice, a `pre_uninstall` step for a program that has to remove something it put on the computer) is the app's decision. It keeps `checkver` and `autoupdate`, so Scoop's own tools still work on it.

### Setting it up

- In the settings of this repository, under Actions, General, allow GitHub Actions to create and approve pull requests.
- In the repository of the app, add the secret `SCOOP_BUCKET_TOKEN`: a fine-grained personal access token for this repository alone, with the permission *Actions: Read and write*. It is only used to start the import workflow. Without it the release of the app still works, and the bucket is simply not told.
- The release workflow of the app looks for a repository called `scoop-bucket` of the same owner. A repository variable `SCOOP_BUCKET` in the app repository names another one.

### By hand

```pwsh
.\bin\import-manifest.ps1 -Repo shalemore/outbound -Tag v0.1.0
```

This needs the GitHub CLI, and it changes the files in this folder like the workflow does. `-ManifestFile` takes a manifest from a file instead of a release.

## Maintenance

```pwsh
.\bin\checkver.ps1 -App <app>      # compares with the latest release
.\bin\checkhashes.ps1 -App <app>   # verifies the hash of the download
.\bin\formatjson.ps1               # formats the manifests
.\bin\test.ps1                     # the same checks as CI
```

The `CI` workflow runs Scoop's checks on every push, and also the tests of the import in `tests`.
