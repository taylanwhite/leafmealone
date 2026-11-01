<#
.SYNOPSIS
  Play the game by hand, one move at a time (net/dev/remote_play.gd).

.EXAMPLE
  tools\play.ps1 -Start                       # launch a windowed host with remote play on
  tools\play.ps1 '[["hold","move_forward",1.5]]'
  tools\play.ps1 '[["look",200,0],["tap","interact"]]'
  tools\play.ps1 -Stop

.NOTES
  Each call sends one command and waits for the game to answer; it prints the
  result (what's on screen, where you are) and the screenshot's path.
#>
param(
	[string]$Steps = '[]',
	[switch]$Start,
	[switch]$Stop,
	[string]$Extra = '',
	[int]$TimeoutSeconds = 60
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Dir = Join-Path $Root 'build\play'
$Godot = Join-Path $env:USERPROFILE 'Tools\Godot\Godot_v4.7.2-stable_win64.exe'

if ($Stop) {
	Get-Process | Where-Object { $_.Path -eq $Godot } | Stop-Process -Force
	"stopped"
	exit 0
}

if ($Start) {
	if (Test-Path $Dir) { Remove-Item -Recurse -Force $Dir }
	New-Item -ItemType Directory -Force $Dir | Out-Null
	$args2 = @('--path', $Root, '--resolution', '1280x720', '--', '--host', '--no-steam', '--name=Claude', "--remote-play=$Dir")
	if ($Extra -ne '') { $args2 += $Extra.Split(' ') }
	Start-Process -FilePath $Godot -ArgumentList $args2 -RedirectStandardOutput (Join-Path $env:TEMP 'play.log') -RedirectStandardError (Join-Path $env:TEMP 'play.err') | Out-Null
	# Wait for the world, then take a first look.
	Start-Sleep -Seconds 6
	$Steps = '[["wait",0.5]]'
}

# Plain steps, no quoting: "tap phone; wait 0.4; hold move_forward 1.5; look 200 0; click 640 360".
# Text for a "text" step is the rest of the step: "text Hello there".
if (-not $Steps.TrimStart().StartsWith('[')) {
	$parts = @()
	foreach ($chunk in ($Steps -split ';')) {
		$words = @($chunk.Trim() -split '\s+' | Where-Object { $_ -ne '' })
		if ($words.Count -eq 0) { continue }
		$verb = $words[0]
		if ($verb -eq 'text') {
			$parts += , @($verb, ($chunk.Trim().Substring(4).Trim()))
			continue
		}
		$item = @($verb)
		foreach ($w in $words[1..($words.Count - 1)]) {
			if ($words.Count -lt 2) { break }
			$n = 0.0
			if ([double]::TryParse($w, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$n)) { $item += $n } else { $item += $w }
		}
		$parts += , $item
	}
	$Steps = ConvertTo-Json -InputObject $parts -Compress -Depth 4
	if (-not $Steps.StartsWith('[[')) { $Steps = '[' + $Steps + ']' }
}

$cmdPath = Join-Path $Dir 'cmd.json'
$resultPath = Join-Path $Dir 'result.json'
$last = 0
if (Test-Path $cmdPath) {
	$m = [regex]::Match((Get-Content $cmdPath -Raw), '"id":\s*(\d+)')
	if ($m.Success) { $last = [int]$m.Groups[1].Value }
}
$id = $last + 1
$json = '{"id": ' + $id + ', "steps": ' + $Steps + '}'
[IO.File]::WriteAllText($cmdPath, $json)
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
while ((Get-Date) -lt $deadline) {
	Start-Sleep -Milliseconds 150
	if (Test-Path $resultPath) {
		try { $r = Get-Content $resultPath -Raw | ConvertFrom-Json } catch { continue }
		if ([int]$r.id -eq $id) {
			$r | ConvertTo-Json -Depth 4 -Compress
			exit 0
		}
	}
}
"timed out waiting for the game (id $id)"
exit 1
