<#
.SYNOPSIS
  Runs the same checks as .github/workflows/netcode.yml on this Windows machine.

.EXAMPLE
  tools\ci_local.ps1                      # every test, then the bot soaks
  tools\ci_local.ps1 -Only smoke,work     # just these
  tools\ci_local.ps1 -SkipSoak            # feature tests only
  tools\ci_local.ps1 -List                # names of every test
  tools\ci_local.ps1 -Jobs 1              # one test at a time, like before

.NOTES
  Godot comes from $env:GODOT, else ~\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe.
  Python (only for the soaks) comes from $env:PYTHON, else the per-user Python 3.12.
  Feature tests run side by side (-Jobs at a time), each on its own port with its own
  test save (campaign_test_<port>.json), and each quits as soon as its test is done
  (net/dev/dev_tools.gd). The two bot soaks run together afterwards, on a quiet machine,
  because they judge smoothness. Logs and reports go to build\soak\local-<test>.
  Exit code: 0 when everything passed, 1 otherwise.
#>
param(
	[string[]]$Only = @(),
	[switch]$SkipSoak,
	[switch]$SkipImport,
	[switch]$List,
	[int]$Jobs = 0,
	# Shifts every port (and so every test save) by this much, so runs in two worktrees
	# at once don't collide. Use a multiple of 100.
	[int]$PortOffset = 0
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
$SaveDir = Join-Path $env:APPDATA 'Godot\app_userdata\Leaf Me Alone\saves'
if ($Jobs -le 0) {
	# Each test is one or two Godot processes; leave room so physics keeps its frame rate.
	$cores = [int](Get-CimInstance Win32_Processor | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
	$Jobs = [math]::Max(1, [math]::Min(8, [math]::Floor($cores / 4)))
}

# One entry per CI step. Host and Client are the args after `--`. Seconds and Client are
# ceilings for a hung test; a test that finishes quits right away. Check gets the host report,
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
	# Host only until cast:4 turns on the networked phase; then it gets Client = 40 and
	# compares $h.crew_cast with $c.crew_cast.
	cast = @{
		Host = '--host --name=Tester --no-steam --start-zone=lot --job-seed=777 --yard-size=1 --cast-test'; Seconds = 45; Port = 7812
		Check = { param($h, $c) [bool]$h.cast_test.ok }
	}
}
# New feature tests register here too (see CLAUDE.md, "Adding a test").
$ExtraTests = Join-Path $PSScriptRoot 'ci_tests.ps1'
if (Test-Path $ExtraTests) { . $ExtraTests }

$AllNames = @('smoke') + @($Tests.Keys) + @('soak', 'event-soak')
if ($List) { $AllNames; exit 0 }
# A typo in -Only would otherwise run nothing and report a pass.
$unknown = @($Only | Where-Object { $AllNames -notcontains $_ })
if ($unknown.Count -gt 0) {
	Write-Host "Unknown test name(s): $($unknown -join ', '). Use -List to see them." -ForegroundColor Red
	exit 1
}

function Same($a, $b) {
	($a | ConvertTo-Json -Depth 30 -Compress) -eq ($b | ConvertTo-Json -Depth 30 -Compress)
}

function Wants([string]$name) {
	if ($Only.Count -gt 0) { return $Only -contains $name }
	if ($SkipSoak -and ($name -like '*soak')) { return $false }
	return $true
}

## Removes the test save for one port, or every test save when no port is given.
function Clear-TestSave([int]$port = 0) {
	if (-not (Test-Path $SaveDir)) { return }
	$pattern = if ($port -gt 0) { "campaign_test_$port.json*" } else { 'campaign_test*.json*' }
	Get-ChildItem -Path $SaveDir -Filter $pattern -ErrorAction SilentlyContinue | Remove-Item -Force
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
	$p = Start-Godot '--headless --path . --import' (Join-Path $env:TEMP "lma-import-$PortOffset.log")
	$p.WaitForExit()
}

$Results = [ordered]@{}
$Times = @{}
$Clock = [Diagnostics.Stopwatch]::StartNew()
# Each test clears its own port's save when it starts; nothing clears every save, since
# another worktree's run (-PortOffset) may be using its own.

# The queue: smoke first, then every feature test on its own port (7794 up, matching CI).
$Queue = New-Object System.Collections.Generic.List[object]
if (Wants 'smoke') { $Queue.Add(@{ Name = 'smoke'; Port = 7791 + $PortOffset }) }
$Port = 7794 + $PortOffset
foreach ($name in $Tests.Keys) {
	if (Wants $name) { $Queue.Add(@{ Name = $name; Port = $Port }) }
	$Port++
}

function Start-Test($item) {
	$name = $item.Name
	$port = $item.Port
	Clear-TestSave $port
	$dir = Join-Path $Root "build\soak\local-$name"
	if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }
	New-Item -ItemType Directory -Force $dir | Out-Null
	$item.Dir = $dir
	$item.Started = $Clock.Elapsed.TotalSeconds
	if ($name -eq 'smoke') {
		$item.HostProc = Start-Godot "--headless --path . -- --smoke-test --port=$port" (Join-Path $dir 'host.log')
		return
	}
	$t = $Tests[$name]
	$item.HostJson = Join-Path $dir 'host.json'
	$item.ClientJson = Join-Path $dir 'target.json'
	$item.HostProc = Start-Godot "--headless --path . -- $($t.Host) --port=$port --measure=`"$($item.HostJson)`" --run-seconds=$($t.Seconds)" (Join-Path $dir 'host.log')
	# The client joins 3 s later, like CI; Step-Tests starts it.
	if ($t.Client) { $item.ClientAt = $item.Started + 3 }
}

## Starts any client that is due. Returns $true once the test's processes have all exited.
function Step-Test($item) {
	# A host that already died has nothing to join; don't wait out a client's ceiling for it.
	if ($item.ClientAt -and -not $item.ClientProc -and $item.HostProc.HasExited) { $item.ClientAt = $null }
	if ($item.ClientAt -and -not $item.ClientProc -and $Clock.Elapsed.TotalSeconds -ge $item.ClientAt) {
		$t = $Tests[$item.Name]
		$item.ClientProc = Start-Godot "--headless --path . -- --join=127.0.0.1 --port=$($item.Port) --name=Target --no-steam --measure=`"$($item.ClientJson)`" --run-seconds=$($t.Client)" (Join-Path $item.Dir 'target.log')
	}
	if (-not $item.HostProc.HasExited) { return $false }
	if ($item.ClientAt -and -not $item.ClientProc) { return $false }
	if ($item.ClientProc -and -not $item.ClientProc.HasExited) { return $false }
	return $true
}

