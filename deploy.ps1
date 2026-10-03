# deploy.ps1 — Deploy agents, skills, prompts, managed config and AGENTS.md to Opencode
#
# Usage:
#   .\deploy.ps1                    # Deploy to user-global (~/.config/opencode/)
#   .\deploy.ps1 -Project .         # Deploy to current project (.opencode/)
#   .\deploy.ps1 -NoConfig          # Skip the managed config merge (MCP, skills, plugins)
#   .\deploy.ps1 -NoPrompts         # Skip prompt -> command deployment
#
# The deployment is idempotent: running it twice produces the same result and
# never duplicates the AGENTS.md block or any managed config entry.

param(
    [string]$Project,
    [switch]$NoConfig,
    [switch]$NoPrompts
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$AgentsDir = Join-Path $ScriptDir "agents"
$SkillsDir = Join-Path $ScriptDir "skills"
$PromptsDir = Join-Path $ScriptDir "prompts"
$ConfigSnippet = Join-Path $ScriptDir "config/agentic.opencode.json"
$AgentsMd = Join-Path $ScriptDir "AGENTS.md"

# Markers used to replace (rather than append) our AGENTS.md block.
$BeginMarker = "<!-- agentic:begin -->"
$EndMarker = "<!-- agentic:end -->"

# External checkouts referenced by the managed config. These are plugin/skill
# repositories that are NOT vendored in this repo, so the deployment ensures a
# checkout exists and points the config at it.
$ExternalCheckouts = @(
    @{
        Name = "understand-anything"
        Dir  = Join-Path $env:USERPROFILE ".understand-anything/repo"
        Url  = "https://github.com/Egonex-AI/Understand-Anything.git"
    }
)

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

$UsingConfig = $false
if (-not $NoConfig) {
    if (Test-Path -LiteralPath $ConfigSnippet) {
        $UsingConfig = $true
    } else {
        Write-Warning "Config snippet not found, skipping managed config merge: $ConfigSnippet"
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

function Merge-ArrayEntry {
    <#
      Union a snippet array into the target array, preserving order. Order is
      significant for `skills` (later entries win) and `plugins`, so entries are
      appended rather than sorted.
    #>
    param($Existing, $Incoming)

    $Result = @()
    foreach ($Item in @($Existing)) { if ($null -ne $Item) { $Result += $Item } }
    foreach ($Item in @($Incoming)) {
        if ($null -ne $Item -and $Result -notcontains $Item) { $Result += $Item }
    }
    # The leading comma is required: PowerShell unrolls a single-element array
    # on return, which would serialise a one-entry list as a bare scalar and make
    # the whole config key invalid. The caller casts back to [object[]] so the
    # list is not nested inside itself.
    return , $Result
}

# ---------------------------------------------------------------------------
# External checkouts
#
# Some skill sources are separate plugin repositories rather than directories in
# this repo. The managed config points at them by path, so make sure a checkout
# actually exists. An existing checkout is never modified; update it yourself so
# a deployment can never move your dependency versions under you.
# ---------------------------------------------------------------------------
foreach ($Checkout in $ExternalCheckouts) {
    if (Test-Path -LiteralPath (Join-Path $Checkout.Dir ".git")) {
        Write-Host "  Checkout: $($Checkout.Name) present at $($Checkout.Dir)" -ForegroundColor Green
    } elseif (Test-Path -LiteralPath $Checkout.Dir) {
        Write-Warning "Checkout: $($Checkout.Dir) exists but is not a git clone; skipping. Remove it and re-run, or clone $($Checkout.Url) manually."
    } else {
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
            Write-Warning "Checkout: git not found, cannot clone $($Checkout.Name). Clone $($Checkout.Url) to $($Checkout.Dir) manually."
            continue
        }
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Checkout.Dir) | Out-Null
        Write-Host "  Checkout: cloning $($Checkout.Name) -> $($Checkout.Dir)" -ForegroundColor Yellow
        & git clone --depth 1 $Checkout.Url $Checkout.Dir
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Checkout: clone of $($Checkout.Name) failed; its skills will not load until this is resolved."
        }
    }
}

