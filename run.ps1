try
{
  cd $PSScriptRoot
  cd ansible
  & ..\msys64\usr\bin\sh.exe /run.sh
}
finally
{
  Write-Host -NoNewLine 'Press any key to continue...';
  $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
}