function Complete-Test($item) {
	$name = $item.Name
	$seconds = [math]::Round($Clock.Elapsed.TotalSeconds - $item.Started)
	$Times[$name] = $seconds
	$ok = $false
	$notes = @()
	if ($name -eq 'smoke') {
		$ok = ($item.HostProc.ExitCode -eq 0)
	} else {
		$t = $Tests[$name]
		try {
			$h = Get-Content $item.HostJson -Raw | ConvertFrom-Json
			$c = $null
			if (Test-Path $item.ClientJson) { $c = Get-Content $item.ClientJson -Raw | ConvertFrom-Json }
			$ok = [bool](& $t.Check $h $c)
			$key = "$($name)_test"
			if (-not $ok -and $h.$key.error) { $notes += "error: $($h.$key.error)" }
			if (-not $h.$key.done) { $notes += 'the test never finished; it ran out its time limit' }
		} catch {
			$notes += "no report: $($_.Exception.Message)"
		}
	}
	$color = if ($ok) { 'Green' } else { 'Red' }
	Write-Host ("{0,-5} {1,-11} {2,4} s" -f $(if ($ok) { 'pass' } else { 'FAIL' }), $name, $seconds) -ForegroundColor $color
	foreach ($n in $notes) { Write-Host "      $n" -ForegroundColor Yellow }
	# "resources still in use at exit" is Godot's teardown noise, seen with or without early finish.
	$errors = Select-String -Path (Join-Path $item.Dir '*.log*') -Pattern 'SCRIPT ERROR|^ERROR' -ErrorAction SilentlyContinue |
		Where-Object { $_.Line -notmatch 'resources still in use at exit' } | Select-Object -First 5
	foreach ($e in $errors) { Write-Host "      $($e.Line)" -ForegroundColor DarkYellow }
	$Results[$name] = $ok
}

