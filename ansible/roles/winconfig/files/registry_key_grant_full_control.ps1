param(
    [Parameter(Mandatory=$true)]
    [string] $RegistryKeyPath,

    [Parameter(Mandatory=$true)]
    [string] $User
)


$ErrorActionPreference = "Stop"


# https://www.leeholmes.com/blog/2010/09/24/adjusting-token-privileges-in-powershell/
function Enable-Privilege
{
    param(
        ## The privilege to adjust. This set is taken from
        ## http://msdn.microsoft.com/en-us/library/bb530716(VS.85).aspx
        [ValidateSet(
            "SeAssignPrimaryTokenPrivilege", "SeAuditPrivilege", "SeBackupPrivilege",
            "SeChangeNotifyPrivilege", "SeCreateGlobalPrivilege", "SeCreatePagefilePrivilege",
            "SeCreatePermanentPrivilege", "SeCreateSymbolicLinkPrivilege", "SeCreateTokenPrivilege",
            "SeDebugPrivilege", "SeEnableDelegationPrivilege", "SeImpersonatePrivilege", "SeIncreaseBasePriorityPrivilege",
            "SeIncreaseQuotaPrivilege", "SeIncreaseWorkingSetPrivilege", "SeLoadDriverPrivilege",
            "SeLockMemoryPrivilege", "SeMachineAccountPrivilege", "SeManageVolumePrivilege",
            "SeProfileSingleProcessPrivilege", "SeRelabelPrivilege", "SeRemoteShutdownPrivilege",
            "SeRestorePrivilege", "SeSecurityPrivilege", "SeShutdownPrivilege", "SeSyncAgentPrivilege",
            "SeSystemEnvironmentPrivilege", "SeSystemProfilePrivilege", "SeSystemtimePrivilege",
            "SeTakeOwnershipPrivilege", "SeTcbPrivilege", "SeTimeZonePrivilege", "SeTrustedCredManAccessPrivilege",
            "SeUndockPrivilege", "SeUnsolicitedInputPrivilege")]
        $Privilege,
        ## The process on which to adjust the privilege. Defaults to the current process.
        $ProcessId = $pid,
        ## Switch to disable the privilege, rather than enable it.
        [Switch] $Disable
    )

    ## Taken from P/Invoke.NET with minor adjustments.
    $definition = @'
    using System;
    using System.Runtime.InteropServices;

    public class AdjPriv
    {
        [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
        internal static extern bool AdjustTokenPrivileges(IntPtr htok, bool disall, ref TokPriv1Luid newst, int len, IntPtr prev, IntPtr relen);

        [DllImport("advapi32.dll", ExactSpelling = true, SetLastError = true)]
        internal static extern bool OpenProcessToken(IntPtr h, int acc, ref IntPtr phtok);

        [DllImport("advapi32.dll", SetLastError = true)]
        internal static extern bool LookupPrivilegeValue(string host, string name, ref long pluid);

        [StructLayout(LayoutKind.Sequential, Pack = 1)]
        internal struct TokPriv1Luid
        {
            public int Count;
            public long Luid;
            public int Attr;
        }

        internal const int SE_PRIVILEGE_ENABLED = 0x00000002;
        internal const int SE_PRIVILEGE_DISABLED = 0x00000000;
        internal const int TOKEN_QUERY = 0x00000008;
        internal const int TOKEN_ADJUST_PRIVILEGES = 0x00000020;

        public static bool EnablePrivilege(long processHandle, string privilege, bool disable)
        {
            bool success;
            TokPriv1Luid tp;
            IntPtr hproc = new IntPtr(processHandle);
            IntPtr htok = IntPtr.Zero;

            success = OpenProcessToken(hproc, TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, ref htok);
            if (!success)
            {
                return false;
            }

            tp.Count = 1;
            tp.Luid = 0;

            if (disable)
            {
                tp.Attr = SE_PRIVILEGE_DISABLED;
            }
            else
            {
                tp.Attr = SE_PRIVILEGE_ENABLED;
            }

            success = LookupPrivilegeValue(null, privilege, ref tp.Luid);
            if (!success)
            {
                return false;
            }

            success = AdjustTokenPrivileges(htok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
            return success;
        }
    }
'@

    $processHandle = (Get-Process -id $ProcessId).Handle
    $type = Add-Type $definition -PassThru
    $type[0]::EnablePrivilege($processHandle, $Privilege, $Disable)
}


function OpenRegistryKey
{
    param(
        [Parameter(Mandatory=$true)]
        [string] $Path,

        [Parameter(Mandatory=$true)]
        [Microsoft.Win32.RegistryKeyPermissionCheck] $PermissionCheck,

        [Parameter(Mandatory=$true)]
        [System.Security.AccessControl.RegistryRights] $Rights,

        [bool] $ParsePath = $true
    )

    $hiveMap = @{
        "HKEY_CURRENT_CONFIG" = [Microsoft.Win32.Registry]::CurrentConfig
        "HKEY_CLASSES_ROOT" = [Microsoft.Win32.Registry]::ClassesRoot
        "HKEY_CURRENT_USER" = [Microsoft.Win32.Registry]::CurrentUser
        "HKEY_LOCAL_MACHINE" = [Microsoft.Win32.Registry]::LocalMachine
        "HKEY_USERS" = [Microsoft.Win32.Registry]::Users
    }

    if ($ParsePath)
    {
        $parsedPath = Resolve-Path $Path | Select-Object -ExpandProperty ProviderPath
    }
    else
    {
        $parsedPath = $Path
    }

    $hivePrefix = ($parsedPath -split "\\")[0]

    if (-not $hiveMap.ContainsKey($hivePrefix))
    {
        throw "Invalid registry path"
    }

    $hive = $hiveMap[$hivePrefix]
    $hivePath = $parsedPath.Substring($hivePrefix.Length + 1)

    $regKey =  $hive.OpenSubKey($hivePath, $PermissionCheck, $Rights)
    if ($regKey -eq $null)
    {
        throw "Registry key not found"
    }

    return $regKey
}


function QueryRegistryRights
{
    param(
        [string] $Path
    )

    $rights = (
        [System.Security.AccessControl.RegistryRights]::ReadPermissions
    )

    $regKey = OpenRegistryKey `
        -Path $Path `
        -PermissionCheck ReadWriteSubTree `
        -Rights $rights `
        -ParsePath $false

    $regKeyParsedPath = $regKey.Name

    try
    {
        # Get original owner
        $acl = $regKey.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Owner)
        $originalOwner = $acl.GetOwner([type]::GetType([System.Security.Principal.NTAccount]))

        echo "Owner is $originalOwner"

        echo "ACCESS RULES:"
        $acl = $regKey.GetAccessControl()

        $accessRules = $acl.GetAccessRules($true, $true, [type]::GetType([System.Security.Principal.NTAccount]))
        return ,$accessRules
    }
    finally
    {
        $regKey.Close()
    }
}


function UpdateInheritedRegistryRightsRecursivly
{
    param(
        [string] $Path,

        [Parameter(Mandatory=$true)]
        [System.Security.Principal.NTAccount]$Identity
    )

    $parentKey = OpenRegistryKey `
        -Path $Path `
        -PermissionCheck ReadWriteSubTree `
        -Rights ([System.Security.AccessControl.RegistryRights]::EnumerateSubKeys -bor [System.Security.AccessControl.RegistryRights]::ReadKey -bor [System.Security.AccessControl.RegistryRights]::ReadPermissions) `
        -ParsePath $false

    try
    {
        $subKeyPaths = $parentKey.GetSubKeyNames() | Foreach-Object { "$($parentKey.Name)\${_}" }

        # Get parent owner
        $parentOwner = $parentKey.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Owner).GetOwner([type]::GetType([System.Security.Principal.NTAccount]))
    }
    finally
    {
        $parentKey.Close()
    }

    $fullControlAccessRule = New-Object System.Security.AccessControl.RegistryAccessRule(
        $Identity,
        ([System.Security.AccessControl.RegistryRights]::FullControl -bor $rights),
        ([System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit),
        [System.Security.AccessControl.PropagationFlags]::None,
        [system.security.accesscontrol.accesscontroltype]::Allow
    )

    foreach ($subKeyPath in $subKeyPaths)
    {
        try
        {
            $childRegKey = OpenRegistryKey `
                -Path $subKeyPath `
                -PermissionCheck ReadWriteSubTree `
                -Rights ([System.Security.AccessControl.RegistryRights]::TakeOwnership -bor [System.Security.AccessControl.RegistryRights]::ReadPermissions) `
                -ParsePath $false

            # Get original owner
            $childAcl = $childRegKey.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Owner)
            $childOriginalOwner = $childAcl.GetOwner([type]::GetType([System.Security.Principal.NTAccount]))
        }
        catch
        {
            # Error might be caused by access error when attempting to read permissions.
            # Try to re-open with only right for taking ownership
            $childRegKey = OpenRegistryKey `
                -Path $subKeyPath `
                -PermissionCheck ReadWriteSubTree `
                -Rights ([System.Security.AccessControl.RegistryRights]::TakeOwnership) `
                -ParsePath $false

            # Fallback to parent owner
            $childOriginalOwner = $parentOwner
        }

        # Change owner (necessary before resetting inheritance rules)
        $childAcl = $childRegKey.GetAccessControl([System.Security.AccessControl.AccessControlSections]::None)
        $childAcl.SetOwner($identity)
        $childRegKey.SetAccessControl($childAcl)

        try
        {
            $rule = New-Object System.Security.AccessControl.RegistryAccessRule(
                $Identity,
                ([System.Security.AccessControl.RegistryRights]::FullControl -bor $rights),
                [System.Security.AccessControl.InheritanceFlags]::None,
                [System.Security.AccessControl.PropagationFlags]::None,
                [system.security.accesscontrol.accesscontroltype]::Allow
            )

            # Get access
            $childAcl = $childRegKey.GetAccessControl()
            $childAcl.SetAccessRule($fullControlAccessRule)
            $childRegKey.SetAccessControl($childAcl)

            UpdateInheritedRegistryRightsRecursivly -Path $subKeyPath -Identity $Identity

            # Disable inheritance (get rid of old inherited rules), but ensure we still have full control access
            $childAcl = $childRegKey.GetAccessControl()
            $childAcl.SetAccessRuleProtection($true, $false)
            $childAcl.SetAccessRule($fullControlAccessRule)
            $childRegKey.SetAccessControl($childAcl)

            # Enable inheritance (update inherited rules), and remove explicit rule for full control access
            $childAcl = $childRegKey.GetAccessControl()
            $childAcl.PurgeAccessRules($Identity)
            $childAcl.SetAccessRuleProtection($false, $false)
            $childRegKey.SetAccessControl($childAcl)
        }
        finally
        {
            # Change back owner
            $childAcl = $childRegKey.GetAccessControl()
            $childAcl.SetOwner($childOriginalOwner)
            $childRegKey.SetAccessControl($childAcl)
        }
    }
}


