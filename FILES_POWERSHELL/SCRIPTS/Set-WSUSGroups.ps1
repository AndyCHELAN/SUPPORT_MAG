<#
    .SYNOPSIS
        Met à jour les groupes AD WSUS

    .DESCRIPTION
        Met à jour les groupes AD WSUS à partir d'un fichier csv contenant computer et adresse IP.
        Il effectue les actions suivante : 
            * Défini le CodeSite du computer à partir de l'adresse IP
            * Créer un fichier temporaire contenant les computers et le groupe WSUS associé.
            * Met à jour le groupe AD WSUS

    .PARAMETER InputFile
        Le fichier CSV contenant les colonnes ComputerName et IPAddress. Séparé par des ;

    .INPUTS 
        Le fichier CSV contenant les colonnes ComputerName et IPAddress. Séparé par des ;
        
    .EXAMPLE
        Set-WSUSGroups -InputFile D:\Computers.csv

        Exécute le script avec le fichier en entrée Compters.csv

    .NOTES
        Nom du fichier : Set-WSUSGroups.ps1
        Auteur   : CHELAN Andy
        Version  : 1.0
        Date     : 2026-03-18
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
function Set-SiteCode {
    param(
        [string]$IP
    )

    $CLanNum = $IP.Split(".")[0]
    $LanNum = $IP.Split(".")[2]

    If ($CLanNum -eq 10) {
        If ($LanNum.Length -eq 1) {
            $SiteCode = "80$LanNum"
        }   
        ElseIf ($LanNum.Length -eq 2) {
            $SiteCode = "8$LanNum"
        }
    }
    Else { 
        If ($LanNum.Length -eq 1) {
            $SiteCode = "00$LanNum"
        }
        ElseIf ($LanNum.Length -eq 2) {
            $SiteCode = "0$LanNum"
        }
        Else {
            $SiteCode = $LanNum
        }
    }
    return $SiteCode
}

#$InputFile = "$PSScriptRoot\AllCompCTK.csv"
$OutputFile = "$PSScriptRoot\CompSiteGroup.csv"

If (Test-Path -Path $OutputFile) {
    Write-Log  "Suppression du fichier existant <$OutPutFile>" -type INFO
    Try {
        Remove-Item -Path $OutputFile
        Write-Log "Fichier supprimé" -Type SUCCESS
    }
    Catch {
        Write-Log "Suppression du fichier impossible. Fin du script :" $($_.Exception.Message) -Type ERROR
        Exit
    }
}

# --- CREATION FICHIER WSUS GROUP/COMP --- 

$Entries = Import-Csv -Delimiter ";" -Path $InputFile
$Result = @()

Write-Log "Définition des groupes WSUS" -type INFO
Foreach ($Entry in $Entries) {

    Try {
        $Comp = $Entry.ComputerName
        $IP   = $Entry.IPAddress

        $SiteCode = Set-SiteCode -IP $IP

        $WSUSGroup = "CK_$($SiteCode)_COMP"

        $Result += [PSCustomObject]@{
            ComputerName = $Comp
            IPAddress    = $IP
            SiteCode     = $SiteCode
            WSUSGroup    = $WSUSGroup
        }
    Write-Log "<$Comp> => <$SiteCode> => <$WSUSGroup>" -type SUCCESS

    }
    Catch {
        Write-Log "Erreur du traitement de <$($Entry.ComputerName)" -type WARNING
    }
}

Write-Log "Export du fichier <$OutputFile>" -Type INFO
Try {
    $Result | Export-Csv -NoTypeInformation -Delimiter ";" -Path $OutputFile 
    Write-Log "Fichier exporté" -type SUCCESS
}
Catch {
    Write-Log "Export du fichier impossible. Fin du script : " $($_.Exception.Message) -Type ERROR
    Exit
}

# --- MISE A JOUR DES GROUPES WSUS SUR l'AD ---

$Entries = Import-Csv -Path $OutputFile -Delimiter ";"

$EntriesGrouped = $Entries | Group-Object WSUSGroup

Foreach ($Group in $EntriesGrouped) {

    $GroupExist = $False
    $Computers = $Group.Group.ComputerName | Sort-Object -Unique
    $WSUSGroup = $Group.Name

    #Write-Log "Récupération des membres du groupe <$($Group.Name)>" -Type INFO
    Try {
        Get-AdGroup $Group.Name -ErrorAction Stop | Out-Null
        $GroupExist = $True
        $ActualMembers = (Get-ADGroupMember $Group.Name).Name
        #Write-Log "Membres récupérés" -Type SUCCESS
    } 
    Catch {
        Write-Log "Groupe $($Group.Name) inexsitant" -Type WARNING
    }

    If ($GroupExist) {
        Write-Log "Mise à jour des membres de <$WSUSGroup>" -Type INFO

        $CompToRemove = Compare-Object $Computers $ActualMembers | Where-Object {$_.SideIndicator -eq "=>"}
        $CompToAdd    = Compare-Object $Computers $ActualMembers | Where-Object {$_.SideIndicator -eq "<="}

        Foreach ($Computer in $CompToRemove) {
            $ComputerName = $Computer.InputObject
            Try {
                Remove-ADGroupMember -Identity $WSUSGroup -Members $ComputerName$ -Confirm:$false -ErrorAction Stop 
                Write-Log "Suppression <$ComputerName> => $WSUSGroup" -type SUCCESS
            }
            Catch {
                Write-Log "Erreur de la suppression <$ComputerName> :$($_.Exception.Message)" -Type WARNING
                
            }
        }

        Foreach ($Computer in $CompToAdd) {
            $ComputerName = $Computer.InputObject
            Try {
                Add-ADGroupMember -Identity $WSUSGroup -Members $ComputerName$ -Confirm:$false -ErrorAction Stop 
                Write-Log "Ajout <$ComputerName> => $WSUSGroup" -type SUCCESS
            }
            Catch {
                Write-Log "Erreur de l'ajout <$ComputerName> : $($_.Exception.Message)"  -Type WARNING
                
            }
        }
    }
}