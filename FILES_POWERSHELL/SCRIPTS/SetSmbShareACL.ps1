
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Path,
    [Parameter(Mandatory)]
    [string]$Name,
    [Parameter(Mandatory)]
    [string]$Right,
    [Parameter(Mandatory)]
    [string]$User
)

function Write-Log {
    param(
        [string]$msg, 
        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR","CLEAN")]
        [string]$type = "INFO"
    )
        
    $time = Get-Date -Format 'HH:mm:ss'

    If ($Server) {
        $prefix = "[$time][$server]"
    }
    Else {
        $prefix = "[$time][$Env:COMPUTERNAME]"
    }

    switch ($type.ToUpper()) {
        "INFO"    { Write-Host "$prefix ℹ️  $msg" -ForegroundColor Gray }
        "SUCCESS" { Write-Host "$prefix ✅ $msg" -ForegroundColor Green }
        "WARNING" { Write-Host "$prefix ⚠️  $msg" -ForegroundColor Yellow }
        "ERROR"   { Write-Host "$prefix ❌ $msg" -ForegroundColor Red }
        "CLEAN"   { Write-Host "$prefix 🧹 $msg" -ForegroundColor Cyan }
        default   { Write-Host "$prefix $msg" }
    }
}


Write-Log "Application des droits sur le partage <$Name>" -Type INFO
Try {
    Grant-SmbShareAccess -Name $Name -AccountName "Tout le monde" -AccessRight Full -Force -Confirm:$false | Out-Null
    Write-Log "Partage <$Name> : <FullControl> accordés à <Tout le monde>" -Type SUCCESS
}
Catch {
    Write-Log "Erreur lors de l'application des droits sur le partage <$Name> : $($_.Exception.Message)" -Type ERROR
}

Try {
    Write-Log "Application des droits NTFS sur le dossier <$Path>" -Type INFO
    $ACL = New-Object System.Security.AccessControl.DirectorySecurity
    $ACL.SetAccessRuleProtection($true, $false)
    $Rule = New-Object System.Security.AccessControl.FileSystemAccessRule("Administrateurs", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
    $ACL.AddAccessRule($Rule)
    Set-Acl -Path $Path -AclObject $ACL
    Write-Log "NTFS - <$Path> : <FullControl> accordé à <Administrateurs>" -Type SUCCESS
}
Catch {
     Write-Log "Erreur lors de l'application des droits NTFS à <Administrateurs> : $($_.Exception.Message)" -Type ERROR
}

Try {
    $User = $User
    $Right = $Right

    $RightsEnum = [System.Security.AccessControl.FileSystemRights]::$Right
    $Control = [System.Security.AccessControl.AccessControlType]::Allow
    $Rule = New-Object System.Security.AccessControl.FileSystemAccessRule($User, $RightsEnum, "ContainerInherit,ObjectInherit", "None", $Control)
    $Acl = Get-Acl -Path $Path
    $Acl.AddAccessRule($rule)
    Set-Acl -Path $Path -AclObject $acl -Confirm:$false
    Write-Log "NTFS - <$Path> : <$Right> accordé à <$User>" -Type SUCCESS
}
Catch {
    If ($_.Exception.Message -like "*identity references could not be translated*") {
        Write-Log "Utilisateur ou groupe <$($Entry.Name)> introuvable. Vérifiez qu'il existe localement ou dans l'AD." -Type WARNING
    } 
    Else {
        Write-Log "Erreur lors de l'affectation des droits à <$($Entry.Name)> : $($_.Exception.Message)" -Type ERROR
    }
}