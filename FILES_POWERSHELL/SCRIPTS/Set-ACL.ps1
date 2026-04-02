<#
    .SYNOPSIS
        Défini les ACLs sur un serveur magasin.
        
    .DESCRIPTION
        Défini les ACLs sur un serveur magasin à partir de deux fichiers CSV en entrées. 
        Il effectue les actions suivantes :
            * Réactive l'héritage et réinitialise les droits sur les arbos définis en paramètres
            * Supprime les droits pour les groupes Utilisateurs, Tout le monde, Créateur propriétaire et Utilisateurs authentifiés
            * Défini les ACLs décrite dans le fichier ACLFile
    
    .PARAMETER SiteFile
        Fichier CSV délimité par des ; : (CodeSite;Server;LIST;READ;MODIFY;SHARE)

    .PARAMETER ACLFile
        Fichier CSV délimité par des ; : (Path;Identity;Rights;AccessType;IsInherited;InheritanceFlags;PropagationFlags)

    .PARAMETER Arbos
        Les arboresence à réinitialiser (Format : "D:\","F:\")

    .INPUTS
        Fichiers CSV délimités par des ; :
         * Fichier contenant les détail du site (CodeSite;Server;LIST;READ;MODIFY;SHARE)
         * Fichier contenant les détail des ACLs souhaitées (Path;Identity;Rights;AccessType;IsInherited;InheritanceFlags;PropagationFlags)

    .EXAMPLE
        Set-ACL.ps1 -SiteFile .\Site.csv -ACLFile .\ACL.csv -Arbos "D:\","F:\"

        Réinitialise les arborescence D:\ et F:\ et défini les ACL spécifiés dans ACLFile.csv sur les site renseignés dans Site.csv

    .NOTES
        Nom du fichier : Set-ACL.ps1
        Auteur   : CHELAN Andy
        Version  : 2.0
        Date     : 2026-03-25
#>


[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SiteFile,
    [Parameter(Mandatory)]
    [string]$ACLFile,
    [Parameter(Mandatory)]
    [string[]]$Arbos
)

function Write-Log {
    param(
        [string]$msg, 
        [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR","CLEAN")]
        [string]$type = "INFO"
    )
    
    $time = Get-Date -Format 'HH:mm:ss'
    $prefix = "[$time][$Env:COMPUTERNAME]"

    switch ($type.ToUpper()) {
        "INFO"    { Write-Host "$prefix ℹ️  $msg" -ForegroundColor Gray }
        "SUCCESS" { Write-Host "$prefix ✅ $msg" -ForegroundColor Green }
        "WARNING" { Write-Host "$prefix ⚠️  $msg" -ForegroundColor Yellow }
        "ERROR"   { Write-Host "$prefix ❌ $msg" -ForegroundColor Red }
        "CLEAN"   { Write-Host "$prefix 🧹 $msg" -ForegroundColor Cyan }
        default   { Write-Host "$prefix $msg" }
    }
}

Write-Log "Import du fichier <$SiteFile>" -Type INFO
Try {
    $Sites   = Import-Csv -Path $SiteFile -Delimiter ";"
    Write-Log "Fichier importé" -Type SUCCESS
}
Catch{
    Write-Log "Import impossible. Fin du script : $($_.Exception.Message)" -Type ERROR
}

Write-Log "Import du fichier <$ACLFile>" -Type INFO
Try {
    $Entries   = Import-Csv -Path $ACLFile -Delimiter ";"
    Write-Log "Fichier importé" -Type SUCCESS
}
Catch{
    Write-Log "Import impossible. Fin du script : $($_.Exception.Message)" -Type ERROR
}


foreach ($Site in $Sites) {

    $Server     = $Site.Server
    $ListGroup  = "RESSINFO\$($Site.LIST)"
    $ReadGroup  = "RESSINFO\$($Site.READ)"
    $ModifGroup = "RESSINFO\$($Site.MODIFY)"
    $Share      = $Site.SHARE

    Write-Log "Connexion à <$Server>" -Type INFO
    try {
        $Session = New-PSSession -ComputerName $Server -ErrorAction Stop
        Write-Log "Connexion à <$Server> réussie" -Type SUCCESS

        Invoke-Command -Session $Session -ScriptBlock {

            param ($Entries, $ListGroup, $ReadGroup, $ModifGroup, $Share, $Arbos)

            function Write-Log {
                param([string]$msg, [ValidateSet("INFO","SUCCESS","WARNING","ERROR","CLEAN")][string]$type="INFO")
                $time = Get-Date -Format 'HH:mm:ss'
                $prefix = "[$time][$Env:COMPUTERNAME]"
                switch ($type.ToUpper()) {
                    "INFO"    { Write-Host "$prefix ℹ️  $msg" -ForegroundColor Gray }
                    "SUCCESS" { Write-Host "$prefix ✅ $msg" -ForegroundColor Green }
                    "WARNING" { Write-Host "$prefix ⚠️  $msg" -ForegroundColor Yellow }
                    "ERROR"   { Write-Host "$prefix ❌ $msg" -ForegroundColor Red }
                    "CLEAN"   { Write-Host "$prefix 🧹 $msg" -ForegroundColor Cyan }
                }
            }

            $UsersToRemove = @("Utilisateurs", "Createur proprietaire", "Tout le monde", "AUTORITE NT\Utilisateurs authentifiés")

            Foreach ($Arbo in $Arbos) {

                Write-Log "Réactivation de l'héritage et reset des ACL sur l'arbo <$Arbo>" -type INFO
                Try {
                    Start-Process -FilePath "icacls.exe" -ArgumentList @($Arbo, "/inheritance:e", "/T") -NoNewWindow -Wait
                    Start-Process -FilePath "icacls.exe" -ArgumentList @($Arbo, "/reset", "/T /C") -NoNewWindow -Wait
                    Write-Log "Héritage réactivé et ACL réinitialisées sur <$Arbo>" -Type SUCCESS
                }
                Catch {
                    Write-log "Erreur lors de la réactivation de l'héritage sur <$Arbo> :" $($_.Exception.Message) -type ERROR
                }
            }

            Foreach ($User in $UsersToRemove) {

                Foreach ($Arbo in $Arbos) {

                    Write-Log "Suppression des droits du groupe <$User> sur l'arbo <$Arbo>" -type INFO
                    Try {
                        Start-Process -FilePath "icacls.exe" -ArgumentList @($Arbo, "/Remove", $User, "/T") -NoNewWindow -Wait
                        Write-Log "Droits du groupe <$User> supprimés sur <$Arbo>" -Type SUCCESS
                    }
                    Catch {
                        Write-log "Erreur lors de la suppression des droits du groupe <$User> sur <$Arbo> :" $($_.Exception.Message) -type ERROR
                    }
                }
            }

            Try {
                $EntriesGrouped = $Entries | Group-Object Path

                Foreach ($Group in $EntriesGrouped) {

                    $Path = $Group.Name

                    Switch ($Path) {
                    "{ShareMag}" { $Path = $Share} 
                    default { $Path = $Path }
                    }

                    If ($Path -ne "NotExist") {

                        If (Test-Path $Path) {
                        
                            $Acl = Get-Acl $Path

                            $Acl.Access | Where-Object { -not $_.IsInherited } | ForEach-Object { $Acl.RemoveAccessRule($_) | Out-Null }

                            Foreach ($Entry in $Group.Group) {

                                Switch ($Entry.Identity) {
                                    "{ModifGroup}" { $Identity = $ModifGroup }
                                    "{ReadGroup}"  { $Identity = $ReadGroup }
                                    "{ListGroup}"  { $Identity = $ListGroup }
                                    default        { $Identity = $Entry.Identity }
                                }

                                $Rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                                    $Identity,
                                    $Entry.Rights,
                                    $Entry.InheritanceFlags,
                                    $Entry.PropagationFlags,
                                    [System.Security.AccessControl.AccessControlType]::$($Entry.AccessType)
                                )

                                $Acl.AddAccessRule($Rule)
                                Write-Log "Préparation ACL : <$Path> => <$Identity> ($($Entry.Rights))" -Type INFO
                            }

                            Set-Acl -Path $Path -AclObject $Acl | Out-Null
                            Write-Log "ACL appliquées pour le dossier <$Path>" -Type SUCCESS
                        }
                    }
                }

            } 
            Catch {
                Write-Log "Erreur sur <$Path> : $($_.Exception.Message)" -Type ERROR
            }

            Write-Log "Modification du partage D: en AccessBased" -Type INFO
            Try {
                Set-SmbShare -Name "D" -FolderEnumerationMode AccessBased -Force -ErrorAction Stop
                Write-Log "Partage D: modifié en AccessBased" -Type SUCCESS
            } 
            Catch {
                Write-Log "Impossible de modifier le partage D: : $($_.Exception.Message)" -Type WARNING
            }

        } -ArgumentList $Entries, $ListGroup, $ReadGroup, $ModifGroup, $Share, $Arbos

        Write-Log "Déconnexion de <$Server>" -Type CLEAN
        Try { 
            Remove-PSSession $Session -ErrorAction Stop 
            Write-Log "Session <$Server> déconnectée" -type SUCCESS
        } 
        Catch {
            Write-Log "Déconnexion de <$Server> impossible : $($_.Exception.Message)" -Type WARNING
        }
    } 
    Catch {
        Write-Log "Connexion impossible à <$Server> : $($_.Exception.Message)" -Type ERROR
    }
}