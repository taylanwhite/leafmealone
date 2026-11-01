<#
.SYNOPSIS
  Runs the same checks as .github/workflows/netcode.yml on this Windows machine.

.EXAMPLE
  tools\ci_local.ps1                      # every test, then the bot soaks
  tools\ci_local.ps1 -Only smoke,work     # just these
  tools\ci_local.ps1 -SkipSoak            # feature tests only
  tools\ci_local.ps1 -List                # names of every test

.NOTES
  Godot comes from $env:GODOT, else ~\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe.
  Python (only for the soaks) comes from $env:PYTHON, else the per-user Python 3.12.
  Each run starts from a clean test save, like CI does. Logs and reports go to build\soak\local-<test>.
  Exit code: 0 when everything passed, 1 otherwise.
#>
param(
	[string[]]$Only = @(),
	[switch]$SkipSoak,
	[switch]$SkipImport,
	[switch]$List
)

$ErrorActionPreference = 'Stop'
# "-Only smoke,work" arrives as one string through powershell -File.
$Only = @($Only | ForEach-Object { $_ -split ',' } | Where-Object { $_ -ne '' })
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$Godot = $env:GODOT
if (-not $Godot) { $Godot = Join-Path $env:USERPROFILE 'Tools\Godot\Godot_v4.7.2-stable_win64_console.exe' }
$Python = $env:PYTHON
if (-not $Python) { $Python = Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\python.exe' }
$Bash = 'C:\Program Files\Git\bin\bash.exe'
$TestSave = Join-Path $env:APPDATA 'Godot\app_userdata\Leaf Me Alone\saves\campaign_test.json'

# One entry per CI step. Host and Client are the args after `--`. Check gets the host report,
# the client report (or $null) and returns $true on pass.
$Tests = [ordered]@{
	job = @{
		Host = '--host --name=Tester --no-steam --job-test --job-seed=777 --yard-size=1'; Seconds = 75
		Check = { param($h, $c) [bool]$h.job_test.ok }
	}
	bonk = @{
		Host = '--host --name=Tester --no-steam --start-zone=lot --bonk-test'; Seconds = 26; Client = 22
		Check = { param($h, $c) [bool]$h.bonk_test.ok }
	}
	work = @{
		Host = '--host --name=Tester --no-steam --start-zone=lot --all-tools --all-tasks --job-seed=777 --work-test'; Seconds = 120; Client = 115
		Check = { param($h, $c) [bool]$h.work_test.ok -and (Same $h.lot_layout $c.lot_layout) -and (Same $h.job_progress $c.job_progress) }
	}
	throw = @{
		Host = '--host --name=Tester --no-steam --start-zone=lot --throw-test'; Seconds = 34
		Check = { param($h, $c) [bool]$h.throw_test.ok }
	}
	water = @{
		Host = '--host --name=Tester --no-steam --start-zone=lot --all-tools --all-tasks --job-seed=4242 --water-test'; Seconds = 50
		Check = { param($h, $c) [bool]$h.water_test.ok }
	}
	mower = @{
		Host = '--host --name=Tester --no-steam --start-zone=lot --all-tools --all-tasks --job-seed=777 --mower-test'; Seconds = 55; Client = 50
		Check = { param($h, $c) [bool]$h.mower_test.ok }
	}
	board = @{
		Host = '--host --name=Tester --no-steam --board-test'; Seconds = 30; Client = 25
		Check = { param($h, $c) [bool]$h.board_test.ok -and (Same $h.board $c.board) }
	}
	gag = @{
		Host = '--host --name=Tester --no-steam --start-zone=lot --all-tools --all-tasks --job-seed=777 --yard-size=1 --gag-test'; Seconds = 80; Client = 75
		Check = { param($h, $c) [bool]$h.gag_test.ok -and ([math]::Abs([double]$h.heat - [double]$c.heat) -lt 1.5) }
	}
	brawl = @{
		Host = '--host --name=Tester --no-steam --start-zone=lot --all-tools --job-seed=777 --yard-size=1 --brawl-test'; Seconds = 50; Client = 45
		Check = { param($h, $c) [bool]$h.brawl_test.ok }
	}
	day = @{
		Host = '--host --name=Tester --no-steam --day-test'; Seconds = 30; Client = 26
		Check = { param($h, $c) [bool]$h.day_test.ok -and (Same $h.day $c.day) }
	}
	town = @{
		Host = '--host --name=Tester --no-steam --town-test'; Seconds = 40; Client = 36
		Check = { param($h, $c) [bool]$h.town_test.ok -and (Same $h.town $c.town) }
	}
	layout = @{
		Host = '--host --name=Tester --no-steam --start-zone=lot --layout-test'; Seconds = 120
		Check = { param($h, $c) [bool]$h.layout_test.ok }
	}
	hire = @{
		Host = '--host --name=Tester --no-steam --start-zone=lot --job-seed=777 --yard-size=1 --rank=22 --hire-test'; Seconds = 70; Client = 65
		Check = { param($h, $c) [bool]$h.hire_test.ok -and ([int]$c.crew_hands -eq 1) }
	}
	rival = @{
		Host = '--host --name=Tester --no-steam --rank=17 --rival-test'; Seconds = 20
		Check = { param($h, $c) [bool]$h.rival_test.ok }
	}
}
# New feature tests register here too (see CLAUDE.md, "Adding a test").
$ExtraTests = Join-Path $PSScriptRoot 'ci_tests.ps1'
if (Test-Path $ExtraTests) { . $ExtraTests }

$AllNames = @('smoke') + @($Tests.Keys) + @('soak', 'event-soak')
if ($List) { $AllNames; exit 0 }

function Same($a, $b) {
	($a | ConvertTo-Json -Depth 30 -Compress) -eq ($b | ConvertTo-Json -Depth 30 -Compress)
}

function Wants([string]$name) {
	if ($Only.Count -gt 0) { return $Only -contains $name }
	if ($SkipSoak -and ($name -like '*soak')) { return $false }
	return $true
}

function Clear-TestSave {
	foreach ($path in @($TestSave, "$TestSave.bak", "$TestSave.tmp")) {
		if (Test-Path $path) { Remove-Item $path -Force }
	}
}

function Start-Godot([string]$argLine, [string]$log) {
	# Quote the whole path so spaces survive; stdout and stderr go to separate files.
	$p = Start-Process -FilePath $Godot -ArgumentList $argLine -NoNewWindow -PassThru `
		-RedirectStandardOutput $log -RedirectStandardError "$log.err"
	# Touch the handle now, or PowerShell 5.1 loses the exit code once the process ends.
	$null = $p.Handle
	$p
}

if (-not (Test-Path $Godot)) { throw "Godot not found at $Godot. Set `$env:GODOT." }

if (-not $SkipImport) {
	Write-Host '== import' -ForegroundColor Cyan
	$p = Start-Godot '--headless --path . --import' (Join-Path $env:TEMP 'lma-import.log')
	$p.WaitForExit()
}

$Results = [ordered]@{}
$Port = 7791

if (Wants 'smoke') {
	Write-Host '== smoke' -ForegroundColor Cyan
	Clear-TestSave
	$dir = Join-Path $Root 'build\soak\local-smoke'
	New-Item -ItemType Directory -Force $dir | Out-Null
	$p = Start-Godot "--headless --path . -- --smoke-test --port=$Port" (Join-Path $dir 'host.log')
	$p.WaitForExit()
	$Results['smoke'] = ($p.ExitCode -eq 0)
}

$Port = 7794
foreach ($name in $Tests.Keys) {
	$t = $Tests[$name]
	$port = $Port
	$Port++
	if (-not (Wants $name)) { continue }
	Write-Host "== $name" -ForegroundColor Cyan
	Clear-TestSave
	$dir = Join-Path $Root "build\soak\local-$name"
	if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }
	New-Item -ItemType Directory -Force $dir | Out-Null
	$hostJson = Join-Path $dir 'host.json'
	$clientJson = Join-Path $dir 'target.json'
	$hp = Start-Godot "--headless --path . -- $($t.Host) --port=$port --measure=`"$hostJson`" --run-seconds=$($t.Seconds)" (Join-Path $dir 'host.log')
	$cp = $null
	if ($t.Client) {
		Start-Sleep -Seconds 3
		$cp = Start-Godot "--headless --path . -- --join=127.0.0.1 --port=$port --name=Target --no-steam --measure=`"$clientJson`" --run-seconds=$($t.Client)" (Join-Path $dir 'target.log')
	}
	$hp.WaitForExit()
	if ($cp) { $cp.WaitForExit() }
	$ok = $false
	try {
		$h = Get-Content $hostJson -Raw | ConvertFrom-Json
		$c = $null
		if (Test-Path $clientJson) { $c = Get-Content $clientJson -Raw | ConvertFrom-Json }
		$ok = [bool](& $t.Check $h $c)
		$key = "$($name)_test"
		if (-not $ok -and $h.$key.error) { Write-Host "   error: $($h.$key.error)" -ForegroundColor Yellow }
	} catch {
		Write-Host "   no report: $($_.Exception.Message)" -ForegroundColor Yellow
	}
	$errors = Select-String -Path (Join-Path $dir '*.log*') -Pattern 'SCRIPT ERROR|^ERROR' -ErrorAction SilentlyContinue | Select-Object -First 5
	foreach ($e in $errors) { Write-Host "   $($e.Line)" -ForegroundColor DarkYellow }
	$Results[$name] = $ok
}

