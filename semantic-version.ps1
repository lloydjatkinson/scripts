<#
.SYNOPSIS
    Calculates the current semantic version purely from conventional commit history.
.DESCRIPTION
    Starts from an initial version and processes all commits to determine what the version
    should be based on conventional commit messages following the official spec.
.PARAMETER StartVersion
    The initial version to start from (default: 0.0.0)
.PARAMETER FromCommit
    Optional: Calculate version from a specific commit hash onwards
#>

param(
    [string]$StartVersion = "0.0.0",
    [string]$FromCommit = $null
)

function Get-AllCommits {
    param(
        [string]$FromCommit
    )
    
    if ($FromCommit) {
        # Get commits from specified commit to HEAD
        $commits = git log "$FromCommit..HEAD" --pretty=format:"%H|%s|%b" --reverse
    } else {
        # Get all commits from the beginning
        $commits = git log --pretty=format:"%H|%s|%b" --reverse
    }
    
    return $commits
}

function Update-VersionFromCommit {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Version,
        
        [Parameter(Mandatory)]
        [string]$CommitMessage,
        
        [AllowEmptyString()]
        [string]$CommitBody = ""
    )
    
    $fullMessage = "$CommitMessage`n$CommitBody"
    
    # Check for breaking changes (MAJOR bump)
    # BREAKING CHANGE can appear in any commit type
    if ($CommitMessage -match '!:' -or $fullMessage -match 'BREAKING[\s-]CHANGE:') {
        $Version.Major++
        $Version.Minor = 0
        $Version.Patch = 0
        return "MAJOR"
    }
    # Check for features (MINOR bump)
    elseif ($CommitMessage -match '^feat(\(.+\))?:') {
        $Version.Minor++
        $Version.Patch = 0
        return "MINOR"
    }
    # Check for fixes (PATCH bump)
    elseif ($CommitMessage -match '^fix(\(.+\))?:') {
        $Version.Patch++
        return "PATCH"
    }
    
    # Per spec: other types (docs, style, refactor, perf, test, chore, build, ci)
    # have NO implicit effect on semantic versioning
    return "NONE"
}

function Get-VersionFromCommits {
    param(
        [Parameter(Mandatory)]
        [string]$StartVersion,
        
        [string]$FromCommit = $null
    )
    
    # Parse starting version
    $versionParts = $StartVersion -split '\.'
    $version = @{
        Major = [int]$versionParts[0]
        Minor = [int]$versionParts[1]
        Patch = [int]$versionParts[2]
    }
    
    $commits = Get-AllCommits -FromCommit $FromCommit
    
    if (-not $commits) {
        Write-Host "No commits found." -ForegroundColor Yellow
        return $version
    }
    
    $commitCount = 0
    $bumpCounts = @{
        MAJOR = 0
        MINOR = 0
        PATCH = 0
        NONE = 0
    }
    
    foreach ($commitLine in $commits) {
        # Skip empty lines
        if ([string]::IsNullOrWhiteSpace($commitLine)) { 
            continue 
        }
        
        # Parse the commit line
        $parts = $commitLine -split '\|', 3
        
        # Validate we have at least hash and subject
        if ($parts.Count -lt 2) {
            continue
        }
        
        $hash = $parts[0]
        $subject = $parts[1]
        $body = if ($parts.Count -gt 2) { $parts[2] } else { "" }
        
        # Skip if subject is empty
        if ([string]::IsNullOrWhiteSpace($subject)) {
            continue
        }
        
        $bumpType = Update-VersionFromCommit -Version $version -CommitMessage $subject -CommitBody $body
        $bumpCounts[$bumpType]++
        $commitCount++
    }
    
    return [PSCustomObject]@{
        Major = $version.Major
        Minor = $version.Minor
        Patch = $version.Patch
        FullVersion = "$($version.Major).$($version.Minor).$($version.Patch)"
        CommitCount = $commitCount
        BumpCounts = $bumpCounts
    }
}

# Main script execution
try {
    # Check if we're in a git repository
    $gitCheck = git rev-parse --git-dir 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Not a git repository"
        exit 1
    }
    
    Write-Host "`n=== Semantic Version from Conventional Commits ===" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "Starting Version: $StartVersion" -ForegroundColor Gray
    if ($FromCommit) {
        Write-Host "From Commit:      $FromCommit" -ForegroundColor Gray
    } else {
        Write-Host "Analyzing:        All commits" -ForegroundColor Gray
    }
    Write-Host ""
    
    $result = Get-VersionFromCommits -StartVersion $StartVersion -FromCommit $FromCommit
    
    Write-Host "Current Version:  " -NoNewline
    Write-Host $result.FullVersion -ForegroundColor Green
    Write-Host "Total Commits:    $($result.CommitCount)" -ForegroundColor Gray
    
    if ($result.CommitCount -gt 0) {
        Write-Host "`nVersion Bumps Applied:" -ForegroundColor Cyan
        Write-Host "  Major (Breaking): $($result.BumpCounts.MAJOR)" -ForegroundColor $(if ($result.BumpCounts.MAJOR -gt 0) { "Red" } else { "Gray" })
        Write-Host "  Minor (Features): $($result.BumpCounts.MINOR)" -ForegroundColor $(if ($result.BumpCounts.MINOR -gt 0) { "Yellow" } else { "Gray" })
        Write-Host "  Patch (Fixes):    $($result.BumpCounts.PATCH)" -ForegroundColor $(if ($result.BumpCounts.PATCH -gt 0) { "Green" } else { "Gray" })
        
        if ($result.BumpCounts.NONE -gt 0) {
            Write-Host "  No bump:          $($result.BumpCounts.NONE)" -ForegroundColor DarkGray
        }
    }
    
    Write-Host ""
    
    # Output just the version for easy parsing in scripts
    if ($env:CI -eq "true" -or $args -contains "--version-only") {
        Write-Output $result.FullVersion
    }
    
} catch {
    Write-Error "An error occurred: $_"
    exit 1
}