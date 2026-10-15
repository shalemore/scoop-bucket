# Functions that import the Scoop manifest of an app into this bucket. They work with Windows
# PowerShell 5.1 and with PowerShell 7, because CI runs the tests with both.

# The release of an app carries its manifest as <app>.scoop.json.
$script:ManifestFilePattern = '^(?<name>[a-z0-9][a-z0-9._-]*)\.scoop\.json$'

function Assert-ImportInput {
    param([string] $Repo, [string] $Tag)

    if ($Repo -notmatch '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$') {
        throw "'$Repo' is not a repository written as owner/name"
    }
    if ($Tag -notmatch '^v\d+\.\d+\.\d+([-+][0-9A-Za-z.+-]+)?$') {
        throw "'$Tag' is not a release tag such as v1.2.3"
    }
}

# Reads the manifest of a release and checks that it belongs to that release.
function Read-ReleaseManifest {
    param([string] $Path, [string] $Repo, [string] $Tag)

    $file = Split-Path $Path -Leaf
    if ($file -notmatch $script:ManifestFilePattern) {
        throw "'$file' is not named <app>.scoop.json"
    }
    $name = $Matches['name']

    $text = [System.IO.File]::ReadAllText($Path)
    try {
        $manifest = $text | ConvertFrom-Json
    } catch {
        throw "'$file' is not valid JSON: $_"
    }

    $version = $Tag.Substring(1)
    if ($manifest.version -ne $version) {
        throw "The manifest is for version '$($manifest.version)', but the release is $Tag"
    }
    $download = $manifest.architecture.'64bit'
    $prefix = "https://github.com/$Repo/releases/download/$Tag/"
    if (-not $download.url -or -not $download.url.StartsWith($prefix)) {
        throw "The download in the manifest does not point to the release $Tag of $Repo"
    }
    if ($download.hash -notmatch '^[0-9a-f]{64}$') {
        throw "The hash in the manifest is not a sha256: '$($download.hash)'"
    }

    [pscustomobject]@{ Name = $name; Version = $version; Text = $text }
}

# A text of a manifest in which the order of the properties and the layout do not matter, to see
# whether two manifests say the same.
function Get-CanonicalJson {
    param($Value)

    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $pairs = $Value.PSObject.Properties | Sort-Object Name | ForEach-Object {
            '"' + $_.Name + '":' + (Get-CanonicalJson $_.Value)
        }
        return '{' + ($pairs -join ',') + '}'
    }
    if ($Value -is [System.Array]) {
        return '[' + (@($Value | ForEach-Object { Get-CanonicalJson $_ }) -join ',') + ']'
    }
    ConvertTo-Json -InputObject $Value -Compress
}

# Writes the manifest into the bucket and says what happened: created, updated or unchanged. The
# file gets the line endings that the checks of Scoop ask for.
function Save-Manifest {
    param([string] $Name, [string] $Bucket, [string] $Text)

    $target = Join-Path $Bucket "$Name.json"
    $new = ($Text -replace "`r`n", "`n").TrimEnd("`n") + "`n"
    $action = 'created'
    if (Test-Path $target) {
        $old = [System.IO.File]::ReadAllText($target)
        if ((Get-CanonicalJson ($old | ConvertFrom-Json)) -eq (Get-CanonicalJson ($new | ConvertFrom-Json))) {
            return 'unchanged'
        }
        $action = 'updated'
    }
    New-Item -ItemType Directory -Force $Bucket | Out-Null
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($target, $new.Replace("`n", "`r`n"), $utf8)
    $action
}

# Rewrites the table of apps in the README, between the two markers, from the manifests.
function Update-AppsTable {
    param([string] $Readme, [string] $Bucket)

    $rows = @(Get-ChildItem $Bucket -Filter '*.json' | Sort-Object Name | ForEach-Object {
        $app = [System.IO.File]::ReadAllText($_.FullName) | ConvertFrom-Json
        $description = ([string] $app.description).Replace('|', '\|')
        "| [$($_.BaseName)]($($app.homepage)) | $description |"
    })
    if ($rows.Count -gt 0) {
        $table = (@('| App | Description |', '| --- | --- |') + $rows) -join "`n"
    } else {
        $table = '_No apps yet._'
    }

    $text = [System.IO.File]::ReadAllText($Readme) -replace "`r`n", "`n"
    $pattern = '(?s)(<!-- apps:start -->\n).*?(\n<!-- apps:end -->)'
    if ($text -notmatch $pattern) {
        throw 'The README has no <!-- apps:start --> and <!-- apps:end --> markers'
    }
    $text = [regex]::Replace($text, $pattern, { param($m) $m.Groups[1].Value + $table + $m.Groups[2].Value })
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Readme, $text.Replace("`n", "`r`n"), $utf8)
}
