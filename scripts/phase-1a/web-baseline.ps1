param(
    [ValidateSet('Default', 'Webpack')]
    [string]$Bundler = 'Default',
    [switch]$Checks,
    [ValidatePattern('^[a-zA-Z0-9-]+$')]
    [string]$RunLabel = 'baseline'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$source = Join-Path $repoRoot 'ledgermindv1-main'
$dependencies = Join-Path $source 'node_modules'
$npm = (Get-Command npm.cmd -ErrorAction Stop).Source
if (-not (Test-Path (Join-Path $dependencies 'next/package.json'))) {
    throw 'Existing dashboard dependencies are required; this helper never installs dependencies.'
}

$evidence = Join-Path $repoRoot 'docs/phase-1a/evidence'
New-Item -ItemType Directory -Path $evidence -Force | Out-Null
$runId = 'web-{0}-{1}' -f $RunLabel, (Get-Date -Format 'yyyyMMdd-HHmmss')
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('ledmi-phase1a-web-' + [guid]::NewGuid().ToString('N'))
$app = Join-Path $tempRoot 'app'
$junction = Join-Path $app 'node_modules'
$originalEnvironment = @{}
Get-ChildItem Env: | ForEach-Object { $originalEnvironment[$_.Name] = $_.Value }
$results = [ordered]@{
    run = $runId
    startedUtc = [DateTime]::UtcNow.ToString('o')
    source = $source
    bundler = $Bundler
    nextVersion = (Get-Content (Join-Path $dependencies 'next/package.json') -Raw | ConvertFrom-Json).version
    environmentFilesCopied = $null
    checks = @()
}
$exitCode = 1

function Invoke-WebCheck([string]$Name, [string[]]$NpmArguments) {
    $log = Join-Path $evidence ($runId + '-' + $Name + '.log')
    ('Command: npm ' + ($NpmArguments -join ' ')) | Set-Content -LiteralPath $log -Encoding UTF8
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $npm @NpmArguments 2>&1 | ForEach-Object {
            $line = $_.ToString()
            $line | Add-Content -LiteralPath $log -Encoding UTF8
            Write-Host $line
        }
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    ('Exit code: ' + $code) | Add-Content -LiteralPath $log -Encoding UTF8
    $results.checks += [ordered]@{ name = $Name; command = 'npm ' + ($NpmArguments -join ' '); exitCode = $code; log = [System.IO.Path]::GetFileName($log) }
    return $code
}

try {
    New-Item -ItemType Directory -Path $app | Out-Null
    & robocopy $source $app /E /XJ /XD node_modules .next .git out build /XF '.env*' '*.tsbuildinfo' .npmrc /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "Source copy failed (robocopy exit $LASTEXITCODE)." }
    $envFiles = @(Get-ChildItem -LiteralPath $app -Force -Recurse -File | Where-Object { $_.Name -like '.env*' })
    $results.environmentFilesCopied = $envFiles.Count
    if ($envFiles.Count -ne 0) { throw 'An environment file was found in the isolated source copy.' }
    New-Item -ItemType Junction -Path $junction -Target $dependencies | Out-Null

    # Child commands inherit only OS/tool locations and explicitly fictional build values.
    $allowed = '^(Path|SystemRoot|windir|TEMP|TMP|PATHEXT|ComSpec|APPDATA|LOCALAPPDATA|USERPROFILE|PROGRAMDATA|ProgramFiles|ProgramFiles\(x86\)|CommonProgramFiles|CommonProgramFiles\(x86\)|NUMBER_OF_PROCESSORS|PROCESSOR_ARCHITECTURE|OS|SystemDrive)$'
    Get-ChildItem Env: | Where-Object { $_.Name -notmatch $allowed } | ForEach-Object { Remove-Item -LiteralPath ('Env:' + $_.Name) }
    $env:NEXT_PUBLIC_SUPABASE_URL = 'http://127.0.0.1:1'
    $env:NEXT_PUBLIC_SUPABASE_ANON_KEY = 'phase-1a-fictional-anon-key'
    $env:NVIDIA_API_URL = 'http://127.0.0.1:1/disabled-provider'
    $env:NEXT_TELEMETRY_DISABLED = '1'
    $env:CI = '1'
    $env:NODE_ENV = 'production'
    $env:NPM_CONFIG_UPDATE_NOTIFIER = 'false'
    $env:NPM_CONFIG_USERCONFIG = Join-Path $tempRoot 'user.npmrc'
    $env:NPM_CONFIG_GLOBALCONFIG = Join-Path $tempRoot 'global.npmrc'
    $env:NPM_CONFIG_CACHE = Join-Path $tempRoot 'npm-cache'
    New-Item -ItemType File -Path $env:NPM_CONFIG_USERCONFIG, $env:NPM_CONFIG_GLOBALCONFIG | Out-Null

    Push-Location $app
    try {
        if ($Checks) { $null = Invoke-WebCheck 'lint' @('run', 'lint') }
        $buildArguments = @('run', 'build')
        if ($Bundler -eq 'Webpack') { $buildArguments += @('--', '--webpack') }
        $null = Invoke-WebCheck 'build' $buildArguments
        if ($Checks) { $null = Invoke-WebCheck 'typecheck' @('run', 'typecheck') }
    } finally {
        Pop-Location
    }
    $exitCode = if (@($results.checks | Where-Object { $_.exitCode -ne 0 }).Count -eq 0) { 0 } else { 1 }
} catch {
    $results.error = $_.Exception.Message
    Write-Warning $_.Exception.Message
} finally {
    Get-ChildItem Env: | ForEach-Object { Remove-Item -LiteralPath ('Env:' + $_.Name) }
    foreach ($key in $originalEnvironment.Keys) { Set-Item -LiteralPath ('Env:' + $key) -Value $originalEnvironment[$key] }
    # Remove the dependency junction without traversing it before deleting this run's temp tree.
    if (Test-Path -LiteralPath $junction) { (Get-Item -LiteralPath $junction).Delete() }
    $resolvedTemp = [System.IO.Path]::GetFullPath($tempRoot)
    $expectedParent = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\')
    if ([System.IO.Path]::GetDirectoryName($resolvedTemp) -ne $expectedParent -or [System.IO.Path]::GetFileName($resolvedTemp) -notlike 'ledmi-phase1a-web-*') {
        throw 'Refusing cleanup outside the expected temporary run directory.'
    }
    if (Test-Path -LiteralPath $resolvedTemp) { Remove-Item -LiteralPath $resolvedTemp -Recurse -Force }
    $results.finishedUtc = [DateTime]::UtcNow.ToString('o')
    $results.exitCode = $exitCode
    $resultPath = Join-Path $evidence ($runId + '-result.json')
    $results | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    Write-Host "Result: $resultPath"
}
exit $exitCode
