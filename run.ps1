try
{
  cd $PSScriptRoot

  Enable-PSRemoting -SkipNetworkProfileCheck
  if ((Get-WSManInstance -ResourceURI winrm/config/service/auth).Negotiate -ne 'true')
  {
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WSMAN\Service -Name auth_negotiate -Value 1 -Type DWord
    Restart-Service WinRM
  }

  $shouldResetUac = $false
  $uacProperty = Get-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System | Select-Object -ExpandProperty LocalAccountTokenFilterPolicy
  if ($uacProperty -ne 1)
  {
    $shouldResetUac = $true
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System -Name LocalAccountTokenFilterPolicy -Value 1 -Type DWord
  }

  cd ansible
  & ..\msys64\usr\bin\sh.exe /run.sh
}
finally
{
  if ($shouldResetUac)
  {
    Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System -Name LocalAccountTokenFilterPolicy -Value 0 -Type DWord
  }

  Write-Host -NoNewLine 'Press any key to continue...';
  $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
}
