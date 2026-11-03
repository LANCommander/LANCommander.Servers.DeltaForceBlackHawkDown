#Requires -Modules Logging
#Requires -Modules Hooks
#Requires -Modules OverlayFS

# Delta Force: Black Hawk Down isn't freely downloadable. Use an existing install in /config/Server,
# or set DFBHD_ARCHIVE_URL to a zip of the game folder, e.g. a LANCommander archive. The shallowest
# folder holding dfbhd.exe and resource.pff is used. The PDF manuals are left out.

Invoke-Hook "PreInstallDeltaForce"

$exe = Join-Path $Env:SERVER_DIR 'dfbhd.exe'

if (Test-Path -Path $exe) {
    Write-Log "Delta Force: Black Hawk Down found in $Env:SERVER_DIR"
} elseif ($Env:DFBHD_ARCHIVE_URL) {
    Write-Log "Downloading Delta Force: Black Hawk Down from $Env:DFBHD_ARCHIVE_URL"

    $zip     = '/tmp/dfbhd.zip'
    $extract = '/tmp/dfbhd'

    curl -fL --retry 3 --output $zip "$Env:DFBHD_ARCHIVE_URL"
    if ($LASTEXITCODE -ne 0) { throw "Download failed: $Env:DFBHD_ARCHIVE_URL" }

    Remove-Item -Recurse -Force -Path $extract -ErrorAction SilentlyContinue
    unzip -q -o $zip -d $extract -x '*.pdf' '*.PDF'
    # unzip exits 11 when an -x pattern matches nothing
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 11) { throw "Could not extract $zip" }

    $root = Get-ChildItem -Path $extract -Filter 'dfbhd.exe' -Recurse -File -Depth 3 |
        Where-Object { Get-ChildItem -Path $_.DirectoryName -Filter 'resource.pff' -File } |
        Sort-Object { $_.FullName.Length } |
        Select-Object -First 1 -ExpandProperty Directory
    if (-not $root) { throw "dfbhd.exe not found in $Env:DFBHD_ARCHIVE_URL" }

    New-Item -ItemType Directory -Path $Env:SERVER_DIR -Force | Out-Null
    Get-ChildItem -Path $root.FullName -Force | Move-Item -Force -Destination $Env:SERVER_DIR

    # Zips made on Windows can carry unusable Unix modes, which leave the .pff files unreadable
    chmod -R 'u+rwX,go+rX' $Env:SERVER_DIR
    chown -R "$($Env:UID):$($Env:GID)" $Env:SERVER_DIR

    Remove-Item -Recurse -Force -Path $zip, $extract

    # The overlay was mounted before Server/ was populated, and overlayfs doesn't reliably show
    # lower-dir changes made while mounted.
    mountpoint -q $Env:SERVER_ROOT
    if ($LASTEXITCODE -eq 0) {
        umount $Env:SERVER_ROOT
        Remove-Item -Path "$Env:WORK_DIR/*" -Recurse -Force -ErrorAction SilentlyContinue
        Mount-Overlay -MountPoint $Env:SERVER_ROOT -LowerDir $Env:SERVER_DIR -UpperDir $Env:OVERLAY_DIR -WorkDir $Env:WORK_DIR -RequireEmptyWorkDir -OverlayOption "xino=on"
        Write-Log "OverlayFS remounted"
    }

    Write-Log "Delta Force: Black Hawk Down installed"
} else {
    Write-Log -Level Error "dfbhd.exe not found in $Env:SERVER_DIR. Copy a Delta Force: Black Hawk Down install there or set DFBHD_ARCHIVE_URL."
}

Invoke-Hook "PostInstallDeltaForce"

Set-Location $Env:SERVER_ROOT
