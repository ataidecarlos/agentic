# deploy.ps1 — Deploy agents, skills, prompts, MCP servers and AGENTS.md to Opencode
#
# Usage:
#   .\deploy.ps1                    # Deploy to user-global (~/.config/opencode/)
#   .\deploy.ps1 -Project .         # Deploy to current project (.opencode/)
#   .\deploy.ps1 -NoMcp             # Skip the MCP server merge
#   .\deploy.ps1 -NoPrompts         # Skip prompt -> command deployment
#
# The deployment is idempotent: running it twice produces the same result and
# never duplicates the AGENTS.md block or the MCP server entries.

param(
    [string]$Project,
    [switch]$NoMcp,
    [switch]$NoPrompts
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$AgentsDir = Join-Path $ScriptDir "agents"
$SkillsDir = Join-Path $ScriptDir "skills"
$PromptsDir = Join-Path $ScriptDir "prompts"
$McpSnippet = Join-Path $ScriptDir "mcp/agentic.opencode.json"
$AgentsMd = Join-Path $ScriptDir "AGENTS.md"

# Markers used to replace (rather than append) our AGENTS.md block.
$BeginMarker = "<!-- agentic:begin -->"
$EndMarker = "<!-- agentic:end -->"

# Validate source directories exist
foreach ($Required in @(
    @{ Path = $AgentsDir; Label = "agents" },
    @{ Path = $SkillsDir; Label = "skills" },
    @{ Path = $AgentsMd;  Label = "AGENTS.md" }
)) {
    if (-not (Test-Path -LiteralPath $Required.Path)) {
        Write-Error "$($Required.Label) not found: $($Required.Path)"
        exit 1
    }
}

$UsingMcp = $false
if (-not $NoMcp) {
    if (Test-Path -LiteralPath $McpSnippet) {
        $UsingMcp = $true
    } else {
        Write-Warning "MCP snippet not found, skipping MCP merge: $McpSnippet"
    }
}

$UsingPrompts = $false
if (-not $NoPrompts) {
    if (Test-Path -LiteralPath $PromptsDir) {
        $UsingPrompts = $true
    } else {
        Write-Warning "Prompts directory not found, skipping prompt deployment: $PromptsDir"
    }
}

# Determine target directories
if ($Project) {
    $ResolvedProject = (Resolve-Path -LiteralPath $Project -ErrorAction Stop).Path
    $TargetBase = Join-Path $ResolvedProject ".opencode"
    Write-Host "Deploying to project: $TargetBase" -ForegroundColor Cyan
} else {
    $TargetBase = Join-Path (Join-Path $env:USERPROFILE ".config") "opencode"
    Write-Host "Deploying to global: $TargetBase" -ForegroundColor Cyan
}

$TargetAgentsDir = Join-Path $TargetBase "agents"
$TargetSkillsDir = Join-Path $TargetBase "skills"

# Create target directories
New-Item -ItemType Directory -Force -Path $TargetAgentsDir | Out-Null
New-Item -ItemType Directory -Force -Path $TargetSkillsDir | Out-Null

# ---------------------------------------------------------------------------
# Agents
# ---------------------------------------------------------------------------
$AgentFiles = @(Get-ChildItem -Path $AgentsDir -Filter "*.md" -File)

if ($AgentFiles.Count -eq 0) {
    Write-Warning "No agent files found in $AgentsDir"
}

$AgentCount = 0
foreach ($File in $AgentFiles) {
    $TargetFile = Join-Path $TargetAgentsDir $File.Name
    Copy-Item -Path $File.FullName -Destination $TargetFile -Force
    Write-Host "  Agent: $($File.Name)" -ForegroundColor Green
    $AgentCount++
}

# ---------------------------------------------------------------------------
# Skills
# ---------------------------------------------------------------------------
$SkillDirs = @(Get-ChildItem -Path $SkillsDir -Directory)

if ($SkillDirs.Count -eq 0) {
    Write-Warning "No skill directories found in $SkillsDir"
}

$SkillCount = 0
$EmptySkillDirs = @()
foreach ($Dir in $SkillDirs) {
    $SkillMd = Join-Path $Dir.FullName "SKILL.md"

    if (-not (Test-Path -LiteralPath $SkillMd)) {
        # An empty directory is almost always an unpopulated git submodule or a
        # symlink that the platform could not materialise. Say so explicitly
        # instead of emitting a generic "SKILL.md not found" warning.
        if ((Get-ChildItem -LiteralPath $Dir.FullName -Recurse -Force | Measure-Object).Count -eq 0) {
            $EmptySkillDirs += $Dir.Name
            Write-Warning "Skipping $($Dir.Name): directory is empty (unpopulated gitlink? add a matching .gitmodules entry or remove it)"
        } else {
            Write-Warning "Skipping $($Dir.Name): SKILL.md not found"
        }
        continue
    }

    $TargetSkillDir = Join-Path $TargetSkillsDir $Dir.Name
    New-Item -ItemType Directory -Force -Path $TargetSkillDir | Out-Null

    Copy-Item -Path $SkillMd -Destination (Join-Path $TargetSkillDir "SKILL.md") -Force
    Write-Host "  Skill: $($Dir.Name)" -ForegroundColor Green

    # Copy any additional files (scripts/, references/, etc.), replacing the
    # destination directory so removed files do not linger between deploys.
    $AdditionalFiles = Get-ChildItem -Path $Dir.FullName -File -Recurse -Force | Where-Object { $_.FullName -ne $SkillMd }
    foreach ($File in $AdditionalFiles) {
        $RelativePath = $File.FullName.Substring($Dir.FullName.Length + 1)
        $TargetFilePath = Join-Path $TargetSkillDir $RelativePath
        $TargetFileDir = Split-Path -Parent $TargetFilePath
        New-Item -ItemType Directory -Force -Path $TargetFileDir | Out-Null
        Copy-Item -Path $File.FullName -Destination $TargetFilePath -Force
    }

    $SkillCount++
}

# ---------------------------------------------------------------------------
# Prompts -> commands
#
# prompts/<name>.md is the canonical prompt. Opencode exposes reusable prompt
# templates as slash commands, so each prompt becomes commands/<name>.md and is
# invocable as /<name>.
# ---------------------------------------------------------------------------
$PromptCount = 0
if ($UsingPrompts) {
    $TargetCommandsDir = Join-Path $TargetBase "commands"
    New-Item -ItemType Directory -Force -Path $TargetCommandsDir | Out-Null

    $PromptFiles = @(Get-ChildItem -Path $PromptsDir -Filter "*.md" -File)
    foreach ($File in $PromptFiles) {
        $TargetFile = Join-Path $TargetCommandsDir $File.Name
        Copy-Item -Path $File.FullName -Destination $TargetFile -Force
        Write-Host "  Prompt -> command: /$($File.BaseName)" -ForegroundColor Green
        $PromptCount++
    }

    if ($PromptCount -eq 0) {
        Write-Warning "No prompt files found in $PromptsDir"
    }
}

# ---------------------------------------------------------------------------
# AGENTS.md (idempotent marked block)
# ---------------------------------------------------------------------------
$TargetAgentsMd = Join-Path $TargetBase "AGENTS.md"
$ProjectContent = (Get-Content -LiteralPath $AgentsMd -Raw).TrimEnd()
$Block = "$BeginMarker`n$ProjectContent`n$EndMarker"

if (Test-Path -LiteralPath $TargetAgentsMd) {
    Copy-Item -LiteralPath $TargetAgentsMd -Destination "$TargetAgentsMd.bak" -Force

    $Existing = Get-Content -LiteralPath $TargetAgentsMd -Raw
    $BeginIndex = $Existing.IndexOf($BeginMarker)
    # Match the LAST end marker. The block content is free text and may itself
    # mention the markers, so the first occurrence cannot be trusted.
    $EndIndex = $Existing.LastIndexOf($EndMarker)

    if ($BeginIndex -ge 0 -and $EndIndex -gt $BeginIndex) {
        # Replace the previous block in place; everything outside the markers
        # (global instructions, other blocks) is preserved untouched.
        $Before = $Existing.Substring(0, $BeginIndex).TrimEnd()
        $After = $Existing.Substring($EndIndex + $EndMarker.Length).TrimStart("`r", "`n")
        $New = if ($Before) { "$Before`n`n$Block" } else { $Block }
        if ($After) { $New = "$New`n$After" }
        Set-Content -LiteralPath $TargetAgentsMd -Value $New -NoNewline
        Write-Host "  AGENTS.md: Replaced agentic block (idempotent)" -ForegroundColor Green
    } else {
        # First deployment against a file we have not written before: migrate a
        # legacy append (old scripts used a plain HTML comment marker) into the
        # marked block so future runs do not keep appending.
        $LegacyMarker = "<!-- Appended from agentic project -->"
        $LegacyIndex = $Existing.IndexOf($LegacyMarker)
        if ($LegacyIndex -ge 0) {
            $Before = $Existing.Substring(0, $LegacyIndex).TrimEnd()
            $New = if ($Before) { "$Before`n`n$Block" } else { $Block }
            Set-Content -LiteralPath $TargetAgentsMd -Value $New -NoNewline
            Write-Host "  AGENTS.md: Migrated legacy appended block to marked block" -ForegroundColor Green
        } else {
            $Existing = $Existing.TrimEnd()
            Set-Content -LiteralPath $TargetAgentsMd -Value "$Existing`n`n$Block" -NoNewline
            Write-Host "  AGENTS.md: Appended agentic block" -ForegroundColor Green
        }
        Write-Host "  AGENTS.md: Backed up existing file to AGENTS.md.bak" -ForegroundColor Yellow
    }
} else {
    Set-Content -LiteralPath $TargetAgentsMd -Value $Block -NoNewline
    Write-Host "  AGENTS.md: Created with agentic block" -ForegroundColor Green
}

# Always terminate AGENTS.md with exactly one trailing newline. Set-Content is
# used with -NoNewline above so the marked block is byte-stable across runs.
$FinalMd = (Get-Content -LiteralPath $TargetAgentsMd -Raw).TrimEnd("`r", "`n") + "`n"
Set-Content -LiteralPath $TargetAgentsMd -Value $FinalMd -NoNewline

# ---------------------------------------------------------------------------
# MCP servers
#
# Opencode loads exactly one extra config file (OPENCODE_CONFIG), so MCP servers
# must be merged into the target's own opencode.json(c). The merge is
# name-scoped: only keys defined in mcp/agentic.opencode.json are written, and
# everything else in the target config is preserved.
# ---------------------------------------------------------------------------
function Remove-JsonComments {
    param([string]$Text)

    $sb = New-Object System.Text.StringBuilder
    $inString = $false
    $escaped = $false

    for ($i = 0; $i -lt $Text.Length; $i++) {
        $c = $Text[$i]

        if ($inString) {
            [void]$sb.Append($c)
            if ($escaped) { $escaped = $false }
            elseif ($c -eq '\') { $escaped = $true }
            elseif ($c -eq '"') { $inString = $false }
            continue
        }

        if ($c -eq '"') { $inString = $true; [void]$sb.Append($c); continue }

        # Line comment
        if ($c -eq '/' -and ($i + 1) -lt $Text.Length -and $Text[$i + 1] -eq '/') {
            while ($i -lt $Text.Length -and $Text[$i] -ne "`n") { $i++ }
            [void]$sb.Append("`n")
            continue
        }

        # Block comment
        if ($c -eq '/' -and ($i + 1) -lt $Text.Length -and $Text[$i + 1] -eq '*') {
            $i += 2
            while ($i -lt $Text.Length -and -not ($Text[$i] -eq '*' -and ($i + 1) -lt $Text.Length -and $Text[$i + 1] -eq '/')) { $i++ }
            $i++
            continue
        }

        [void]$sb.Append($c)
    }

    $result = $sb.ToString()
    # Remove trailing commas before } or ]
    $result = [regex]::Replace($result, ',(\s*[}\]])', '$1')
    return $result
}

function ConvertTo-HashtableDeep {
    param($Value)

    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Collections.IDictionary]) {
        $h = @{}
        foreach ($k in $Value.Keys) { $h[$k] = ConvertTo-HashtableDeep $Value[$k] }
        return $h
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        return @($Value | ForEach-Object { ConvertTo-HashtableDeep $_ })
    }
    return $Value
}

