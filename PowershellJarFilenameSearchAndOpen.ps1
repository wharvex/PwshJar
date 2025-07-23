param(
    [string]$RootDir = "."
)

function List-Archive-Contents {
    param($ArchivePath)
    if (Get-Command 7z -ErrorAction SilentlyContinue) {
        & 7z l -ba "$ArchivePath" | ForEach-Object {
            $parts = $_ -split "\s+", 6
            if ($parts.Count -eq 6) {
                $parts[5]
            }
        }
    } elseif ($ArchivePath -like "*.jar" -and (Get-Command jar -ErrorAction SilentlyContinue)) {
        & jar tf "$ArchivePath"
    } else {
        throw "No suitable listing tool found for $ArchivePath"
    }
}

function Extract-File-From-Archive {
    param($ArchivePath, $InternalPath, $DestFile)
    if (Get-Command 7z -ErrorAction SilentlyContinue) {
        # 7z will recreate the directory structure unless you use -so (stdout)
        & 7z e "$ArchivePath" "$InternalPath" -so > "$DestFile"
    } elseif ($ArchivePath -like "*.jar" -and (Get-Command jar -ErrorAction SilentlyContinue)) {
        # jar cannot extract a single file to stdout, so extract to temp dir and move
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $tempDir | Out-Null
        Push-Location $tempDir
        & jar xf "$ArchivePath" "$InternalPath"
        Pop-Location
        $source = Join-Path $tempDir $InternalPath
        Copy-Item $source "$DestFile"
        Remove-Item -Recurse -Force $tempDir
    } else {
        throw "No suitable extraction tool found for $ArchivePath"
    }
}

$archives = Get-ChildItem -Path $RootDir -Recurse -Include *.jar,*.war,*.ear

if (-not $archives) {
    Write-Host "No archives found in $RootDir"
    exit 1
}

$results = @()

foreach ($archive in $archives) {
    try {
        $files = List-Archive-Contents -ArchivePath $archive.FullName
        foreach ($file in $files) {
            if ($file -and $file -ne "." -and $file -ne "..") {
                $results += "$($archive.FullName)!$file"
            }
        }
    } catch {
        Write-Warning "Failed to list $($archive.FullName): $_"
    }
}

if ($results.Count -eq 0) {
    Write-Host "No files found within archives."
    exit 1
}

# Use fzf and capture the selection
$selection = $results | fzf --ansi --preview "echo {}"

if (-not $selection) {
    Write-Host "No selection made."
    exit 0
}

# Parse selection: archive!internal/path
if ($selection -match "^(.*)!(.*)$") {
    $archivePath = $matches[1]
    $internalPath = $matches[2]
    $tmpFile = [System.IO.Path]::GetTempFileName()
    try {
        Extract-File-From-Archive -ArchivePath $archivePath -InternalPath $internalPath -DestFile $tmpFile
        vim $tmpFile
    } finally {
        Remove-Item $tmpFile -Force
    }
} else {
    Write-Host "Selection format not recognized."
    exit 1
}