function Invoke-Soak([string]$name, [string]$soakArgs) {
	Write-Host "== $name" -ForegroundColor Cyan
	Clear-TestSave
	$env:GODOT = ($Godot -replace '\\', '/')
	$env:PYTHON = ($Python -replace '\\', '/')
	$out = (Join-Path $Root "build\soak\local-$name") -replace '\\', '/'
	# Out-Host, so the soak's own output shows instead of becoming this function's return value.
	& $Bash tools/soak.sh $soakArgs.Split(' ') -o $out | Out-Host
	$code = $LASTEXITCODE
	if ($code -eq 2) { Write-Host '   inconclusive (machine too busy); counted as a pass, like CI' -ForegroundColor Yellow; return $true }
	return ($code -eq 0)
}

if (Wants 'soak') { $Results['soak'] = Invoke-Soak 'soak' '-n 4 -s 45 -P 7792' }
if (Wants 'event-soak') { $Results['event-soak'] = Invoke-Soak 'event-soak' '-n 4 -s 170 -e 65 -P 7793' }

Write-Host ''
$failed = 0
foreach ($k in $Results.Keys) {
	if ($Results[$k]) { Write-Host ("PASS  {0}" -f $k) -ForegroundColor Green }
	else { Write-Host ("FAIL  {0}" -f $k) -ForegroundColor Red; $failed++ }
}
if ($failed -gt 0) { exit 1 }
exit 0
