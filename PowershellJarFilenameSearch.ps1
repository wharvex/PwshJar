param(
    [string]$RootDir = "."
)

function List-Archive-Contents {
    param($ArchivePath)
    # Prefer 7z for all types, fallback to jar for jars
    if (Get-Command 7z -ErrorAction SilentlyContinue) {
        & 7z l -ba "$ArchivePath" | ForEach-Object {
            # 7z l -ba outputs: [date] [time] [attr] [size] [compressed] [name]
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

if ($results.Count -gt 0) {
    $results | fzf --ansi --preview "echo {}"
} else {
    Write-Host "No files found within archives."
}
