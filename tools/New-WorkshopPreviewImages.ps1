[CmdletBinding()]
param(
    [string]$PatchRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'workshop-patches')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
Add-Type -AssemblyName System.Drawing

$items = @(
    [pscustomobject]@{
        Directory = 'QuickDealsMultiplayerPatch'
        Accent = [System.Drawing.Color]::FromArgb(37, 211, 102)
        Lines = @('QUICK DEALS', 'MULTIPLAYER', 'SAFETY PATCH')
        Symbol = 'QD'
    },
    [pscustomobject]@{
        Directory = 'TechCivicProgressMultiplayerPatch'
        Accent = [System.Drawing.Color]::FromArgb(79, 166, 255)
        Lines = @('TECH + CIVIC', 'MULTIPLAYER', 'SAFETY PATCH')
        Symbol = 'TC'
    },
    [pscustomobject]@{
        Directory = 'MultiplayerHelperSafetyPatch'
        Accent = [System.Drawing.Color]::FromArgb(255, 177, 66)
        Lines = @('MP HELPER', 'MULTIPLAYER', 'SAFETY PATCH')
        Symbol = 'MP'
    }
)

foreach ($item in $items) {
    $directory = Join-Path ([System.IO.Path]::GetFullPath($PatchRoot)) $item.Directory
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        throw "Patch directory does not exist: '$directory'."
    }

    $bitmap = [System.Drawing.Bitmap]::new(512, 512)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
        $graphics.Clear([System.Drawing.Color]::FromArgb(13, 22, 36))

        $backgroundBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(22, 37, 58))
        $accentBrush = [System.Drawing.SolidBrush]::new($item.Accent)
        $whiteBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(245, 248, 252))
        $mutedBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(174, 190, 210))
        $linePen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(90, $item.Accent), 5)
        try {
            $graphics.FillEllipse($backgroundBrush, 86, 42, 340, 340)
            $nodes = @(
                [System.Drawing.PointF]::new(256, 78),
                [System.Drawing.PointF]::new(138, 210),
                [System.Drawing.PointF]::new(374, 210),
                [System.Drawing.PointF]::new(256, 334)
            )
            $graphics.DrawLine($linePen, $nodes[0], $nodes[1])
            $graphics.DrawLine($linePen, $nodes[0], $nodes[2])
            $graphics.DrawLine($linePen, $nodes[1], $nodes[3])
            $graphics.DrawLine($linePen, $nodes[2], $nodes[3])
            foreach ($node in $nodes) {
                $graphics.FillEllipse($accentBrush, $node.X - 13, $node.Y - 13, 26, 26)
            }

            $symbolFont = [System.Drawing.Font]::new('Segoe UI', 66, [System.Drawing.FontStyle]::Bold)
            $titleFont = [System.Drawing.Font]::new('Segoe UI', 26, [System.Drawing.FontStyle]::Bold)
            $smallFont = [System.Drawing.Font]::new('Segoe UI', 17, [System.Drawing.FontStyle]::Bold)
            $center = [System.Drawing.StringFormat]::new()
            $center.Alignment = [System.Drawing.StringAlignment]::Center
            $center.LineAlignment = [System.Drawing.StringAlignment]::Center
            try {
                $graphics.DrawString($item.Symbol, $symbolFont, $whiteBrush, [System.Drawing.RectangleF]::new(128, 126, 256, 140), $center)
                $graphics.DrawString($item.Lines[0], $titleFont, $whiteBrush, [System.Drawing.RectangleF]::new(24, 361, 464, 48), $center)
                $graphics.DrawString($item.Lines[1], $smallFont, $accentBrush, [System.Drawing.RectangleF]::new(24, 411, 464, 34), $center)
                $graphics.DrawString($item.Lines[2], $smallFont, $mutedBrush, [System.Drawing.RectangleF]::new(24, 447, 464, 34), $center)
            }
            finally {
                $center.Dispose()
                $smallFont.Dispose()
                $titleFont.Dispose()
                $symbolFont.Dispose()
            }
        }
        finally {
            $linePen.Dispose()
            $mutedBrush.Dispose()
            $whiteBrush.Dispose()
            $accentBrush.Dispose()
            $backgroundBrush.Dispose()
        }

        $output = Join-Path $directory 'preview.png'
        $bitmap.Save($output, [System.Drawing.Imaging.ImageFormat]::Png)
        Write-Output $output
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}
