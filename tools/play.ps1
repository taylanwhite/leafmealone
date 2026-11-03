<#
.SYNOPSIS
  Play the game by hand, one move at a time (net/dev/remote_play.gd), and record
  moments to judge them in motion (docs/PLAYTEST.md).

.EXAMPLE
  tools\play.ps1 -Start                            # a windowed host with remote play on
  tools\play.ps1 -Start -Scenario rake_pile        # ... that jumps straight to a moment
  tools\play.ps1 -Start -Observer                  # ... plus a second window watching it
  tools\play.ps1 '[["hold","move_forward",1.5]]'
  tools\play.ps1 'look 200 0; tap interact'
  tools\play.ps1 'scenario caught; record 4 30 caught'      # jump, then record 4 s at 30 fps
  tools\play.ps1 -Instance observer 'follow host 5 2 160'   # the observer's camera
  tools\play.ps1 -Instance observer 'record 4 30 caught_3p'
  tools\play.ps1 -Stop                             # closes the windows this worktree started
  tools\play.ps1 -Start -Friend -Observer -Scenario cite_rescue   # + a friend who plays
  tools\play.ps1 -Instance friend 'record_start 30 cited_2p'       # the friend's own view
  tools\play.ps1 -Script build\annex_visit.txt     # a whole sequence, no round trips

.NOTES
  Each call sends one command to one instance (-Instance main, the default, or
  observer) and waits for the game to answer; it prints the result (what's on
  screen, where you are, any recordings) and the screenshot's path. A recording's
  audio.wav is drawn into audio.png (tools/playtest_audio.py) before it returns.

  -Start runs the game with a fixed step (the engine's --fixed-fps and the game's
  --fixed-step, -Fps 30 by default; 0 turns it off): every frame is exactly 1/Fps s
  of game time, held to real time, so recordings are evenly spaced even while other
  agents load the machine. Each worktree gets its own port (-Port) and its own folders
  (build\play, build\play-observer, build\play-friend), and -Stop only closes the windows
  it started. A new -Start moves the last session's shot_*.png into shots-<time>\.

  -Script <file> runs a whole sequence in the game with no round trips, so the time
  spent thinking between calls never eats game time (pace can be measured): one step
  per line (or several joined with ;), # comments, blank lines ignored; a line that
  starts with "observer:" or "friend:" (any instance name and a colon) goes to that
  instance instead. Every instance's steps are sent at once and run side by side;
  this waits for all of them. Use the in-game until / mark / goto / face steps
  (net/dev/remote_play.gd) to react without coming back here.
