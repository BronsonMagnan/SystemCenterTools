function Configure-DPMAgent {
    [cmdletbinding()]
    param(
        [parameter(mandatory)]
        [validateNotNullOrEmpty()]
        [string]$DPMServerName,
        [parameter(mandatory)]
        [ValidateNotNullorEmpty()]
        [string[]]$ComputerName,
        [parameter(mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSCredential]$Credential
    )

    begin {
    }
    
    Process {
        foreach($server in $ComputerName) {
            #Setup a session to $Server
            Write-Verbose "Creating a PSSession to $server"
            $session = $null
            try {
                $session = New-PSSession -ComputerName $server -Credential $Credential
            } catch {
                Write-warning "Could not establish a PSSession to $server"
            }
            if (-not ($session)) { 
                write-warning "Skipping $server"
                continue;
            }
 
            if ($session) {
                #Check to see if software installed
                $SoftwareInstalled = $null
                $SoftwareInstalled = Invoke-Command -Session $session -ScriptBlock {
                    $Software = Get-WmiObject -ClassName win32_product
                    $DPMAgent = $Software | Where-Object {$_.name -eq "Microsoft System Center  DPM Protection Agent"}
                    if ($DPMAgent) {
                        Write-Output $dpmagent.version
                    } else {
                        Write-Output $false 
                    }
                }

                if ($SoftwareInstalled) {
                    Write-Verbose "$Server has DPM agent version $($SoftwareInstalled) installed" 

                } else {
                    write-warning "$Server does not have DPM Agent installed, Skipping"
                    continue;
                }

            }
            
            #Check to see if CredSSP is enabled
            write-verbose "Checking to see if CredSSP is enabled on server $server"
            $CredSSPStatus = Invoke-Command -Session $session -ScriptBlock { 
                $CredSSPStatus = Get-WSManCredSSP | out-null
                if ($CredSSPStatus -match "This computer is configured to receive credentials from a remote client computer") {
                    Write-Output "KEEPCREDSSP"
                } else {
                    Write-Output "TEMPCREDSSP"
                }
            }

            $turnOffCredSSP = $true
            if ($CredSSPStatus -eq "KEEPCREDSSP") {
                Write-Verbose "Current status of CredSSP on $server is on, so we will not remove it on cleanup"
                $turnOffCredSSP = $false
            } else {
                Write-Verbose "Current status of CredSSP on $server is OFF, so we will turn it on for script and remove during cleanup"
            }

            Enable-WSManCredSSP -Role Client -DelegateComputer $server -Force | Out-Null
          
            #Turn on CredSSP if not already turned on.
            if ($CredSSPStatus -eq "TEMPCREDSSP") {
                Write-Verbose "Turning on CredSSP on $server"
                Invoke-Command -Session $session -ScriptBlock {
                    Enable-WSManCredSSP -role server -Force | Out-Null
                }                        
            }
            Remove-PSSession $session
        
            #Setup a session to $Server
            Write-Verbose "Creating a PSSession to $server with CredSSP"
            $session = $null
            try {
                $session = New-PSSession -ComputerName $server -Credential $Credential -Authentication Credssp
            } catch {
                Write-warning "Could not establish a PSSession to $server"
            }
            if (-not ($session)) { 
                write-warning "Skipping $server"
                if ($turnOffCredSSP) {
                    try {
                        $session = New-PSSession -ComputerName $server -Credential $Credential
                    } catch {
                        Write-warning "Could not establish a PSSession to $server"
                    }

                    Invoke-Command -Session $session -ScriptBlock {
                       Disable-WSManCredSSP -role server
                    }                        
                }
                continue;
            }


            if ($session) {

                #Configure DPM Agent
                Invoke-Command -Session $session -ArgumentList $DPMServerName -ScriptBlock {
                    Param($DPMServerName)
                    Start-Process -FilePath "C:\Program Files\Microsoft Data Protection Manager\DPM\bin\SetDpmServer.exe" -ArgumentList "-dpmServerName $DPMServerName" -RedirectStandardOutput "c:\dpmconfigure.log" -RedirectStandardError "c:\dpmconfigerror.log" -NoNewWindow -Wait | out-null
                }
                Write-Verbose "$Server should be ready for DPM attach, logs at c:\dpmconfigure.log"
            }

            #End of work loop, remove session
            Remove-PSSession $session

            if ($turnOffCredSSP) {
                try {
                    $session = New-PSSession -ComputerName $server -Credential $Credential
                } catch {
                    Write-warning "Could not establish a PSSession to $server CREDSSP is left on, you will need to fix this manually!"
                }

                Invoke-Command -Session $session -ScriptBlock {
                   Disable-WSManCredSSP -role server
                }
                $CredSSPStatus = Invoke-Command -Session $session -ScriptBlock { 
                    $CredSSPStatus = Get-WSManCredSSP | out-null
                    if ($CredSSPStatus -match "This computer is configured to receive credentials from a remote client computer") {
                        Write-Output "ON"
                    } else {
                        Write-Output "OFF"
                    }
                }
                write-verbose "Current Status of CREDSSP on $server is $CredSSPStatus"
            }


        } #end foreach loop
    } #end process block
    
    end {
    }
}

$servers = @("fswit2.contoso.com")

Configure-DPMAgent -DPMServerName "dpm03.contoso.com" -ComputerName $servers -Credential (Get-Credential "contoso\administrator") -Verbose
