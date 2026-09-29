Add-Type -AssemblyName System.Drawing
$renderDirectory = 'C:/ChatGPT/1942/renders/zero'
$renderFiles = @('01-dessus.png', '02-dessous.png', '03-trois-quarts.png')
$board = New-Object System.Drawing.Bitmap(4200, 1840)
$graphics = [System.Drawing.Graphics]::FromImage($board)
$graphics.SmoothingMode = 'AntiAlias'
$graphics.InterpolationMode = 'HighQualityBicubic'
$firstImage = [System.Drawing.Bitmap]::FromFile((Join-Path $renderDirectory $renderFiles[0]))
$background = $firstImage.GetPixel(2,2)
$firstImage.Dispose()
$graphics.Clear($background)
$ink = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(48,54,49))
$muted = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(91,98,89))
$line = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(143,148,139), 2)
$titleFont = New-Object System.Drawing.Font('Segoe UI', 43, ([System.Drawing.FontStyle]::Regular), ([System.Drawing.GraphicsUnit]::Pixel))
$labelFont = New-Object System.Drawing.Font('Segoe UI', 32, ([System.Drawing.FontStyle]::Regular), ([System.Drawing.GraphicsUnit]::Pixel))
$smallFont = New-Object System.Drawing.Font('Segoe UI', 23, ([System.Drawing.FontStyle]::Regular), ([System.Drawing.GraphicsUnit]::Pixel))
$center = New-Object System.Drawing.StringFormat
$center.Alignment = 'Center'
$graphics.DrawString('1942  /  CHASSEUR ZERO', $titleFont, $ink, ([System.Drawing.RectangleF]::new(0,75,4200,65)), $center)
$graphics.DrawLine($line,100,164,4100,164)
$labels = @('01  /  DESSUS', '02  /  DESSOUS', '03  /  TROIS QUARTS FACE')
for ($viewIndex=0; $viewIndex -lt 3; $viewIndex++) {
    $renderImage = [System.Drawing.Image]::FromFile((Join-Path $renderDirectory $renderFiles[$viewIndex]))
    $graphics.DrawImage($renderImage, [System.Drawing.Rectangle]::new(($viewIndex*1400),190,1400,1400))
    $renderImage.Dispose()
    $graphics.DrawString($labels[$viewIndex],$labelFont,$ink,([System.Drawing.RectangleF]::new(($viewIndex*1400),1590,1400,60)),$center)
}
$graphics.DrawLine($line,100,1710,4100,1710)
$graphics.DrawString('BLENDER / CYCLES     -     STUDIO HDR     -     MODELE 3D TEXTURE', $smallFont, $muted, ([System.Drawing.RectangleF]::new(0,1750,4200,45)), $center)
$board.Save((Join-Path $renderDirectory 'planche-zero-studio.png'), [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose(); $board.Dispose()
$ink.Dispose();$muted.Dispose();$line.Dispose();$titleFont.Dispose();$labelFont.Dispose();$smallFont.Dispose();$center.Dispose()