#>
param(
	[string]$Steps = '[]',
	[switch]$Start,
	[switch]$Stop,
	# With -Start: also launch a second window that joins as a client, parks at the store and
	# follows the host (net/dev/remote_play.gd --observer). Address it with -Instance observer.
	[switch]$Observer,
	# With -Start: also launch a client that plays ("Friend"): a second player on the host's
	# yard for cite_rescue, van_unbuckle and annex_visit. Address it with -Instance friend.
	[switch]$Friend,
	# A file of steps to run in the game in one go (see .NOTES).
	[string]$Script = '',
	[string]$Instance = 'main',
	# With -Start: jump to this moment once the world is up (net/dev/scenarios.gd). Adds the
	# flags the moment needs (a job yard, or the connected town for drive) unless -Extra has them.
	[string]$Scenario = '',
	[string]$Extra = '',
	[int]$TimeoutSeconds = 180,
	[int]$Fps = 30,
	[int]$Port = 0,
	[string]$Resolution = '1280x720',
	# With -Start: mute the game's output (recordings still capture the mix).
	[switch]$Mute
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Godot = Join-Path $env:USERPROFILE 'Tools\Godot\Godot_v4.7.2-stable_win64.exe'
$Python = $env:PYTHON
if (-not $Python) { $Python = Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\python.exe' }
$MainDir = Join-Path $Root 'build\play'
$SessionFile = Join-Path $MainDir 'session.json'

function Get-InstanceDir([string]$name) {
	if ($name -eq 'main') { return $MainDir }
	return Join-Path $Root "build\play-$name"
}

# A port of this worktree's own (9100-9499), so two worktrees' sessions never meet.
if ($Port -le 0) {
	$h = 0
	foreach ($ch in $Root.ToLower().ToCharArray()) { $h = ($h * 31 + [int]$ch) % 100003 }
	$Port = 9100 + ($h % 400)
}

function Read-Session {
	if (Test-Path $SessionFile) {
		try { return Get-Content $SessionFile -Raw | ConvertFrom-Json } catch {}
	}
	return $null
}

function Save-Session($pids, [int]$port, [int]$fps) {
	$obj = [ordered]@{ port = $port; fps = $fps; pids = $pids }
	New-Item -ItemType Directory -Force $MainDir | Out-Null
	[IO.File]::WriteAllText($SessionFile, ($obj | ConvertTo-Json -Depth 4))
}

function Stop-Instance([string]$name) {
	$s = Read-Session
	if ($null -eq $s -or $null -eq $s.pids) { return }
	$procId = $s.pids.$name
	if (-not $procId) { return }
	$p = Get-Process -Id $procId -ErrorAction SilentlyContinue
	if ($p -and $p.Path -eq $Godot) { try { $p.Kill(); $p.WaitForExit(5000) | Out-Null } catch {} }
}

if ($Stop) {
	$s = Read-Session
	$names = @('main', 'observer', 'friend')
	if ($PSBoundParameters.ContainsKey('Instance')) { $names = @($Instance) }
	elseif ($s -and $s.pids) { $names = @($s.pids.PSObject.Properties.Name) }
	foreach ($n in $names) { Stop-Instance $n }
	"stopped $($names -join ', ')"
	exit 0
}

## Plain steps, no quoting: "tap phone; wait 0.4; hold move_forward 1.5; look 200 0; click 640 360".
## Text for a "text" step is the rest of the step: "text Hello there".
function Convert-Steps([string]$text) {
	if ($text.TrimStart().StartsWith('[')) { return $text }
	$parts = @()
	foreach ($chunk in ($text -split ';')) {
		$words = @($chunk.Trim() -split '\s+' | Where-Object { $_ -ne '' })
		if ($words.Count -eq 0) { continue }
		$verb = $words[0]
		if ($verb -eq 'text') {
			$parts += , @($verb, ($chunk.Trim().Substring(4).Trim()))
			continue
		}
		$item = @($verb)
		if ($words.Count -ge 2) {
			foreach ($w in $words[1..($words.Count - 1)]) {
				$n = 0.0
				if ([double]::TryParse($w, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$n)) { $item += $n } else { $item += $w }
			}
		}
		$parts += , $item
	}
	$json = ConvertTo-Json -InputObject $parts -Compress -Depth 4
	if (-not $json.StartsWith('[[')) { $json = '[' + $json + ']' }
	return $json
}

## Sends one command to an instance and returns its result object (or $null on a timeout).
function Send-Command([string]$name, [string]$stepsJson) {
	$dir = Get-InstanceDir $name
	if (-not (Test-Path $dir)) {
		$switch = ''
		if ($name -eq 'observer') { $switch = ' -Observer' } elseif ($name -eq 'friend') { $switch = ' -Friend' }
		throw "no $name instance (start one with tools\play.ps1 -Start$switch)"
	}
	$cmdPath = Join-Path $dir 'cmd.json'
	$resultPath = Join-Path $dir 'result.json'
	$last = 0
	if (Test-Path $cmdPath) {
		$m = [regex]::Match((Get-Content $cmdPath -Raw), '"id":\s*(\d+)')
		if ($m.Success) { $last = [int]$m.Groups[1].Value }
	}
	$id = $last + 1
	[IO.File]::WriteAllText($cmdPath, '{"id": ' + $id + ', "steps": ' + $stepsJson + '}')
	$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
	while ((Get-Date) -lt $deadline) {
		Start-Sleep -Milliseconds 150
		if (Test-Path $resultPath) {
			try { $r = Get-Content $resultPath -Raw | ConvertFrom-Json } catch { continue }
			if ([int]$r.id -eq $id) { return $r }
		}
	}
	Write-Host "timed out waiting for $name (id $id); its log: $(Join-Path $dir 'godot.log')"
	return $null
}

## Draws each finished recording's audio and events into audio.png (tools/playtest_audio.py).
function Complete-Recordings($result) {
	if ($null -eq $result -or $null -eq $result.recordings) { return }
	foreach ($rec in @($result.recordings)) {
		if (-not (Test-Path $Python)) { $rec | Add-Member -NotePropertyName audio_png_error -NotePropertyValue "no Python at $Python" -Force; continue }
		$out = & $Python (Join-Path $PSScriptRoot 'playtest_audio.py') $rec.dir 2>&1
		$png = Join-Path $rec.dir 'audio.png'
		if (Test-Path $png) { $rec | Add-Member -NotePropertyName audio_png -NotePropertyValue $png -Force }
		$sync = Join-Path $rec.dir 'sync.json'
		if (Test-Path $sync) { $rec | Add-Member -NotePropertyName sync_json -NotePropertyValue $sync -Force }
		if ($LASTEXITCODE -ne 0) { $rec | Add-Member -NotePropertyName audio_png_error -NotePropertyValue (($out | Out-String).Trim()) -Force }
	}
}

function Start-Instance([string]$name, [string[]]$gameArgs, [string]$position) {
	Stop-Instance $name
	$dir = Get-InstanceDir $name
	New-Item -ItemType Directory -Force $dir | Out-Null
	# The last session's screenshots move to shots-<time>\ (a new session numbers its
	# own from 1 again); old mail goes; recordings (rec_*) stay until removed by hand.
	$shots = @(Get-ChildItem $dir -File -Filter 'shot_*.png' -ErrorAction SilentlyContinue)
	if ($shots.Count -gt 0) {
		$keep = Join-Path $dir ('shots-' + $shots[0].LastWriteTime.ToString('yyyyMMdd-HHmmss'))
		New-Item -ItemType Directory -Force $keep | Out-Null
		$shots | Move-Item -Destination $keep -Force
	}
	Get-ChildItem $dir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'session.json' } | Remove-Item -Force
	$engine = @('--path', "`"$Root`"", '--resolution', $Resolution, '--position', $position)
	if ($Fps -gt 0) { $engine += @('--fixed-fps', "$Fps") }
	$all = $engine + @('--') + $gameArgs + @("--remote-play=`"$dir`"")
	if ($Fps -gt 0) { $all += "--fixed-step=$Fps" }
	if ($Mute) { $all += '--mute-audio' }
	# The log goes through Godot's own --log-file: redirecting the output here would hand
	# the game this shell's handles, and a caller piping this script would then wait for
	# the game to quit.
	$all = @('--log-file', "`"$(Join-Path $dir 'godot.log')`"") + $all
	$p = Start-Process -FilePath $Godot -ArgumentList $all -PassThru -WindowStyle Normal
	# Remote play writes ready.json once it reads its mailbox; a command sent before
	# that would be taken for a stale one.
	$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
	while (-not (Test-Path (Join-Path $dir 'ready.json')) -and (Get-Date) -lt $deadline -and -not $p.HasExited) { Start-Sleep -Milliseconds 200 }
	return $p.Id
}

if ($Start) {
	if (-not (Test-Path $Godot)) { throw "Godot not found at $Godot" }
	$s = Read-Session
	$pids = [ordered]@{}
	if ($s -and $s.pids) { foreach ($prop in $s.pids.PSObject.Properties) { $pids[$prop.Name] = $prop.Value } }
	$mainAlive = $false
	if ($pids.Contains('main')) { $mainAlive = [bool](Get-Process -Id $pids['main'] -ErrorAction SilentlyContinue) }
	$addingOnly = ($Observer -or $Friend) -and $mainAlive
	if ($s -and $addingOnly -and -not $PSBoundParameters.ContainsKey('Port')) { $Port = [int]$s.port }
	$started = @()
	# With -Friend, the scenario waits until the friend has joined: a --scenario at launch
	# runs before the friend window exists, and cite_rescue, van_unbuckle and annex_visit
	# would refuse for want of one. The host gets the moment's world flags at launch and
	# the scenario itself as a command once everyone is in.
	$scenarioLater = $Friend -and $Scenario -ne ''
	if (-not $addingOnly) {
		$hostArgs = @('--host', '--no-steam', '--name=Claude', "--port=$Port")
		if ($Scenario -ne '') {
			if (-not $scenarioLater) { $hostArgs += "--scenario=$Scenario" }
			$wantsTown = $Scenario -in @('drive', 'crash', 'crash_big', 'knock', 'plow')
			if ($wantsTown -and $Extra -notmatch '--town-map') { $hostArgs += '--town-map' }
			if ($wantsTown -and $Extra -notmatch '--job-seed') { $hostArgs += '--job-seed=777' }
			if (-not $wantsTown -and $Scenario -ne 'store' -and $Extra -notmatch '--start-zone|--job-seed') { $hostArgs += @('--start-zone=lot', '--job-seed=777', '--yard-size=1') }
		}
		if ($Extra -ne '') { $hostArgs += $Extra.Split(' ') }
		$pids['main'] = Start-Instance 'main' $hostArgs '20,40'
		$started += 'main'
		Save-Session $pids $Port $Fps
		# The first command waits for the world, the player and any scenario.
		$r = Send-Command 'main' '[["wait",0.3]]'
		Complete-Recordings $r
		if ($r) { $r | ConvertTo-Json -Depth 6 -Compress }
	}
	if ($Observer) {
		$obsArgs = @('--join=127.0.0.1', "--port=$Port", '--no-steam', '--name=Observer', '--observer')
		# The --sim- flags, and --rank= (a dev rank floor each peer reads for itself, so a client sees the shops the host's rank opened).
		if ($Extra -ne '' -and $Extra -match '--sim-|--rank=') { $obsArgs += @($Extra.Split(' ') | Where-Object { $_ -match '^--(sim-|rank=)' }) }
		$pids['observer'] = Start-Instance 'observer' $obsArgs '660,120'
		$started += 'observer'
		Save-Session $pids $Port $Fps
		$r = Send-Command 'observer' '[["wait",1.0]]'
		if ($r) { $r | ConvertTo-Json -Depth 6 -Compress }
	}
	if ($Friend) {
		# A plain client that plays: no --observer, so it isn't parked, ghosted or kept
		# safe; the scenarios that need a friend put it on the yard themselves.
		$friendArgs = @('--join=127.0.0.1', "--port=$Port", '--no-steam', '--name=Friend')
		if ($Extra -ne '' -and $Extra -match '--sim-|--rank=') { $friendArgs += @($Extra.Split(' ') | Where-Object { $_ -match '^--(sim-|rank=)' }) }
		$pids['friend'] = Start-Instance 'friend' $friendArgs '340,380'
		$started += 'friend'
		Save-Session $pids $Port $Fps
		$r = Send-Command 'friend' '[["wait",1.0]]'
		if ($r) { $r | ConvertTo-Json -Depth 6 -Compress }
	}
	if ($scenarioLater) {
		$r = Send-Command 'main' (Convert-Steps "scenario $Scenario")
		Complete-Recordings $r
		if ($r) { $r | ConvertTo-Json -Depth 6 -Compress }
	}
	"started $($started -join ' and ') on port $Port (fixed step: $(if ($Fps -gt 0) { "$Fps fps" } else { 'off' }))"
	if ($Steps -eq '[]' -and $Script -eq '') { exit 0 }
}

## -Script: each instance's lines, in order ("observer: ..." lines to the observer).
function Read-Script([string]$path) {
	$byInstance = [ordered]@{}
	foreach ($raw in (Get-Content $path)) {
		$line = $raw.Trim()
		if ($line -eq '' -or $line.StartsWith('#')) { continue }
		$target = $Instance
		$m = [regex]::Match($line, '^([A-Za-z][A-Za-z0-9_-]*)\s*:\s*(.*)$')
		if ($m.Success -and (Test-Path (Get-InstanceDir $m.Groups[1].Value))) {
			$target = $m.Groups[1].Value
			$line = $m.Groups[2].Value
		}
		if (-not $byInstance.Contains($target)) { $byInstance[$target] = @() }
		$byInstance[$target] += $line
	}
	return $byInstance
}

if ($Script -ne '') {
	if (-not (Test-Path $Script)) { throw "no script at $Script" }
	if (-not $PSBoundParameters.ContainsKey('TimeoutSeconds')) { $TimeoutSeconds = 1800 }
	$plan = Read-Script $Script
	# Every instance gets its whole list at once; they run side by side in the game.
	$sent = [ordered]@{}
	foreach ($name in $plan.Keys) {
		$dir = Get-InstanceDir $name
		$cmdPath = Join-Path $dir 'cmd.json'
		$last = 0
		if (Test-Path $cmdPath) {
			$m = [regex]::Match((Get-Content $cmdPath -Raw), '"id":\s*(\d+)')
			if ($m.Success) { $last = [int]$m.Groups[1].Value }
		}
		$id = $last + 1
		$json = Convert-Steps (($plan[$name]) -join '; ')
		[IO.File]::WriteAllText($cmdPath, '{"id": ' + $id + ', "steps": ' + $json + '}')
		$sent[$name] = $id
	}
	$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
	$results = [ordered]@{}
	while ($results.Count -lt $sent.Count -and (Get-Date) -lt $deadline) {
		Start-Sleep -Milliseconds 250
		foreach ($name in $sent.Keys) {
			if ($results.Contains($name)) { continue }
			$resultPath = Join-Path (Get-InstanceDir $name) 'result.json'
			if (-not (Test-Path $resultPath)) { continue }
			try { $r = Get-Content $resultPath -Raw | ConvertFrom-Json } catch { continue }
			if ([int]$r.id -eq $sent[$name]) { $results[$name] = $r }
		}
	}
	$failed = $false
	foreach ($name in $sent.Keys) {
		if (-not $results.Contains($name)) { Write-Host "timed out waiting for $name"; $failed = $true; continue }
		Complete-Recordings $results[$name]
		"[$name] " + ($results[$name] | ConvertTo-Json -Depth 6 -Compress)
	}
	if ($failed) { exit 1 }
	exit 0
}

$json = Convert-Steps $Steps
$result = Send-Command $Instance $json
if ($null -eq $result) { exit 1 }
Complete-Recordings $result
$result | ConvertTo-Json -Depth 6 -Compress
exit 0
