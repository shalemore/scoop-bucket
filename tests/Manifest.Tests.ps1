BeforeAll {
    . "$PSScriptRoot/../lib/Manifest.ps1"

    function New-ManifestText {
        param([string] $Version = '1.2.3', [string] $Repo = 'owner/demo', [string] $Hash = ('a' * 64))
        $manifest = [ordered]@{
            version      = $Version
            description  = 'A demo | with a pipe'
            homepage     = "https://github.com/$Repo"
            license      = 'MIT'
            architecture = @{ '64bit' = [ordered]@{
                    url  = "https://github.com/$Repo/releases/download/v$Version/demo.exe#/demo.exe"
                    hash = $Hash
                } }
            bin          = 'demo.exe'
        }
        $manifest | ConvertTo-Json -Depth 10
    }

    function New-ReleaseFile {
        param([string] $Dir, [string] $Text, [string] $Name = 'demo.scoop.json')
        $path = Join-Path $Dir $Name
        [System.IO.File]::WriteAllText($path, $Text)
        $path
    }
}

Describe 'Assert-ImportInput' {
    It 'accepts a repository and a release tag' {
        { Assert-ImportInput -Repo 'owner/demo' -Tag 'v1.2.3' } | Should -Not -Throw
        { Assert-ImportInput -Repo 'o.w-n_er/de.mo' -Tag 'v1.2.3-rc.1' } | Should -Not -Throw
    }

    It 'rejects anything else' {
        { Assert-ImportInput -Repo 'owner' -Tag 'v1.2.3' } | Should -Throw
        { Assert-ImportInput -Repo 'owner/demo; rm -rf /' -Tag 'v1.2.3' } | Should -Throw
        { Assert-ImportInput -Repo 'owner/demo' -Tag '1.2.3' } | Should -Throw
        { Assert-ImportInput -Repo 'owner/demo' -Tag 'v1.2' } | Should -Throw
    }
}

Describe 'Read-ReleaseManifest' {
    It 'reads a manifest that belongs to the release' {
        $path = New-ReleaseFile -Dir $TestDrive -Text (New-ManifestText)
        $release = Read-ReleaseManifest -Path $path -Repo 'owner/demo' -Tag 'v1.2.3'
        $release.Name | Should -Be 'demo'
        $release.Version | Should -Be '1.2.3'
    }

    It 'refuses a manifest of another version' {
        $path = New-ReleaseFile -Dir $TestDrive -Text (New-ManifestText -Version '1.2.4')
        { Read-ReleaseManifest -Path $path -Repo 'owner/demo' -Tag 'v1.2.3' } | Should -Throw '*version*'
    }

    It 'refuses a download from another repository' {
        $path = New-ReleaseFile -Dir $TestDrive -Text (New-ManifestText -Repo 'someone/else')
        { Read-ReleaseManifest -Path $path -Repo 'owner/demo' -Tag 'v1.2.3' } | Should -Throw '*does not point*'
    }

    It 'refuses a hash that is not a sha256' {
        $path = New-ReleaseFile -Dir $TestDrive -Text (New-ManifestText -Hash 'nothash')
        { Read-ReleaseManifest -Path $path -Repo 'owner/demo' -Tag 'v1.2.3' } | Should -Throw '*sha256*'
    }

    It 'refuses a file with the wrong name or content' {
        $path = New-ReleaseFile -Dir $TestDrive -Text (New-ManifestText) -Name 'Demo.json'
        { Read-ReleaseManifest -Path $path -Repo 'owner/demo' -Tag 'v1.2.3' } | Should -Throw '*named*'
        $path = New-ReleaseFile -Dir $TestDrive -Text '{ not json' -Name 'broken.scoop.json'
        { Read-ReleaseManifest -Path $path -Repo 'owner/demo' -Tag 'v1.2.3' } | Should -Throw '*JSON*'
    }
}

Describe 'Save-Manifest' {
    BeforeEach {
        $bucket = Join-Path $TestDrive 'bucket'
    }

    It 'creates a manifest that is not there yet' {
        Save-Manifest -Name 'demo' -Bucket $bucket -Text (New-ManifestText) | Should -Be 'created'
        $bytes = [System.IO.File]::ReadAllText((Join-Path $bucket 'demo.json'))
        $bytes | Should -Match "`r`n"
        $bytes.TrimEnd() | ConvertFrom-Json | Select-Object -ExpandProperty version | Should -Be '1.2.3'
    }

    It 'says unchanged for the same manifest, however it is laid out' {
        Save-Manifest -Name 'demo' -Bucket $bucket -Text (New-ManifestText) | Out-Null
        $compact = (New-ManifestText) | ConvertFrom-Json | ConvertTo-Json -Depth 10 -Compress
        Save-Manifest -Name 'demo' -Bucket $bucket -Text $compact | Should -Be 'unchanged'
    }

    It 'updates a manifest that changed' {
        Save-Manifest -Name 'demo' -Bucket $bucket -Text (New-ManifestText) | Out-Null
        Save-Manifest -Name 'demo' -Bucket $bucket -Text (New-ManifestText -Version '1.3.0') | Should -Be 'updated'
        (Get-Content (Join-Path $bucket 'demo.json') -Raw | ConvertFrom-Json).version | Should -Be '1.3.0'
    }
}

Describe 'Update-AppsTable' {
    BeforeEach {
        $bucket = Join-Path $TestDrive 'bucket'
        New-Item -ItemType Directory -Force $bucket | Out-Null
        $readme = Join-Path $TestDrive 'README.md'
        $text = "# Bucket`r`n`r`n<!-- apps:start -->`r`n_No apps yet._`r`n<!-- apps:end -->`r`n`r`nThe end.`r`n"
        [System.IO.File]::WriteAllText($readme, $text)
    }

    It 'lists the apps with a link and an escaped description' {
        Save-Manifest -Name 'demo' -Bucket $bucket -Text (New-ManifestText) | Out-Null
        Update-AppsTable -Readme $readme -Bucket $bucket
        $text = [System.IO.File]::ReadAllText($readme)
        $text | Should -Match '\| \[demo\]\(https://github.com/owner/demo\) \| A demo \\\| with a pipe \|'
        $text | Should -Match 'The end\.'
    }

    It 'goes back to saying that there are no apps' {
        Save-Manifest -Name 'demo' -Bucket $bucket -Text (New-ManifestText) | Out-Null
        Update-AppsTable -Readme $readme -Bucket $bucket
        Remove-Item (Join-Path $bucket 'demo.json')
        Update-AppsTable -Readme $readme -Bucket $bucket
        [System.IO.File]::ReadAllText($readme) | Should -Match '_No apps yet\._'
    }

    It 'keeps the line endings and gives the same result when it runs again' {
        Save-Manifest -Name 'demo' -Bucket $bucket -Text (New-ManifestText) | Out-Null
        Update-AppsTable -Readme $readme -Bucket $bucket
        $first = [System.IO.File]::ReadAllText($readme)
        Update-AppsTable -Readme $readme -Bucket $bucket
        [System.IO.File]::ReadAllText($readme) | Should -BeExactly $first
        ($first -replace "`r`n", '').Contains("`n") | Should -BeFalse
    }

    It 'complains when the markers are missing' {
        [System.IO.File]::WriteAllText($readme, "# no markers`r`n")
        { Update-AppsTable -Readme $readme -Bucket $bucket } | Should -Throw '*markers*'
    }
}
