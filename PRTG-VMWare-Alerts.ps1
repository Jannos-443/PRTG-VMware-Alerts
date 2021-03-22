<#   
    .SYNOPSIS
    Monitors VMWare Alarms and Warnings

    .DESCRIPTION
    Using VMware PowerCLI this Script checks VMware Alerts and Warnings
    Exceptions can be made within this script by changing the variable $AlarmIgnoreScript or $VMIgnoreScript. This way, the change applies to all PRTG sensors 
    based on this script. If exceptions have to be made on a per sensor level, the script parameter VMIgnorePattern or AlarmIgnorePattern can be used.

    Copy this script to the PRTG probe EXEXML scripts folder (${env:ProgramFiles(x86)}\PRTG Network Monitor\Custom Sensors\EXEXML)
    and create a "EXE/Script Advanced. Choose this script from the dropdown and set at least:

    + Parameters: VCenter, Username, Password
    + Scanning Interval: minimum 5 minutes

    .PARAMETER ViServer
    The Hostname of the VCenter Server

    .PARAMETER UserName
    Provide the VCenter Username

    .PARAMETER Password
    Provide the VCenter Password

    .PARAMETER VMIgnorePattern
    Regular expression to describe the VMs to Ignore Alerts and Warnings

    .PARAMETER AlarmIgnorePattern
    Regular expression to describe the Alert to Ignore

    Example: ^(DemoTestServer|DemoAusname2)$

    Example2: ^(Test123.*|TestPrinter555)$ excluded Test12345 und alles mit 

    #https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_regular_expressions?view=powershell-7.1
    
    .EXAMPLE
    Sample call from PRTG EXE/Script Advanced
    PSx64.exe -f="PRTG-VMware-Alerts.ps1" -p="%VCenter%" "%Username%" "%PW%"

    .NOTES
    This script is based on the sample by Paessler (https://kb.paessler.com/en/topic/70174-monitor-vcenter)

    Author:  Jannos-443
    https://github.com/Jannos-443/PRTG-VMware-Alerts

#>
param(
    [string] $ViServer = "",
	[string] $User = "",
	[string] $Password = "",
    [string] $VMIgnorePattern = "", #VM Objekt to ignore
    [string] $AlarmIgnorePattern = "" #Alarm Message to ignore
)

#Catch all unhandled Errors
trap{
    $null = Disconnect-VIServer -Server $ViServer -Confirm:$false -ErrorAction SilentlyContinue
    Write-Output "<prtg>"
    Write-Output " <error>1</error>"
    Write-Output " <text>$($_.ToString() - $($_.ScriptStackTrace))</text>"
    Write-Output "</prtg>"
    Exit
}

[int] $Warnings = 0
[int] $WarningsNotAck = 0
[int] $WarningsAck = 0
[int] $Alerts = 0
[int] $AlertsNotAck = 0
[int] $AlertsAck = 0
[String] $WarningsText = ""
[String] $AlertsText = ""


# Import VMware PowerCLI module
$ViModule = "VMware.VimAutomation.Core"

try {
    Import-Module $ViModule -ErrorAction Stop
} catch {
    Write-Output "<prtg>"
    Write-Output " <error>1</error>"
    Write-Output " <text>Error Loading VMware Powershell Module ($($_.Exception.Message))</text>"
    Write-Output "</prtg>"
    Exit
}

#avoid unecessary output
Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP:$false -confirm:$false

# Ignore certificate warnings
Set-PowerCLIConfiguration -InvalidCertificateAction ignore -confirm:$false | Out-Null

# Connect to vCenter
try {
    Connect-VIServer -Server $ViServer -User $User -Password $Password -ErrorAction Stop | Out-Null
} catch {
    Write-Output "<prtg>"
    Write-Output " <error>1</error>"
    Write-Output " <text>Could not connect to vCenter server $ViServer. Error: $($_.Exception.Message)</text>"
    Write-Output "</prtg>"
    Exit
}

# Get a list of all Alarms
try {
    #$Alarms = (Get-Inventory -Server $ViServer -ErrorAction Stop).ExtensionData.TriggeredAlarmState
    $Alarms = (Get-Folder -Type "Datacenter" -Server $ViServer -ErrorAction Stop).ExtensionData.TriggeredAlarmState

} catch {
    Write-Output "<prtg>"
    Write-Output " <error>1</error>"
    Write-Output " <text>Could not Get-Inventory. Error: $($_.Exception.Message)</text>"
    Write-Output "</prtg>"
    Exit
}

#Filter Alarms

# hardcoded list that applies to all hosts
$AlarmIgnoreScript = '^(TestIgnore)$' 
$VMIgnoreScript = '^(TestIgnore)$' 

if($VMIgnorePattern -eq "")
    {
    $VMIgnorePattern = '^()$'
    }

if($AlarmIgnorePattern -eq "")
    {
    $AlarmIgnorePattern = '^()$'
    }


$xmlOutput = '<prtg>'

if ($Alarms.Count -gt 0) {
    foreach ($Alarm in $Alarms) {
        $path = (get-view $alarm.Entity -Server $ViServer).Name #Alarm Objekt
        $name = ((get-view $alarm.Alarm -Server $ViServer).info).name #Alarm Name

        #check ignore variables
        if(($name -match $AlarmIgnoreScript) -or ($path -match $VMIgnoreScript) -or ($path -match $VMIgnorePattern) -or ($alarm -match $AlarmIgnorePattern))
            {
            #ignored
            }

        #if not ignored
        else
            {
            if ($Alarm.OverallStatus -eq "yellow") {
                $Warnings += 1
                if ($Alarm.Acknowledged)
                    {
                    $WarningsAck += 1
                    } 
                else 
                    {
                    $WarningsNotAck +=1
                    $WarningsText += "$($path) - $($name) # "
                    }

            } 
            elseif ($Alarm.OverallStatus -eq "red") {
                $Alerts += 1
                if ($Alarm.Acknowledged) 
                    {
                    $AlertsAck += 1
                    } 
                else 
                    {
                    $AlertsNotAck += 1
                    $AlertsText += "$($path) - $($name) # "
                    }
            }
        }
    }
}
# Output Text
$OutputText =""

if($AlertsNotAck -gt 0)
    {
    $OutputText += "Alerts: $($AlertsText)"
    }

if($WarningsNotAck -gt 0)
    {
    $OutputText += "Warnings: $($WarningsText)"
    }


if(($WarningsNotAck -gt 0) -or ($AlertsNotAck -gt 0))
    {
    $xmlOutput = $xmlOutput + "<text>$OutputText</text>"
    }

else
    {
    $xmlOutput = $xmlOutput + "<text>No not Acknowledged Alarms or Warnings</text>"
    }

# Disconnect from vCenter
Disconnect-VIServer -Server $ViServer -Confirm:$false


$xmlOutput = $xmlOutput + "<result>
        <channel>Total Alerts - NOT Acknowledged</channel>
        <value>$AlertsNotAck</value>
        <unit>Count</unit>
        <limitmode>1</limitmode>
        <LimitMaxError>0.1</LimitMaxError>
        </result>

        <result>
        <channel>Total Warnings - NOT Acknowledged</channel>
        <value>$WarningsNotAck</value>
        <unit>Count</unit>
        <limitmode>1</limitmode>
        <LimitMaxWarning>0.1</LimitMaxWarning>
        </result>

        <result>
        <channel>Total Alerts - Acknowledged</channel>
        <value>$AlertsAck</value>
        <unit>Count</unit>
        </result>
        
        <result>
        <channel>Total Warnings - Acknowledged</channel>
        <value>$WarningsAck</value>
        <unit>Count</unit>
        </result>"   
        



$xmlOutput = $xmlOutput + "</prtg>"

$xmlOutput