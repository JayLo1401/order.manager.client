<#
.SYNOPSIS
    Erzeugt Logo, App-Icons und TV-Banner: die Pizza aus dem order.manager-Icon
    (docs/order_manager_icon.png) auf einem Fernseher, auf order.manager-Gruen.

.DESCRIPTION
    - docs/logo.png                      Logo 1024x1024 (README)
    - assets/logo.png                    Logo fuer die App-Kopfzeile (192 px)
    - mipmap-*/ic_launcher.png           Kachel mit transparenten Ecken (Android < 8)
    - drawable-nodpi/ic_launcher_foreground.png
                                         Fernseher fuer das adaptive Icon (Android 8+), im sicheren Bereich
    - values/colors.xml                  Hintergrundfarbe des adaptiven Icons
    - drawable-xhdpi/banner.png          TV-Banner 320x180 dp
#>
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = Split-Path -Parent $PSScriptRoot
$res = Join-Path $root 'android\app\src\main\res'
$src = [Drawing.Bitmap]::FromFile((Join-Path $root 'docs\order_manager_icon.png'))
# Pizza im 512er-Icon: Mittelpunkt 256/256, Rand-Radius ~200
$pizza = New-Object Drawing.Rectangle ([int]($src.Width * 56 / 512)), ([int]($src.Height * 56 / 512)), ([int]($src.Width * 400 / 512)), ([int]($src.Height * 400 / 512))

$green = [Drawing.Color]::FromArgb(255, 0x1B, 0x6B, 0x3E)   # order.manager theme-color
$brand = [Drawing.Color]::FromArgb(255, 0x2F, 0x9E, 0x5C)   # brandGreen (home.control)
$frame = [Drawing.Color]::FromArgb(255, 0xEC, 0xEF, 0xF1)
$screen = [Drawing.Color]::FromArgb(255, 0x14, 0x1A, 0x22)  # panelBackground