function ConvertTo-SortedOrdered {
    param($Value)

    if ($Value -is [System.Collections.IDictionary]) {
        $ordered = [ordered]@{}
        foreach ($k in ($Value.Keys | Sort-Object)) { $ordered[$k] = ConvertTo-SortedOrdered $Value[$k] }
        return $ordered
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        return , @($Value | ForEach-Object { ConvertTo-SortedOrdered $_ })
    }
    return $Value
}

$McpCount = 0
if ($UsingMcp) {
    # -AsHashtable so the servers object exposes .Keys; ConvertFrom-Json without
    # it yields PSCustomObject, whose property names are not enumerable that way.
    $Snippet = ConvertFrom-Json (Get-Content -LiteralPath $McpSnippet -Raw) -AsHashtable
    $SnippetServers = $Snippet["mcp"]["servers"]
    if ($null -eq $SnippetServers) {
        Write-Warning "Snippet has no mcp.servers object, skipping: $McpSnippet"
    } else {
        $TargetConfig = $null
        foreach ($Candidate in @("opencode.jsonc", "opencode.json")) {
            $CandidatePath = Join-Path $TargetBase $Candidate
            if (Test-Path -LiteralPath $CandidatePath) { $TargetConfig = $CandidatePath; break }
        }

        if ($null -eq $TargetConfig) {
            $TargetConfig = Join-Path $TargetBase "opencode.jsonc"
            Set-Content -LiteralPath $TargetConfig -Value "{}" -NoNewline
            Write-Host "  MCP: Created $TargetConfig" -ForegroundColor Yellow
        }

        $RawText = Get-Content -LiteralPath $TargetConfig -Raw
        $HadComments = $RawText -match '(?m)^\s*//' -or $RawText.Contains('/*')
        $Config = ConvertTo-HashtableDeep (Remove-JsonComments $RawText | ConvertFrom-Json -AsHashtable)

        if ($null -eq $Config) { $Config = @{} }
        if ($null -eq $Config["mcp"]) { $Config["mcp"] = @{} }
        if ($null -eq $Config["mcp"]["servers"]) { $Config["mcp"]["servers"] = @{} }

        foreach ($Name in $SnippetServers.Keys) {
            $Config["mcp"]["servers"][$Name] = $SnippetServers[$Name]
            Write-Host "  MCP: $Name" -ForegroundColor Green
            $McpCount++
        }

        $BackupPath = "$TargetConfig.bak"
        Copy-Item -LiteralPath $TargetConfig -Destination $BackupPath -Force

        # Recursively sort object keys. PowerShell hashtable enumeration order is
        # not guaranteed, so sorting at every level (arrays keep their order) is
        # what makes the written file byte-stable across runs and reviewable in
        # version control.
        $Json = (ConvertTo-SortedOrdered $Config) | ConvertTo-Json -Depth 20
        Set-Content -LiteralPath $TargetConfig -Value ($Json + "`n") -NoNewline

        if ($HadComments) {
            Write-Warning "MCP: $TargetConfig contained comments; they were stripped by the JSONC merge. Original saved at $BackupPath"
        }
        Write-Host "  MCP: Merged $McpCount server(s) into $TargetConfig" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "Deployed $AgentCount agent(s), $SkillCount skill(s), $PromptCount prompt(s), $McpCount MCP server(s), and AGENTS.md" -ForegroundColor Green
Write-Host "Agents:  $TargetAgentsDir" -ForegroundColor Yellow
Write-Host "Skills:  $TargetSkillsDir" -ForegroundColor Yellow
if ($UsingPrompts) { Write-Host "Commands: $(Join-Path $TargetBase 'commands')" -ForegroundColor Yellow }
if ($UsingMcp) { Write-Host "MCP:     $(Join-Path $TargetBase 'opencode.jsonc')" -ForegroundColor Yellow }
Write-Host "AGENTS.md: $TargetAgentsMd" -ForegroundColor Yellow

if ($EmptySkillDirs.Count -gt 0) {
    Write-Host ""
    Write-Warning "Unpopulated skill directories skipped: $($EmptySkillDirs -join ', ')"
    Write-Warning "These are committed as gitlinks without a .gitmodules entry, so a fresh clone gets empty directories."
}