if ($Queue.Count -gt 0) {
	Write-Host "== $($Queue.Count) tests, $Jobs at a time" -ForegroundColor Cyan
}
$Running = New-Object System.Collections.Generic.List[object]
$next = 0
try {
	while ($next -lt $Queue.Count -or $Running.Count -gt 0) {
		while ($next -lt $Queue.Count -and $Running.Count -lt $Jobs) {
			Start-Test $Queue[$next]
			$Running.Add($Queue[$next])
			$next++
		}
		foreach ($item in $Running.ToArray()) {
			if (Step-Test $item) {
				Complete-Test $item
				[void]$Running.Remove($item)
			}
		}
		Start-Sleep -Milliseconds 250
	}
} finally {
	# Stopped early (Ctrl+C or an error): don't leave games running.
	foreach ($item in $Running.ToArray()) {
		foreach ($p in @($item.HostProc, $item.ClientProc)) {
			if ($p -and -not $p.HasExited) { try { $p.Kill() } catch {} }
		}
	}
}

## Starts one bot soak in the background; its output goes to build\soak\local-<name>.out.
function Start-Soak([string]$name, [string]$soakArgs) {
	# A fresh folder: soak_report.py reads every report in it, so an old one could stand in for a crashed peer.
	$dir = Join-Path $Root "build\soak\local-$name"
	if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }
	New-Item -ItemType Directory -Force $dir | Out-Null
	$out = $dir -replace '\\', '/'
	$argLine = "tools/soak.sh $soakArgs -o `"$out`""
	$log = Join-Path $Root "build\soak\local-$name.out"
	$p = Start-Process -FilePath $Bash -ArgumentList $argLine -NoNewWindow -PassThru `
		-RedirectStandardOutput $log -RedirectStandardError "$log.err"
	$null = $p.Handle
	@{ Name = $name; Proc = $p; Log = $log; Started = $Clock.Elapsed.TotalSeconds }
}

$Soaks = @()
$env:GODOT = ($Godot -replace '\\', '/')
$env:PYTHON = ($Python -replace '\\', '/')
if (Wants 'soak') { Clear-TestSave (7792 + $PortOffset); $Soaks += Start-Soak 'soak' "-n 4 -s 45 -P $(7792 + $PortOffset)" }
if (Wants 'event-soak') { Clear-TestSave (7793 + $PortOffset); $Soaks += Start-Soak 'event-soak' "-n 4 -s 170 -e 65 -P $(7793 + $PortOffset)" }
if ($Soaks.Count -gt 1) { Write-Host "== $($Soaks.Count) bot soaks, together" -ForegroundColor Cyan }
elseif ($Soaks.Count -eq 1) { Write-Host '== bot soak' -ForegroundColor Cyan }
foreach ($s in $Soaks) {
	$s.Proc.WaitForExit()
	$code = $s.Proc.ExitCode
	$seconds = [math]::Round($Clock.Elapsed.TotalSeconds - $s.Started)
	$Times[$s.Name] = $seconds
	$ok = ($code -eq 0 -or $code -eq 2)
	$color = if ($ok) { 'Green' } else { 'Red' }
	Write-Host ("{0,-5} {1,-11} {2,4} s" -f $(if ($ok) { 'pass' } else { 'FAIL' }), $s.Name, $seconds) -ForegroundColor $color
	if ($code -eq 2) { Write-Host '      inconclusive (machine too busy); counted as a pass, like CI' -ForegroundColor Yellow }
	if (-not $ok) {
		foreach ($f in @($s.Log, "$($s.Log).err")) {
			if (Test-Path $f) { Get-Content $f -Tail 15 | ForEach-Object { Write-Host "      $_" } }
		}
	}
	$Results[$s.Name] = $ok
}

Write-Host ''
$failed = 0
foreach ($k in $Results.Keys) {
	if ($Results[$k]) { Write-Host ("PASS  {0}" -f $k) -ForegroundColor Green }
	else { Write-Host ("FAIL  {0}" -f $k) -ForegroundColor Red; $failed++ }
}
Write-Host ("{0} tests in {1:N0} s" -f $Results.Count, $Clock.Elapsed.TotalSeconds)
if ($failed -gt 0) { exit 1 }
exit 0