# To be able to become owner
$success = Enable-Privilege SeTakeOwnershipPrivilege
if (!$success)
{
    Write-Error "Failed to enable SeTakeOwnershipPrivilege"
}

# To be able to change back to previous owner
$success = Enable-Privilege SeRestorePrivilege
if (!$success)
{
    Write-Error "Failed to enable SeTakeOwnershipPrivilege"
}

$rights = (
    [System.Security.AccessControl.RegistryRights]::TakeOwnership -bor
    [System.Security.AccessControl.RegistryRights]::ReadPermissions -bor
    [System.Security.AccessControl.RegistryRights]::EnumerateSubKeys -bor
    [System.Security.AccessControl.RegistryRights]::ReadKey -bor
    [System.Security.AccessControl.RegistryRights]::QueryValues
)

$regKey = OpenRegistryKey `
    -Path $RegistryKeyPath `
    -PermissionCheck ReadWriteSubTree `
    -Rights $rights

$regKeyParsedPath = $regKey.Name

try
{
    $identity = [System.Security.Principal.NTAccount]$User

    # Get original owner
    $acl = $regKey.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Owner)
    $originalOwner = $acl.GetOwner([type]::GetType([System.Security.Principal.NTAccount]))

    # Change owner
    $acl = $regKey.GetAccessControl([System.Security.AccessControl.AccessControlSections]::None)
    $acl.SetOwner($identity)
    $regKey.SetAccessControl($acl)

    # Give full control
    $acl = $regKey.GetAccessControl()
    $rule = New-Object System.Security.AccessControl.RegistryAccessRule(
        $identity,
        ([System.Security.AccessControl.RegistryRights]::FullControl -bor $rights),
        ([System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit),
        [System.Security.AccessControl.PropagationFlags]::None,
        [System.Security.AccessControl.AccessControlType]::Allow
    )
    $acl.SetAccessRule($rule)
    $regKey.SetAccessControl($acl)

    try
    {
        UpdateInheritedRegistryRightsRecursivly -Path $regKeyParsedPath -Identity $identity
    }
    finally
    {
        # Change back owner
        $acl = $regKey.GetAccessControl()
        $acl.SetOwner($originalOwner)
        $regKey.SetAccessControl($acl)
    }
}
finally
{
    $regKey.Close()
}
