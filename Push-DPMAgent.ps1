#Push DPM Agent

function Push-DPMAgentInstall {
    [cmdletbinding()]
    param(
        [parameter(mandatory)]
        [validateNotNullorEmpty()]
        [String]$AgentSourcePath,
        [parameter(mandatory)]
        [validateNotNullorEmpty()]
        [string]$DPMServerName,
        [validateNotNullOrEmpty()]
        [String[]]$ComputerName,
        [PSCredential]$Credential
    )
    begin {
        try {
            $test = test-path -Path $AgentSourcePath -ErrorAction Stop
        } catch {
            Write-Error "$AgentSourcePath is not valid path"
        }
    }

    process {
        foreach ($Server in $ComputerName) {
            
            #Setup a session to $Server
            Write-Verbose "Creating a PSSession to $server"
            $session = $null
            try {
                if ($Credential) { 
                    $session = New-PSSession -ComputerName $server -Credential $Credential
                } else {
                    $session = New-PSSession -ComputerName $server
                }
            } catch {
                Write-warning "Could not establish a PSSession to $server"
            }
            if (-not ($session)) { 
                write-warning "Skipping $server"
                continue;
            }
            if ($session) {

                #Check to see if already installed 
                write-verbose "Checking to see if the software is already installed"
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
                    write-warning "$Server already has the DPM agent installed, version $($SoftwareInstalled)"
                    continue;
                }
                
                write-verbose "creating the temporary directory"
                Invoke-Command -Session $session -ScriptBlock {
                    $testpath = test-path "c:\dpmagentinstall" -ErrorAction SilentlyContinue
                    if (-not ($testpath) ) {
                        new-item -Path "c:\dpmagentinstall" -ItemType Directory -Force | out-null
                    } 
                }


                $filename = split-path -Path $AgentSourcePath -Leaf

                #Check if the installer has already been copied"
                write-verbose "Checking if the installer is already copied"
                $filepresent = Invoke-Command -Session $session -ArgumentList $filename -ScriptBlock {
                    param($filename)
                    $testpath = test-path (join-path -path "c:\dpmagentinstall" -ChildPath $filename) -ErrorAction SilentlyContinue
                    if ($testpath ) {
                        Write-Output $true
                    } else {
                        Write-Output $false
                    }
                }

                write-verbose "Copying the DPM Agent installer from $AgentSourcePath"
                if (-not ($filepresent) ) { 
                    copy-item -ToSession $session -Path $AgentSourcePath -Destination (join-path -path "c:\dpmagentinstall" -ChildPath $filename) -ErrorAction SilentlyContinue
                } else {
                    Write-Warning "Install source is already copied to server $server"
                }

                $copysucess = Invoke-Command -Session $session -ArgumentList $filename -ScriptBlock {
                    param($filename) 
                    $testpath = test-path (join-path "c:\dpmagentinstall" -ChildPath $filename) -ErrorAction SilentlyContinue
                    if ($testpath)  {
                        Write-Output $true
                    } else {
                        Write-Output $false
                    }
                }

                if (-not ($copysucess)) {
                    Write-Warning "Copy of $AgentSourcePath to $server failed"
                    continue;
                }
        

                #Perform the installation
                Invoke-Command -Session $session -ArgumentList $filename,$DPMServerName -ScriptBlock {
                    param($filename,$DPMServerName) 
                    Start-Process -FilePath (join-path -Path "c:\dpmagentinstall" -ChildPath $filename) -ArgumentList "/q /IAcceptEula" -RedirectStandardOutput "c:\dpmagentinstall\install.log" -RedirectStandardError "c:\dpmagentinstall\error.log" -NoNewWindow -Wait | out-null
                }

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
                    write-warning "$Server failed to install DPM agent"
                    continue;
                }

                #Configure DPM Agent - this step moved to it's own function for idempotency
                #Invoke-Command -Session $session -ArgumentList $DPMServerName -ScriptBlock {
                #    Param($DPMServerName)
                #    Start-Process -FilePath "C:\Program Files\Microsoft Data Protection Manager\DPM\bin\SetDpmServer.exe" -ArgumentList "-dpmServerName $DPMServerName" -RedirectStandardOutput "c:\dpmagentinstall\configure.log" -RedirectStandardError "c:\dpmagentinstall\configerror.log" -NoNewWindow -Wait | out-null
                #}

                Write-Verbose "Logs on $server at c:\dpmagentinstall\"
                #Write-Verbose "$Server should be ready for DPM attach"
            }
        }
    }

    end {
    }

}


#Agent Source
$AgentSource = "\\gufs1\Build\System Center Data Protection Manager 2019\Agents\DPMAgentInstaller_x64.exe"
$servers = @("fsclusnode01.contoso.com","fsclusnode02.contoso.com")

Push-DPMAgentInstall -AgentSourcePath $AgentSource -DPMServerName "dpm03.contoso.com" -ComputerName $servers -Verbose
