# deploy.ps1 — Deploy all agents and skills to Opencode
#
# Usage:
#   .\deploy.ps1              # Deploy to global location (~/.config/opencode/)
#   .\deploy.ps1 -Project .   # Deploy to current project (.opencode/)

param(
    [string]$Project
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$AgentsDir = Join-Path $ScriptDir "agents"
$SkillsDir = Join-Path $ScriptDir "skills"
$AgentsMd = Join-Path $ScriptDir "AGENTS.md"

# Validate source directories exist
if (-not (Test-Path -LiteralPath $AgentsDir)) {
    Write-Error "Agents directory not found: $AgentsDir"
    exit 1
}

if (-not (Test-Path -LiteralPath $SkillsDir)) {
    Write-Error "Skills directory not found: $SkillsDir"
    exit 1
}

if (-not (Test-Path -LiteralPath $AgentsMd)) {
    Write-Error "AGENTS.md not found: $AgentsMd"
    exit 1
}

# Determine target directories
if ($Project) {
    $TargetBase = Join-Path $Project ".opencode"
    Write-Host "Deploying to project: $TargetBase" -ForegroundColor Cyan
} else {
    $TargetBase = Join-Path $env:USERPROFILE ".config" | Join-Path -ChildPath "opencode"
    Write-Host "Deploying to global: $TargetBase" -ForegroundColor Cyan
}

$TargetAgentsDir = Join-Path $TargetBase "agents"
$TargetSkillsDir = Join-Path $TargetBase "skills"

# Create target directories
New-Item -ItemType Directory -Force -Path $TargetAgentsDir | Out-Null
New-Item -ItemType Directory -Force -Path $TargetSkillsDir | Out-Null

# Copy all agent files
$AgentFiles = Get-ChildItem -Path $AgentsDir -Filter "*.md" -File

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

# Copy all skill directories
$SkillDirs = Get-ChildItem -Path $SkillsDir -Directory

if ($SkillDirs.Count -eq 0) {
    Write-Warning "No skill directories found in $SkillsDir"
}

$SkillCount = 0
foreach ($Dir in $SkillDirs) {
    # Validate skill has SKILL.md
    $SkillMd = Join-Path $Dir.FullName "SKILL.md"
    if (-not (Test-Path -LiteralPath $SkillMd)) {
        Write-Warning "Skipping $($Dir.Name): SKILL.md not found"
        continue
    }

    $TargetSkillDir = Join-Path $TargetSkillsDir $Dir.Name
    New-Item -ItemType Directory -Force -Path $TargetSkillDir | Out-Null

    # Copy SKILL.md
    Copy-Item -Path $SkillMd -Destination (Join-Path $TargetSkillDir "SKILL.md") -Force
    Write-Host "  Skill: $($Dir.Name)" -ForegroundColor Green

    # Copy any additional files (scripts/, references/, etc.)
    $AdditionalFiles = Get-ChildItem -Path $Dir.FullName -File -Recurse | Where-Object { $_.Name -ne "SKILL.md" }
    foreach ($File in $AdditionalFiles) {
        $RelativePath = $File.FullName.Substring($Dir.FullName.Length + 1)
        $TargetFilePath = Join-Path $TargetSkillDir $RelativePath
        $TargetFileDir = Split-Path -Parent $TargetFilePath
        New-Item -ItemType Directory -Force -Path $TargetFileDir | Out-Null
        Copy-Item -Path $File.FullName -Destination $TargetFilePath -Force
    }

    $SkillCount++
}

# Deploy AGENTS.md (append if exists, copy if not)
$TargetAgentsMd = Join-Path $TargetBase "AGENTS.md"
if (Test-Path -LiteralPath $TargetAgentsMd) {
    # Backup existing file
    $BackupPath = "$TargetAgentsMd.bak"
    Copy-Item -Path $TargetAgentsMd -Destination $BackupPath -Force
    Write-Host "  AGENTS.md: Backed up existing file to AGENTS.md.bak" -ForegroundColor Yellow
    
    # Append new content
    Add-Content -Path $TargetAgentsMd -Value "`n`n<!-- Appended from agentic project -->`n"
    Get-Content -Path $AgentsMd | Add-Content -Path $TargetAgentsMd
    Write-Host "  AGENTS.md: Appended project content" -ForegroundColor Green
} else {
    # Copy new file
    Copy-Item -Path $AgentsMd -Destination $TargetAgentsMd -Force
    Write-Host "  AGENTS.md: Copied new file" -ForegroundColor Green
}

Write-Host "`nDeployed $AgentCount agent(s), $SkillCount skill(s), and AGENTS.md" -ForegroundColor Green
Write-Host "Agents: $TargetAgentsDir" -ForegroundColor Yellow
Write-Host "Skills: $TargetSkillsDir" -ForegroundColor Yellow
Write-Host "AGENTS.md: $TargetAgentsMd" -ForegroundColor Yellow
