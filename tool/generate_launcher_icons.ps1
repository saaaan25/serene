$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

# Deterministic packaging of the existing brand PNG; no logo redraw.
$iconProjectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$iconSourcePath = Join-Path $iconProjectRoot 'assets\icons\logo_wo_text.png'
$iconSource = [Drawing.Bitmap]::new($iconSourcePath)

function New-LauncherBitmap {
    param([int]$PixelSize, [bool]$Opaque = $true, [double]$ArtworkWidth = 0.82)
    $pixelFormat = if ($Opaque) { [Drawing.Imaging.PixelFormat]::Format24bppRgb } else { [Drawing.Imaging.PixelFormat]::Format32bppArgb }
    $bitmap = [Drawing.Bitmap]::new($PixelSize, $PixelSize, $pixelFormat)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    try {
        $background = if ($Opaque) { [Drawing.Color]::White } else { [Drawing.Color]::Transparent }
        $graphics.Clear($background)
        $graphics.CompositingQuality = [Drawing.Drawing2D.CompositingQuality]::HighQuality
        $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $drawWidth = [single]($PixelSize * $ArtworkWidth)
        $drawHeight = [single]($drawWidth * $iconSource.Height / $iconSource.Width)
        $rectangle = [Drawing.RectangleF]::new(($PixelSize - $drawWidth) / 2, ($PixelSize - $drawHeight) / 2, $drawWidth, $drawHeight)
        $sourceRectangle = [Drawing.RectangleF]::new(0, 0, $iconSource.Width, $iconSource.Height)
        $graphics.DrawImage($iconSource, $rectangle, $sourceRectangle, [Drawing.GraphicsUnit]::Pixel)
    } finally { $graphics.Dispose() }
    return $bitmap
}

function Save-LauncherPng {
    param([string]$RelativePath, [int]$PixelSize, [bool]$Opaque = $true, [double]$ArtworkWidth = 0.82)
    $target = [IO.Path]::GetFullPath((Join-Path $iconProjectRoot $RelativePath))
    if (-not $target.StartsWith($iconProjectRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Icon output must stay inside the project'
    }
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
    $bitmap = New-LauncherBitmap -PixelSize $PixelSize -Opaque $Opaque -ArtworkWidth $ArtworkWidth
    try { $bitmap.Save($target, [Drawing.Imaging.ImageFormat]::Png) } finally { $bitmap.Dispose() }
}

try {
    Save-LauncherPng 'assets\icons\app_icon_light.png' 1024

    $densities = @(
        @('mdpi', 48, 108), @('hdpi', 72, 162), @('xhdpi', 96, 216),
        @('xxhdpi', 144, 324), @('xxxhdpi', 192, 432)
    )
    foreach ($density in $densities) {
        Save-LauncherPng "android\app\src\main\res\mipmap-$($density[0])\ic_launcher.png" $density[1]
        Save-LauncherPng "android\app\src\main\res\mipmap-$($density[0])\ic_launcher_foreground.png" $density[2] $false 0.58
    }

    foreach ($catalog in @('ios\Runner\Assets.xcassets\AppIcon.appiconset', 'macos\Runner\Assets.xcassets\AppIcon.appiconset')) {
        $contents = Get-Content -LiteralPath (Join-Path $iconProjectRoot "$catalog\Contents.json") -Raw | ConvertFrom-Json
        $written = @{}
        foreach ($entry in $contents.images) {
            if (-not $entry.filename -or $written.ContainsKey($entry.filename)) { continue }
            $points = [double]::Parse(($entry.size -split 'x')[0], [Globalization.CultureInfo]::InvariantCulture)
            $scale = [double]::Parse($entry.scale.TrimEnd('x'), [Globalization.CultureInfo]::InvariantCulture)
            Save-LauncherPng "$catalog\$($entry.filename)" ([int]($points * $scale))
            $written[$entry.filename] = $true
        }
    }

    Save-LauncherPng 'web\favicon.png' 32
    foreach ($size in @(192, 512)) {
        Save-LauncherPng "web\icons\Icon-$size.png" $size
        Save-LauncherPng "web\icons\Icon-maskable-$size.png" $size $true 0.8
    }

    # Windows ICO: a directory of PNG images, including the 256px resource.
    $icoImages = @()
    foreach ($size in @(16, 24, 32, 48, 64, 128, 256)) {
        $bitmap = New-LauncherBitmap $size
        $stream = [IO.MemoryStream]::new()
        try {
            $bitmap.Save($stream, [Drawing.Imaging.ImageFormat]::Png)
            $icoImages += @{ Size = $size; Bytes = $stream.ToArray() }
        } finally { $stream.Dispose(); $bitmap.Dispose() }
    }
    $icoPath = Join-Path $iconProjectRoot 'windows\runner\resources\app_icon.ico'
    $file = [IO.File]::Create($icoPath)
    $writer = [IO.BinaryWriter]::new($file)
    try {
        $writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$icoImages.Count)
        $offset = 6 + 16 * $icoImages.Count
        foreach ($entry in $icoImages) {
            $dimension = if ($entry.Size -eq 256) { 0 } else { $entry.Size }
            $writer.Write([byte]$dimension); $writer.Write([byte]$dimension)
            $writer.Write([byte]0); $writer.Write([byte]0)
            $writer.Write([uint16]1); $writer.Write([uint16]24)
            $writer.Write([uint32]$entry.Bytes.Length); $writer.Write([uint32]$offset)
            $offset += $entry.Bytes.Length
        }
        foreach ($entry in $icoImages) { $writer.Write([byte[]]$entry.Bytes) }
    } finally { $writer.Dispose(); $file.Dispose() }
    Write-Output 'Launcher icons generated from logo_wo_text.png on white.'
} finally { $iconSource.Dispose() }
