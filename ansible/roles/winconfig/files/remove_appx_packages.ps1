$ErrorActionPreference = "Stop"

# See https://blog.danic.net/provisioned-apps-in-windows-10-pro/

$packagesToRemove = @(
    "Microsoft.3DBuilder",                          # 3D Builder
    "Microsoft.BingWeather",                        # Weather
    "Microsoft.GetHelp",                            # Get Help
    "Microsoft.GetStarted",                         # Tips
    "Microsoft.Messaging",                          # Messaging
    "Microsoft.Microsoft3DViewer",                  # Mixed Reality Viewer
    "Microsoft.MicrosoftOfficeHub",                 # Get MS Office
    "Microsoft.MicrosoftSolitaireCollection",       # Microsoft Solitaire Collection
    "Microsoft.MSPaint",                            # Paint 3D
    "Microsoft.OneConnect",                         # Paid Wifi and Cellular
    "Microsoft.People",                             # People
    "Microsoft.Print3D",                            # Print 3D
    "Microsoft.Wallet",                             # Wallet
    "Microsoft.WindowsAlarms",                      # Alarms & Clock
    "Microsoft.WindowsFeedbackHub",                 # Feedback Hub
    "Microsoft.WindowsMaps",                        # Maps
    "Microsoft.Xbox.TCUI",                          # Xbox Live in-game experience
    "Microsoft.XboxApp",
    "Microsoft.XboxGameOverlay",                    # Xbox Game bar
    "Microsoft.XboxIdentityProvider",
    "Microsoft.XboxSpeechToTextOverlay",
    "Microsoft.ZuneMusic",                          # Groove Music
    "Microsoft.ZuneVideo"                           # Movies & TV
)


foreach ($package in $packagesToRemove)
{
    $packageFullName = (Get-AppxPackage $package).PackageFullName
    if ($packageFullName)
    {
        Write-Host "Removing package: $packageFullName"
        Remove-AppxPackage -Package $packageFullName
    }
}

foreach ($package in $packagesToRemove)
{
    $packageName = (Get-AppxProvisionedPackage -Online | Where-Object { $_.Displayname -eq $package }).PackageName
    if ($packageName)
    {
        Write-Host "Removing provisioned package: $packageName"
        Remove-AppxProvisionedPackage -Online -PackageName $packageName
    }
}
