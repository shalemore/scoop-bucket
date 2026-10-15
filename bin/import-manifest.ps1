<#
.SYNOPSIS
    Imports the Scoop manifest of an app from its GitHub release into this bucket: creates the
    manifest if the app is new, updates it if the app is already here, and rewrites the table of
    apps in the README.

.DESCRIPTION
    The release of the app carries a file called <app>.scoop.json, made by the app itself from its
    own metadata and from the file it built. This script does not know anything about the app.

.EXAMPLE
    .\bin\import-manifest.ps1 -Repo shalemore/outbound -Tag v0.1.0

.EXAMPLE
    .\bin\import-manifest.ps1 -Repo shalemore/outbound -Tag v0.1.0 -ManifestFile .\outbound.scoop.json
#>
param(
    [Parameter(Mandatory)] [string] $Repo,
    [Parameter(Mandatory)] [string] $Tag,
    # Reads the manifest from this file instead of downloading it, to try things out by hand.
    [string] $ManifestFile
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/../lib/Manifest.ps1"

$root = Split-Path $PSScriptRoot -Parent
$bucket = Join-Path $root 'bucket'
Assert-ImportInput -Repo $Repo -Tag $Tag

if (-not $ManifestFile) {
    $download = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
    New-Item -ItemType Directory $download | Out-Null
    gh release download $Tag --repo $Repo --pattern '*.scoop.json' --dir $download
    if ($LASTEXITCODE -ne 0) { throw "Cannot download the manifest of release $Tag of $Repo" }
    $files = @(Get-ChildItem $download -Filter '*.scoop.json')
    if ($files.Count -ne 1) { throw "Expected one *.scoop.json file in the release, found $($files.Count)" }
    $ManifestFile = $files[0].FullName
}

$release = Read-ReleaseManifest -Path $ManifestFile -Repo $Repo -Tag $Tag
$action = Save-Manifest -Name $release.Name -Bucket $bucket -Text $release.Text
Update-AppsTable -Readme (Join-Path $root 'README.md') -Bucket $bucket

# Lets Scoop format the manifest the way it likes it, when Scoop is there.
if ($action -ne 'unchanged' -and ($env:SCOOP_HOME -or (Get-Command scoop -ErrorAction SilentlyContinue))) {
    & "$PSScriptRoot/formatjson.ps1" -App $release.Name
}

Write-Host "$action $($release.Name) $($release.Version)"
if ($env:GITHUB_OUTPUT) {
    $changed = if ($action -eq 'unchanged') { 'false' } else { 'true' }
    Add-Content -Path $env:GITHUB_OUTPUT -Value "name=$($release.Name)", "version=$($release.Version)", "action=$action", "changed=$changed"
}
