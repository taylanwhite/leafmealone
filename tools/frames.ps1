<#
.SYNOPSIS
  Put chosen frames of a playtest recording side by side, bigger than the contact
  sheet shows them, to read a moment closely (docs/PLAYTEST.md).

.EXAMPLE
  tools\frames.ps1 build\play\rec_caught 96,100,110,116,118,120
  tools\frames.ps1 build\play\rec_rake 30..40 -Crop 400,150,480,450 -Columns 6
  tools\frames.ps1 build\play\rec_rake 12,14 -Out build\rake_close.png

.NOTES
  Frames are frame_NNN.png in the recording's folder; each tile is stamped with
  its number and game time (from events.json). Writes <rec>\frames_<first>_<last>.png
  unless -Out says otherwise, and prints the path for the Read tool.
#>
param(
	[Parameter(Mandatory = $true, Position = 0)][string]$Dir,
	[Parameter(Mandatory = $true, Position = 1)][string]$FrameList,
	# x,y,w,h in the frame's pixels: show only this part of each frame.
	[string]$Crop = '',
	[int]$Columns = 3,
	# Each tile's width in pixels (its height follows the frame or crop).
	[int]$TileWidth = 640,
	[string]$Out = ''
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$Dir = (Resolve-Path $Dir).Path
# "12,14,20" and ranges like "30..40" (or "30-40"), mixed: "5,30..34,60".
$Frames = @()
foreach ($part in ($FrameList -split ',')) {
	$m = [regex]::Match($part.Trim(), '^(\d+)\s*(\.\.|-)\s*(\d+)$')
	if ($m.Success) { $Frames += [int]$m.Groups[1].Value..[int]$m.Groups[3].Value }
	elseif ($part.Trim() -ne '') { $Frames += [int]$part.Trim() }
}
$times = @{}
$events = Join-Path $Dir 'events.json'
if (Test-Path $events) {
	foreach ($f in (Get-Content $events -Raw | ConvertFrom-Json).frames) { $times[[int]$f.n] = [double]$f.t }
}
$first = [System.Drawing.Image]::FromFile((Join-Path $Dir ('frame_{0:D3}.png' -f $Frames[0])))
$src = New-Object System.Drawing.Rectangle 0, 0, $first.Width, $first.Height
$first.Dispose()
if ($Crop -ne '') {
	$c = $Crop.Split(',') | ForEach-Object { [int]$_ }
	$src = New-Object System.Drawing.Rectangle $c[0], $c[1], $c[2], $c[3]
}
$tileH = [int]($TileWidth * $src.Height / $src.Width)
$cols = [math]::Min($Columns, $Frames.Count)
$rows = [math]::Ceiling($Frames.Count / $cols)
$bmp = New-Object System.Drawing.Bitmap ($TileWidth * $cols), ($tileH * $rows)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::Black)
$font = New-Object System.Drawing.Font 'Arial', 13
$i = 0
foreach ($n in $Frames) {
	$path = Join-Path $Dir ('frame_{0:D3}.png' -f $n)
	$x = ($i % $cols) * $TileWidth
	$y = [math]::Floor($i / $cols) * $tileH
	if (Test-Path $path) {
		$img = [System.Drawing.Image]::FromFile($path)
		$g.DrawImage($img, (New-Object System.Drawing.Rectangle $x, $y, $TileWidth, $tileH), $src, [System.Drawing.GraphicsUnit]::Pixel)
		$img.Dispose()
	}
	$label = "#$n" + $(if ($times.ContainsKey($n)) { '  {0:N3} s' -f $times[$n] } else { '' })
	$g.FillRectangle([System.Drawing.Brushes]::Black, $x, $y, 128, 22)
	$g.DrawString($label, $font, [System.Drawing.Brushes]::Yellow, $x + 3, $y + 2)
	$i++
}
if ($Out -eq '') { $Out = Join-Path $Dir ('frames_{0:D3}_{1:D3}.png' -f $Frames[0], $Frames[-1]) }
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
$Out
