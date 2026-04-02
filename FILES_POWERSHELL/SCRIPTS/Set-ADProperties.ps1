<#
    .SYNOPSIS
        Met à jour des utilisateurs AD
        
    .DESCRIPTION
        Met à jour des utilisateurs AD à partir des informations renseignés dans un CSV.
        Les propriétés seront remplacéées par celles renseignées dans le fichier.

        Les propriétés Name et SamAccountName sont exclues des modifications. Elles ont uniquement la pour 
        identifier les utilisateurs.

    .PARAMETER InputFile
        Le fichier CSV contenant les colonnes correspondantes à la propriété AD. Séparé par des ;
        Exemple : SamAccountName;Name;Title;Department;TelephoneNumber;StreetAddress;l;PostalCode;co;Description;Company
        Colonne "SamAccountName" obligatoire.
        Les propriétés Name et SamAccountName sont exclues des modifications.

    .INPUTS 
        Le fichier CSV contenant les colonnes correspondantes à la propriété AD. Séparé par des ;
        Exemple : SamAccountName;Name;Title;Department;TelephoneNumber;StreetAddress;l;PostalCode;co;Description;Company
        Colonne "SamAccountName" obligatoire.
        Les propriétés Name et SamAccountName sont exclues des modifications.

    .EXAMPLE
        Set-ADProperties.ps1 -InputFile .\Users.csv

        Remplace les propriétés des utilisateurs rensignés dans le fichier Users.csv.

    .NOTES
        Nom du fichier : Set-ADProperties
        Auteur   : CHELAN Andy
        Version  : 1.0
        Date     : 2026-03-23
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$InputFile
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

Write-Log "Import du fichier CSV <$InputFile>" -type INFO
Try {
    $Entries = Import-Csv $InputFile -Delimiter ";" -Encoding utf8BOM -ErrorAction Stop
    Write-Log "Fichier importé" -type SUCCESS
}
Catch {
    Write-Log "Import impossible, fin du script : $($_.Exception.Message)" -Type ERROR
    Exit
}

 
Foreach ($Entry in $Entries) {

    $UserExist = $false

    Try {
        Write-Log "Traitement utilisateur $($Entry.SamAccountName)" -type INFO
        $SAM = (Get-ADUser -Identity $Entry.SamAccountName -ErrorAction Stop).SamAccountName
        $UserExist = $true
    }
    Catch {
        Write-Log "Utilisateur $($Entry.SamAccountName) inexistant" -type WARNING
    }

    If ($UserExist) {

        $Properties = @{}
        $Members = ($Entry | Get-Member -MemberType NoteProperty | Where-Object {$_.Name -ne "Name" -and $_.Name -ne "SamAccountName"}).Name
        
        Foreach ($Member in $Members) {

            $Value = $Entry.$Member
            If ($null -ne $Value -and $Value -ne "") {
            Write-Log "Ajout $SAM > $Member = $Value" -Type INFO
            $Properties[$Member] = $Value
            }
     }

    Try {
        Set-ADUser -Identity $SAM -Replace $Properties -ErrorAction Stop
        Write-Log "Utilisateur $($Entry.Name) modifié" -Type SUCCESS
    }
    Catch {
        Write-Log "Erreur $SAM : $($_.Exception.Message)" -Type WARNING
    }
       
    }
}