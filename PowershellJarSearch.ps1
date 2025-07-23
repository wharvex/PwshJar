param(
    [string]$RootDir = "."
)

# Helper: Extract archive to temp dir
function Extract-Archive {
    param($ArchivePath, $DestDir)
    # Prefer 7z for all types, fallback to jar for jars
    if (Get-Command 7z -ErrorAction SilentlyContinue) {
        & 7z x "$ArchivePath" "-o$DestDir" -y | Out-Null
    } elseif ($ArchivePath -like "*.jar" -and (Get-Command jar -ErrorAction SilentlyContinue)) {
        & jar xf "$ArchivePath" -C "$DestDir"
    } else {
        throw "No suitable extraction tool found for $ArchivePath"
    }
}

# 1. Find all .jar, .war, .ear files
$archives = Get-ChildItem -Path $RootDir -Recurse -Include *.jar,*.war,*.ear

if (-not $archives) {
    Write-Host "No archives found in $RootDir"
    exit 1
}

# 2. For each archive, extract and search
$tempRoot = New-TemporaryFile | Remove-Item -Force; [System.IO.Path]::GetTempPath() + [System.Guid]::NewGuid().ToString()
New-Item -ItemType Directory -Path $tempRoot | Out-Null

$resultsFile = [System.IO.Path]::GetTempFileName()

foreach ($archive in $archives) {
    $tempDir = Join-Path $tempRoot ([System.Guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $tempDir | Out-Null

    try {
        Extract-Archive -ArchivePath $archive.FullName -DestDir $tempDir

        # Find source/code files (adjust file types as needed)
        $codeFiles = Get-ChildItem -Path $tempDir -Recurse -File |
            Where-Object { $_.Extension -match "^\.(java|xml|properties|js|ts|py|rb|sh|groovy|scala|kt|html|css|json|yml|yaml|txt)$" }

        foreach ($file in $codeFiles) {
            $lines = Get-Content $file.FullName
            for ($i = 0; $i -lt $lines.Count; $i++) {
                # Format: archive!relative/path:line_number:line_content
                $relativePath = $file.FullName.Substring($tempDir.Length).TrimStart('\','/')
                $entry = "$($archive.FullName)!$relativePath:$($i+1):$($lines[$i])"
                Add-Content -Path $resultsFile -Value $entry
            }
        }
    } finally {
        Remove-Item -Recurse -Force $tempDir
    }
}

# 3. Pipe into fzf
if (Test-Path $resultsFile) {
    Get-Content $resultsFile | fzf --ansi --preview "echo {}"
    Remove-Item $resultsFile
} else {
    Write-Host "No code lines found in archives."
}

Remove-Item -Recurse -Force $tempRoot