function New-Canvas([int]$w, [int]$h) {
    $bmp = New-Object Drawing.Bitmap($w, $h, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'; $g.InterpolationMode = 'HighQualityBicubic'
    $g.PixelOffsetMode = 'HighQuality'; $g.TextRenderingHint = 'AntiAliasGridFit'
    return $bmp, $g
}

function RoundRect([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
    $p = New-Object Drawing.Drawing2D.GraphicsPath
    $p.AddArc($x, $y, 2 * $r, 2 * $r, 180, 90); $p.AddArc($x + $w - 2 * $r, $y, 2 * $r, 2 * $r, 270, 90)
    $p.AddArc($x + $w - 2 * $r, $y + $h - 2 * $r, 2 * $r, 2 * $r, 0, 90); $p.AddArc($x, $y + $h - 2 * $r, 2 * $r, 2 * $r, 90, 90)
    $p.CloseFigure(); return $p
}

# Fernseher mit Pizza im Bild, in ein Quadrat ($x,$y,$s) gezeichnet (transparenter Grund)
function Draw-Tv($g, [float]$x, [float]$y, [float]$s) {
    $frameBrush = New-Object Drawing.SolidBrush $frame
    # Standfuss
    $g.FillRectangle($frameBrush, $x + 0.45 * $s, $y + 0.74 * $s, 0.10 * $s, 0.09 * $s)
    $g.FillPath($frameBrush, (RoundRect ($x + 0.29 * $s) ($y + 0.82 * $s) (0.42 * $s) (0.05 * $s) (0.025 * $s)))
    # Gehaeuse und Bildschirm
    $g.FillPath($frameBrush, (RoundRect ($x + 0.05 * $s) ($y + 0.13 * $s) (0.90 * $s) (0.64 * $s) (0.07 * $s)))
    $sx = $x + 0.09 * $s; $sy = $y + 0.17 * $s; $sw = 0.82 * $s; $sh = 0.56 * $s
    $g.FillPath((New-Object Drawing.SolidBrush $screen), (RoundRect $sx $sy $sw $sh (0.04 * $s)))
    # Pizza mittig im Bild
    $d = $sh * 0.86
    $px = $sx + ($sw - $d) / 2; $py = $sy + ($sh - $d) / 2
    $clip = New-Object Drawing.Drawing2D.GraphicsPath
    $clip.AddEllipse($px, $py, $d, $d)
    $g.SetClip($clip)
    $g.DrawImage($src, (New-Object Drawing.RectangleF $px, $py, $d, $d), $pizza, 'Pixel')
    $g.ResetClip()
}

# Gruene Kachel mit runden, transparenten Ecken und Fernseher
function Draw-Tile($g, [float]$x, [float]$y, [float]$s) {
    $g.FillPath((New-Object Drawing.SolidBrush $green), (RoundRect $x $y $s $s ($s * 0.2)))
    Draw-Tv $g ($x + 0.08 * $s) ($y + 0.08 * $s) (0.84 * $s)
}

function Save($bmp, [string]$path) {
    New-Item -ItemType Directory -Force (Split-Path -Parent $path) | Out-Null
    $bmp.Save($path, [Drawing.Imaging.ImageFormat]::Png)
}

# --- Logos ---
foreach ($item in @(@{ Size = 1024; Path = 'docs\logo.png' }, @{ Size = 192; Path = 'assets\logo.png' })) {
    $bmp, $g = New-Canvas $item.Size $item.Size
    Draw-Tile $g 0 0 $item.Size
    Save $bmp (Join-Path $root $item.Path)
    $g.Dispose(); $bmp.Dispose()
}

# --- Launcher-Icons fuer Android < 8 ---
$sizes = @{ 'mdpi' = 48; 'hdpi' = 72; 'xhdpi' = 96; 'xxhdpi' = 144; 'xxxhdpi' = 192 }
foreach ($d in $sizes.Keys) {
    $s = $sizes[$d]
    $bmp, $g = New-Canvas $s $s
    Draw-Tile $g 0 0 $s
    Save $bmp (Join-Path $res "mipmap-$d\ic_launcher.png")
    $g.Dispose(); $bmp.Dispose()
}

# --- Adaptives Icon: Fernseher im sicheren Bereich (66 von 108 dp) ---
$fs = 432                    # 108 dp bei xxxhdpi
$inner = [int]($fs * 0.66)
$off = [int](($fs - $inner) / 2)
$bmp, $g = New-Canvas $fs $fs
Draw-Tv $g $off $off $inner
Save $bmp (Join-Path $res 'drawable-nodpi\ic_launcher_foreground.png')
$g.Dispose(); $bmp.Dispose()
$hex = '#{0:X2}{1:X2}{2:X2}' -f $green.R, $green.G, $green.B
@"
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <!-- aus scripts/gen_icons.ps1 (order.manager-Gruen) -->
    <color name="ic_launcher_background">$hex</color>
</resources>
"@ | Set-Content (Join-Path $res 'values\colors.xml') -Encoding utf8

# --- TV-Banner 320x180 dp (xhdpi = 640x360 px) ---
$w = 640; $h = 360
$bmp, $g = New-Canvas $w $h
$g.Clear($screen)
$g.FillRectangle((New-Object Drawing.SolidBrush $brand), 0, $h - 10, $w, 10)
Draw-Tile $g 34 45 260
$font = New-Object Drawing.Font('Segoe UI Semibold', 50, [Drawing.FontStyle]::Bold, [Drawing.GraphicsUnit]::Pixel)
$small = New-Object Drawing.Font('Segoe UI', 24, [Drawing.FontStyle]::Regular, [Drawing.GraphicsUnit]::Pixel)
$g.DrawString('Order', $font, [Drawing.Brushes]::White, 318, 88)
$g.DrawString('Manager', $font, (New-Object Drawing.SolidBrush $brand), 318, 145)
$g.DrawString('Client · Bestell-Anzeige', $small, (New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(160, 255, 255, 255))), 322, 218)
Save $bmp (Join-Path $res 'drawable-xhdpi\banner.png')
$g.Dispose(); $bmp.Dispose()

$src.Dispose()
Write-Host "Logo, Icons und Banner erzeugt (Hintergrund $hex)."
