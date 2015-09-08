function Get-TargetResource
{
    [OutputType([Hashtable])]
    param (
        [ValidateSet("Present", "Absent")]
        [string]$Ensure = "Present",
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$AgentName,
        [ValidateSet("Started", "Stopped")]
        [string]$State = "Started",                
        [string]$TeamCityAgentInstallationZipUrl,
        [string]$AgentHomeDirectory,
        [int]$AgentPort,
        [string]$ServerHostname,
        [int]$ServerPort
    )

    Write-Verbose "Checking if TeamCity Agent is installed"
    $installLocation = (get-itemproperty -path "HKLM:\Software\ORACLE\KEY_XE" -ErrorAction SilentlyContinue).ORACLE_HOME
    $present = Test-Path "$AgentHomeDirectory\bin\service.start.bat"
    Write-Verbose "TeamCity Agent present: $present"
    
    $currentEnsure = if ($present) { "Present" } else { "Absent" }
    
    Write-Verbose "Checking for Windows Service: $AgentName"
    $serviceInstance = Get-Service -Name $AgentName -ErrorAction SilentlyContinue
    $currentState = "Stopped"
    if ($serviceInstance -ne $null) 
    {
        Write-Verbose "Windows service: $($serviceInstance.Status)"
        if ($serviceInstance.Status -eq "Running") 
        {
            $currentState = "Started"
        }
        
        if ($currentEnsure -eq "Absent") 
        {
            Write-Verbose "Since the Windows Service is still installed, the service is present"
            $currentEnsure = "Present"
        }
    } 
    else 
    {
        Write-Verbose "Windows service: Not installed"
        $currentEnsure = "Absent"
    }

    return @{
        AgentName = $AgentName; 
        Ensure = $currentEnsure;
        State = $currentState;
    };
}

function Set-TargetResource 
{
    param (       
        [ValidateSet("Present", "Absent")]
        [string]$Ensure = "Present",
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$AgentName,
        [ValidateSet("Started", "Stopped")]
        [string]$State = "Started",    
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]            
        [string]$TeamCityAgentInstallationZipUrl,
        [string]$AgentHomeDirectory = "C:\TeamCity\Agent",
        [int]$AgentPort = 9090,
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ServerHostname,
        [int]$ServerPort = 80
    )

    if ($Ensure -eq "Absent" -and $State -eq "Started") 
    {
        throw "Invalid configuration: service cannot be both 'Absent' and 'Started'"
    }

    $currentResource = (Get-TargetResource -Name $AgentName)

    Write-Verbose "Configuring TeamCity Agent ..."
        
    if ($State -eq "Stopped" -and $currentResource["State"] -eq "Started") 
    {        
        Write-Verbose "Stopping TeamCity Agent service $AgentName"        	    
        Stop-Service -Name $AgentName -Force         
    }

    if ($Ensure -eq "Absent" -and $currentResource["Ensure"] -eq "Present")
    {                
        # Uninstall TeamCity Agent
        throw "Removal of TeamCity Agent Currently not supported by this DSC Module!"        
    } 
    elseif ($Ensure -eq "Present" -and $currentResource["Ensure"] -eq "Absent") 
    {
        Write-Verbose "Installing TeamCity Agent..."
        Install-TeamCityAgent -AgentName $AgentName -TeamCityAgentInstallationZipUrl $TeamCityAgentInstallationZipUrl `
            -AgentHomeDirectory $AgentHomeDirectory -AgentPort $AgentPort -ServerHostname $ServerHostname -ServerPort $ServerPort
        Write-Verbose "TeamCity Agent installed!"
    }

    if ($State -eq "Started" -and $currentResource["State"] -eq "Stopped") 
    {        
        Write-Verbose "Starting TeamCity Agent service $AgentName"                    
        Start-Service -Name $AgentName                          
    }

    Write-Verbose "Finished"
}

function Test-TargetResource 
{
    param (       
        [ValidateSet("Present", "Absent")]
        [string]$Ensure = "Present",
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$AgentName,
        [ValidateSet("Started", "Stopped")]
        [string]$State = "Started",                
        [string]$TeamCityAgentInstallationZipUrl,
        [string]$AgentHomeDirectory,
        [int]$AgentPort,
        [string]$ServerHostname,
        [int]$ServerPort
    )
 
    $currentResource = (Get-TargetResource -Name $AgentName)

    $ensureMatch = $currentResource["Ensure"] -eq $Ensure
    Write-Verbose "Ensure: $($currentResource["Ensure"]) vs. $Ensure = $ensureMatch"
    if (!$ensureMatch) 
    {
        return $false
    }
    
    $stateMatch = $currentResource["State"] -eq $State
    Write-Verbose "State: $($currentResource["State"]) vs. $State = $stateMatch"
    if (!$stateMatch) 
    {
        return $false
    }

    return $true
}

function Request-File 
{
    param (
        [string]$url,
        [string]$saveAs
    )
 
    Write-Verbose "Downloading $url to $saveAs"
    $downloader = new-object System.Net.WebClient
    $downloader.DownloadFile($url, $saveAs)
}

function Expand-ZipFile
{
    param (
        [string]$file, 
        [string]$destination
    )    
    Add-Type -assembly "system.io.compression.filesystem"
    [io.compression.zipfile]::ExtractToDirectory($file, $destination)
}
  
function Install-TeamCityAgent
{
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$AgentName,
        [Parameter(Mandatory=$True)]
        [string]$TeamCityAgentInstallationZipUrl,
        [Parameter(Mandatory=$True)]
        [string]$AgentHomeDirectory,
        [Parameter(Mandatory=$True)]
        [int]$AgentPort,
        [Parameter(Mandatory=$True)]
        [string]$ServerHostname,        
        [Parameter(Mandatory=$True)]
        [int]$ServerPort                     
    )
   
    if ((test-path $AgentHomeDirectory) -ne $true) {
        New-Item $AgentHomeDirectory -type directory
    }

    $installationZipFilePath = "$AgentHomeDirectory\TeamCityAgent.zip"
    if ((test-path $installationZipFilePath) -ne $true) 
    {
        Write-Verbose "Downloading TeamCity Agent installation zip from $TeamCityAgentInstallationZipUrl to $installationZipFilePath"
        Request-File $TeamCityAgentInstallationZipUrl $installationZipFilePath
        Write-Verbose "Downloaded TeamCity Agent installation zip to $installationZipFilePath"
    }
    
    Write-Verbose "Expanding TeamCity Agent installation zip $installationZipFilePath to directory $AgentHomeDirectory"
    Expand-ZipFile $installationZipFilePath $AgentHomeDirectory
    Write-Verbose "Expanded TeamCity Agent installation zip to directory $AgentHomeDirectory"
        
	# token replace oracle username and password
    Write-Verbose "Configuring TeamCity Agent with system password before installation."
    $agentConfigfile = "$AgentHomeDirectory\conf\buildAgent.dist.properties"
    (cat $agentConfigfile) -replace 'serverUrl=http://localhost:8111/', "serverUrl=http://$ServerHostname:$ServerPort/" `
        -replace 'name=', "name=$AgentName" `
        -replace 'ownPort=9090', "ownPort=$AgentPort" > $agentConfigfile    
    
    # TODO setup TeamCity Agent Windows Service
}