# ---------------------------------------------------------------------------
# Managed config (MCP servers, skill sources, plugins)
#
# OpenCode loads exactly one extra config file (OPENCODE_CONFIG), so these must
# be merged into the target's own opencode.json(c). The merge is scoped: only
# keys present in the snippet are touched, and everything else in the target
# config is preserved.
# ---------------------------------------------------------------------------
$ServerCount = 0
$SkillPathCount = 0
$PluginCount = 0
if ($UsingConfig) {
    # -AsHashtable so objects expose .Keys; ConvertFrom-Json without it yields
    # PSCustomObject, whose property names are not enumerable that way.
    $Snippet = ConvertFrom-Json (Get-Content -LiteralPath $ConfigSnippet -Raw) -AsHashtable

    $TargetConfig = $null
    foreach ($Candidate in @("opencode.jsonc", "opencode.json")) {
        $CandidatePath = Join-Path $TargetBase $Candidate
        if (Test-Path -LiteralPath $CandidatePath) { $TargetConfig = $CandidatePath; break }
    }

    if ($null -eq $TargetConfig) {
        $TargetConfig = Join-Path $TargetBase "opencode.jsonc"
        Set-Content -LiteralPath $TargetConfig -Value "{}" -NoNewline
        Write-Host "  Config: Created $TargetConfig" -ForegroundColor Yellow
    }

    $RawText = Get-Content -LiteralPath $TargetConfig -Raw
    $HadComments = $RawText -match '(?m)^\s*//' -or $RawText.Contains('/*')
    $Config = ConvertTo-HashtableDeep (Remove-JsonComments $RawText | ConvertFrom-Json -AsHashtable)
    if ($null -eq $Config) { $Config = @{} }

    # MCP servers, merged by name.
    $SnippetServers = $null
    if ($null -ne $Snippet["mcp"]) { $SnippetServers = $Snippet["mcp"]["servers"] }
    if ($null -ne $SnippetServers) {
        if ($null -eq $Config["mcp"]) { $Config["mcp"] = @{} }
        if ($null -eq $Config["mcp"]["servers"]) { $Config["mcp"]["servers"] = @{} }
        foreach ($Name in $SnippetServers.Keys) {
            $Config["mcp"]["servers"][$Name] = $SnippetServers[$Name]
            Write-Host "  MCP: $Name" -ForegroundColor Green
            $ServerCount++
        }
    }

    # Extra skill sources (directories or HTTP catalogs) and plugins, merged as
    # ordered unions so pre-existing entries keep their precedence.
    #
    # NOTE: the key is `plugin` (singular) on V1-line OpenCode builds. Builds
    # that follow the V2 config guide expect `plugins`, and reject the singular
    # form. Probe your build before assuming either spelling.
    foreach ($Key in @("skills", "plugin")) {
        $Incoming = $Snippet[$Key]
        if ($null -eq $Incoming) { continue }
        $Before = @($Config[$Key])
        # Cast rather than wrap in @(): the function already returns the array as
        # a single object, so @() around it would nest the list inside itself.
        $Merged = [object[]](Merge-ArrayEntry $Before $Incoming)
        $Config[$Key] = $Merged
        $Added = $Merged.Count - $Before.Count
        foreach ($Entry in $Merged) {
            if ($Before -notcontains $Entry) {
                Write-Host "  ${Key}: $Entry" -ForegroundColor Green
            }
        }
        if ($Key -eq "skills") { $SkillPathCount += $Added }
        if ($Key -eq "plugin") { $PluginCount += $Added }
    }

    Copy-Item -LiteralPath $TargetConfig -Destination "$TargetConfig.bak" -Force

    # Recursively sort object keys. PowerShell hashtable enumeration order is
    # not guaranteed, so sorting at every level (arrays keep their order) is
    # what makes the written file byte-stable across runs and reviewable in
    # version control.
    $Json = (ConvertTo-SortedOrdered $Config) | ConvertTo-Json -Depth 20
    Set-Content -LiteralPath $TargetConfig -Value ($Json + "`n") -NoNewline

    if ($HadComments) {
        Write-Warning "Config: $TargetConfig contained comments; they were stripped by the JSONC merge. Original saved at $TargetConfig.bak"
    }
    Write-Host "  Config: Merged into $TargetConfig" -ForegroundColor Green
}

Write-Host ""
Write-Host "Deployed $AgentCount agent(s), $SkillCount skill(s), $PromptCount prompt(s), $ServerCount MCP server(s), and AGENTS.md" -ForegroundColor Green
Write-Host "Agents:  $TargetAgentsDir" -ForegroundColor Yellow
Write-Host "Skills:  $TargetSkillsDir" -ForegroundColor Yellow
if ($UsingPrompts) { Write-Host "Commands: $(Join-Path $TargetBase 'commands')" -ForegroundColor Yellow }
if ($UsingConfig) { Write-Host "Config:  $(Join-Path $TargetBase 'opencode.jsonc')" -ForegroundColor Yellow }
Write-Host "AGENTS.md: $TargetAgentsMd" -ForegroundColor Yellow

if ($EmptySkillDirs.Count -gt 0) {
    Write-Host ""
    Write-Warning "Unpopulated skill directories skipped: $($EmptySkillDirs -join ', ')"
    Write-Warning "A skill directory with no SKILL.md is either an unpopulated git submodule or a"
    Write-Warning "multi-skill plugin repository. Run 'git submodule update --init --recursive',"
    Write-Warning "or point the config's skills array at the repository's skills/ directory."
}