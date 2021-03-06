#!/usr/local/bin/pwsh
#Requires -Version 4
# Compare-Directory.ps1
# https://gist.github.com/victorvogelpoel/6636754
# Compare files in one or more directories and return file difference results
# Victor Vogelpoel <victor@victorvogelpoel.nl>
# Sept 2013
#
# Disclaimer
# This script is provided AS IS without warranty of any kind. I disclaim all implied warranties including, without limitation,
# any implied warranties of merchantability or of fitness for a particular purpose. The entire risk arising out of the use or
# performance of the sample scripts and documentation remains with you. In no event shall I be liable for any damages whatsoever
# (including, without limitation, damages for loss of business profits, business interruption, loss of business information,
# or other pecuniary loss) arising out of the use of or inability to use the script or documentation.

[CmdletBinding(SupportsShouldProcess)]
param ()
# Set-StrictMode -Version latest

Write-Verbose -Message 'Declaring Function Add-FileComparisonAttribute'
function Add-FileComparisonAttribute {
    <#
        .SYNOPSIS
        Processes each file in a specified directory, for comparing files by hash values

        .DESCRIPTION
        Add-FileComparisonAttribute enumerates files contained in the specified folder, and returns a custom object containing each files name, FullName (Path) and MD5 Hash property

        .PARAMETER DirectoryPath
        File system Directory Path to enumerate

        .PARAMETER ExcludeFile
        Specify any file(s) to exclude

        .PARAMETER ExcludeDirectory
        Specify any directory(ies) to exclude

        .PARAMETER Recurse
        Recurse subdirectories / subfolders of DirectoryPath

        .EXAMPLE
        Add-FileComparisonAttribute -DirectoryPath $referenceDirectory -ExcludeFile $ExcludeFile -ExcludeDirectory $ExcludeDirectory -Recurse:$Recurse

        This is how this internal function is called by the primary function of this script file

        .OUTPUTS
        Customized File object
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory,HelpMessage='Specify File system Directory Path to process.')]
		[IO.DirectoryInfo]$DirectoryPath,
        [array]$ExcludeFile,
        [array]$ExcludeDirectory,
        [switch]$Recurse = $false
    )

    # Get the files from the first path, Add MD5 hash & a relative path property for each file
    Get-ChildItem -Path $DirectoryPath -Exclude $ExcludeFile -Recurse:$Recurse | ForEach-Object { 

        # Test for directories and files that need to be excluded because of ExcludeDirectory
        if (($PSItem.PSIsContainer) -and ($ExcludeDirectory -like $PSItem.Name)) {
            Write-Verbose -Message ('Excluding Directory/container item `"{0}"' -f $PSItem.Fullname)
        } elseif ($PSItem.PSIsContainer) {
            Write-Debug -Message ('Skipping Get-FileHash for Directory/container item "{0}"' -f $PSItem.Name)
        } else {
            Write-Debug -Message ('Adding "{0}" to result set' -f $PSItem.Name)
            # Added property(ies) to the object
            $hash = ''
            if (-not $PSItem.PSIsContainer) {
                Write-Debug -Message ('$hash = Get-FileHash -Algorithm MD5 -Path {0}' -f $PSItem.FullName)
                try {
                    $hash = Get-FileHash -Algorithm MD5 -Path $PSItem.FullName
                }
                catch {
                    Write-Warning -Message ("Failed: Get-FileHash -Algorithm MD5 -Path {0}`n{1}" -f $PSItem.Name, $Error[0])
                    break
                }
            }
            Write-Debug -Message ('$hash = {0}' -f $hash)
            $item = $PSItem |
                Add-Member -NotePropertyName 'MD5Hash' -NotePropertyValue $hash.Hash -PassThru
            #     |
            #    Add-Member -NotePropertyName "ContainerName" -NotePropertyValue $(Split-Path -Path $(Split-Path -Path $PSItem.FullName -Parent) -Leaf) -PassThru | 
            Write-Output -InputObject $item # $($item | select Name,CompareName,MD5Hash)
        }
    }
}

Write-Verbose -Message 'Declaring Function Compare-Directory'
function Compare-Directory {
    [OutputType([bool])]
    [CmdletBinding()]
	param (
		[Parameter(Mandatory, position=0, ValueFromPipelineByPropertyName, HelpMessage='The reference directory to compare one or more difference directories to.')]
		[IO.DirectoryInfo]$ReferenceDirectory,

		[Parameter(Mandatory, position=1, ValueFromPipeline, ValueFromPipelineByPropertyName, HelpMessage='One or more directories to compare to the reference directory.')]
		[IO.DirectoryInfo]$DifferenceDirectory,

		[Parameter(ValueFromPipelineByPropertyName)]
		[switch]$Recurse,

		[Parameter(ValueFromPipelineByPropertyName)]
		[array]$ExcludeFile,

		[Parameter(ValueFromPipelineByPropertyName)]
		[array]$ExcludeDirectory,

		[Parameter(ValueFromPipelineByPropertyName)]
		[switch]$ExcludeDifferent,
		
		[Parameter(ValueFromPipelineByPropertyName)]
		[switch]$IncludeEqual,
		
		[Parameter(ValueFromPipelineByPropertyName)]
		[switch]$PassThru
	)

	begin {
        # Get the contents of the base reference file/directory array for later comparison
        Write-Verbose -Message ('Getting FileComparisonAttribute for reference directory {0}' -f $referenceDirectory)
        Write-Debug -Message ('Add-FileComparisonAttribute -DirectoryPath {0} -ExcludeFile {1} -ExcludeDirectory {2} -Recurse:{3}' -f $referenceDirectory, $ExcludeFile, $ExcludeDirectory, $Recurse)
        $referenceDirectoryFiles = Add-FileComparisonAttribute -DirectoryPath $referenceDirectory -ExcludeFile $ExcludeFile -ExcludeDirectory $ExcludeDirectory -Recurse:$Recurse
        $results = $null
	}

	process {
		if ($DifferenceDirectory -and $referenceDirectoryFiles) {
			foreach($nextPath in $DifferenceDirectory) {
				# Get and compare the contents of the next file/directory array and return the results
		        Write-Debug -Message ('Getting FileComparisonAttributes Function for difference directory {0}' -f $nextpath)
		        Write-Debug -Message ('Add-FileComparisonAttribute -DirectoryPath {0} -ExcludeFile {1} -ExcludeDirectory {2} -Recurse:{3}' -f $nextpath, $ExcludeFile, $ExcludeDirectory, $Recurse)
				$nextDifferenceFiles = Add-FileComparisonAttribute -DirectoryPath $nextpath -ExcludeFile $ExcludeFile -ExcludeDirectory $ExcludeDirectory -Recurse:$Recurse
				$results = @(Compare-Object -ReferenceObject $referenceDirectoryFiles -DifferenceObject $nextDifferenceFiles -ExcludeDifferent:$ExcludeDifferent -IncludeEqual:$IncludeEqual -PassThru:$PassThru -Property Name, MD5Hash | Select-Object -Property Name, LastWriteTime, MD5Hash, SideIndicator)

				if ( -not $PassThru) {
                    foreach ($result in $results) {
                        $path 	   = $ReferenceDirectory
                        $pathFiles = $referenceDirectoryFiles
						
                        if ($result.SideIndicator -eq '=>') {
                            $path 	   = $nextPath
                            $pathFiles = $nextDifferenceFiles
                        }
                        
                        # Find the original item in the files array
                        # $itemPath = $(Join-Path $path $result.CompareName) #.ToString().TrimEnd('\')
                        $item = $pathFiles | Where-Object -FilterScript { $PSItem.fullName -eq $(Join-Path -Path $path -ChildPath $result.Name) }

                        $results | Add-Member -NotePropertyName 'Item' -NotePropertyValue $item -Force -PassThru
                    }
				}
				# Write-Output $results
			}
		} else {
            Write-Warning -Message "Missing dependency: Unable to proceed without both `$DifferenceDirectory and `$referenceDirectoryFiles"
        }
    }
    
    end {
        # $differences = 0
        # $results | % {$differences+=1}
        # if ($differences -gt 0)
        if ((Get-Variable -Name results -ErrorAction SilentlyContinue) -and ($results.Count -gt 0)) {
            return $false
        } else {
            return $true
        }
    }
    <#
        .SYNOPSIS
            Compares a reference directory with one or more difference directories.		

        .DESCRIPTION
            Compare-Directory compares a reference directory with one ore more difference
            directories. Files and directories are compared both on filename and contents
            using a MD5hash.
            
            Internally, Compare-Object is used to compare the directories. The behavior
            and results of Compare-Directory is similar to Compare-Object.

        .PARAMETER  ReferenceDirectory
            The reference directory to compare one or more difference directories to.

        .PARAMETER  DifferenceDirectory
            One or more directories to compare to the reference directory.

        .PARAMETER Recurse
            Include subdirectories in the comparison.
            
        .PARAMETER ExcludeFile
            File names to exclude from the comparison.

        .PARAMETER ExcludeDirectory
            Directory names to exclude from the comparison. Directory names are 
            relative to the Reference of Difference Directory path

        .PARAMETER ExcludeDifferent
            Displays only the characteristics of compared files that are equal.
            
        .PARAMETER IncludeEqual
            Displays characteristics of files that are equal. By default, only 
            characteristics that differ between the reference and difference files 
            are displayed.

        .PARAMETER PassThru
            Passes the objects that differed to the pipeline. By default, this 
            cmdlet does not generate any output.

        .EXAMPLE
            Compare-Directory -reference "D:\TEMP\CompareTest\path1" -difference "D:\TEMP\CompareTest\path2" -ExcludeFile "web.config" -recurse
            
            Compares directories "D:\TEMP\CompareTest\path1" and "D:\TEMP\CompareTest\path2" recursively, excluding "web.config"
            Only differences are shown. Results:
            
            RelativeBaseName  MD5Hash                          SideIndicator Item                                                                     
            ----------------  -------                          ------------- ----                                                                     
            bin\site.dll      87A1E6006C2655252042F16CBD7FB41B =>            D:\TEMP\CompareTest\path2\bin\site.dll
            index.html        02BB8A33E1094E547CA41B9E171A267B =>            D:\TEMP\CompareTest\path2\index.html                                     
            index.html        20EE266D1B23BCA649FEC8385E5DA09D <=            D:\TEMP\CompareTest\path1\index.html                                     
            web_2.config      5E6B13B107ED7A921AEBF17F4F8FE7AF <=            D:\TEMP\CompareTest\path1\web_2.config                                   
            bin\site.dll      87A1E6006C2655252042F16CBD7FB41B =>            D:\TEMP\CompareTest\path2\bin\site.dll
            index.html        02BB8A33E1094E547CA41B9E171A267B =>            D:\TEMP\CompareTest\path2\index.html                                     
            index.html        20EE266D1B23BCA649FEC8385E5DA09D <=            D:\TEMP\CompareTest\path1\index.html                                     
            web_2.config      5E6B13B107ED7A921AEBF17F4F8FE7AF <=            D:\TEMP\CompareTest\path1\web_2.config                                   

        .EXAMPLE
            Compare-Directory -reference "D:\TEMP\CompareTest\path1" -difference "D:\TEMP\CompareTest\path2" -ExcludeFile "web.config" -recurse -IncludeEqual
            
            Compares directories "D:\TEMP\CompareTest\path1" and "D:\TEMP\CompareTest\path2" recursively, excluding "web.config".
            Results include the items that are equal:
            
            RelativeBaseName    MD5Hash                          SideIndicator Item                                                 
            ----------------    -------                          ------------- ----                                                 
            bin 	                                             ==            D:\TEMP\CompareTest\path1\bin                        
            bin\site2.dll       98B68D681A8D40FA943D90588E94D1A9 ==            D:\TEMP\CompareTest\path1\bin\site2.dll
            bin\site3.dll       9408C4B29F82260CBBA528342CBAA80F ==            D:\TEMP\CompareTest\path1\bin\site3.dll
            bin\site4.dll       0616E1FBE12D468F611F07768D70C2EE ==            D:\TEMP\CompareTest\path1\bin\site4.dll
            ...
            bin\site8.dll       87A1E6006C2655252042F16CBD7FB41B =>            D:\TEMP\CompareTest\path2\bin\site8.dll
            index.html          02BB8A33E1094E547CA41B9E171A267B =>            D:\TEMP\CompareTest\path2\index.html                 
            index.html          20EE266D1B23BCA649FEC8385E5DA09D <=            D:\TEMP\CompareTest\path1\index.html                 
            web_2.config        5E6B13B107ED7A921AEBF17F4F8FE7AF <=            D:\TEMP\CompareTest\path1\web_2.config               

        .EXAMPLE
            Compare-Directory -reference "D:\TEMP\CompareTest\path1" -difference "D:\TEMP\CompareTest\path2" -ExcludeFile "web.config" -recurse -ExcludeDifference
            
            Compares directories "D:\TEMP\CompareTest\path1" and "D:\TEMP\CompareTest\path2" recursively, excluding "web.config".
            Results only include the files that are equal; different files are excluded from the results.
            
        .EXAMPLE
            Compare-Directory -reference "D:\TEMP\CompareTest\path1" -difference "D:\TEMP\CompareTest\path2" -ExcludeFile "web.config" -recurse -Passthru
            
            Compares directories "D:\TEMP\CompareTest\path1" and "D:\TEMP\CompareTest\path2" recursively, excluding "web.config" and returns NO comparison
            results, but the different files themselves!
            
            FullName                                                                                                                                                                  
            --------                                                                                                                                                                  
            D:\TEMP\CompareTest\path2\bin\site3.dll
            D:\TEMP\CompareTest\path2\index.html
            D:\TEMP\CompareTest\path1\index.html
            D:\TEMP\CompareTest\path1\web_2.config

        .LINK
            Compare-Object
    #>
}

# SIG # Begin signature block
# MIIHqgYJKoZIhvcNAQcCoIIHmzCCB5cCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUgYXne7rKgn3/jXBX8iv5clUN
# ndigggTFMIIEwTCCA3WgAwIBAgIQKn06fomwQ6RKe8dq7JvZkjBBBgkqhkiG9w0B
# AQowNKAPMA0GCWCGSAFlAwQCAQUAoRwwGgYJKoZIhvcNAQEIMA0GCWCGSAFlAwQC
# AQUAogMCASAwgZgxCzAJBgNVBAYTAlVTMRAwDgYDVQQIDAdNb250YW5hMREwDwYD
# VQQHDAhNaXNzb3VsYTETMBEGA1UECgwKQnJ5YW4gRGFkeTEVMBMGA1UECwwMQ29k
# ZSBTaWduaW5nMRowGAYDVQQDDBFTZWN1cmUgUG93ZXJTaGVsbDEcMBoGCSqGSIb3
# DQEJARYNYnJ5YW5AZGFkeS51czAeFw0xODEyMzAwMzM5NDNaFw0xOTEyMzAwMzU5
# NDNaMIGYMQswCQYDVQQGEwJVUzEQMA4GA1UECAwHTW9udGFuYTERMA8GA1UEBwwI
# TWlzc291bGExEzARBgNVBAoMCkJyeWFuIERhZHkxFTATBgNVBAsMDENvZGUgU2ln
# bmluZzEaMBgGA1UEAwwRU2VjdXJlIFBvd2VyU2hlbGwxHDAaBgkqhkiG9w0BCQEW
# DWJyeWFuQGRhZHkudXMwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQC3
# tawJQoBbR3HJe+GYdZMLf0jhbO7FM0SoX8509y1RR62TTFsgnK2Aqa1SbzTysBMS
# rL0+MI6ud44lC7/qCSTcCoqIpSMGtJ56QxJ3lLcRBe5Xb4xDLvzitpaGeKlugHfd
# QAAd1w0SetXT3D/AjnzW0/WrYZ6in3I9FzFF+JC24t4PGyQUaeE6UgCtEVyOdRGA
# gRr1Xhz9jomUVw84qof4LAAdfroR1z7VgY8j2Mq66HzsY63/y9iiBJSOeQ+OvBuz
# 6aaBoiiOflQ0HxbZYXuj5HSWeRPaFa/cM2Vp1iBJQ0K0ptaS6pAx2yOngWKhTGUY
# OPaFRxELdUICyBrSWFdlAgMBAAGjgZwwgZkwDgYDVR0PAQH/BAQDAgeAMFMGA1Ud
# EQRMMEqgHQYKKwYBBAGCNxQCA6APDA1icnlhbkBkYWR5LnVzgQ1icnlhbkBkYWR5
# LnVzggt3d3cuZGFkeS51c4INYnJ5YW4uZGFkeS51czATBgNVHSUEDDAKBggrBgEF
# BQcDAzAdBgNVHQ4EFgQUZUQGb3yr7zNZSgdlXQEmJ9SpdjIwQQYJKoZIhvcNAQEK
# MDSgDzANBglghkgBZQMEAgEFAKEcMBoGCSqGSIb3DQEBCDANBglghkgBZQMEAgEF
# AKIDAgEgA4IBAQCe91LHEw1CznKDFzRP4zzRf8DL/ffFgkOPjnb3e1JYiuTTobii
# HQtrTBRxnRh3t5nYQOkAdQZRW/VY2cUopMnVvBo1iJKkosPyVvP+QeZ/V9J9kJR0
# cYUpiMXmFKB6JMfGCfHG+cN3t57HDC2+yXD/tkvF0DwKrIXVz6MJIAq6ww9ZLs+d
# 7dUYo1T4I8F3J28X5YBiBPTQ0W2or2CWfnTNwxzQavdrRFoPBaZgXTrkdIjCuI9G
# 4Tnl1lNfz5qCshSBhOrwwYUkTuZv32hcYe1Yuj2exBfEF3gT5Cbgrp25v37dRDZ5
# qmIb6V9gpxBxUlJp2ApxyCvvGOejlh6BhtaxMYICTzCCAksCAQEwga0wgZgxCzAJ
# BgNVBAYTAlVTMRAwDgYDVQQIDAdNb250YW5hMREwDwYDVQQHDAhNaXNzb3VsYTET
# MBEGA1UECgwKQnJ5YW4gRGFkeTEVMBMGA1UECwwMQ29kZSBTaWduaW5nMRowGAYD
# VQQDDBFTZWN1cmUgUG93ZXJTaGVsbDEcMBoGCSqGSIb3DQEJARYNYnJ5YW5AZGFk
# eS51cwIQKn06fomwQ6RKe8dq7JvZkjAJBgUrDgMCGgUAoHgwGAYKKwYBBAGCNwIB
# DDEKMAigAoAAoQKAADAZBgkqhkiG9w0BCQMxDAYKKwYBBAGCNwIBBDAcBgorBgEE
# AYI3AgELMQ4wDAYKKwYBBAGCNwIBFTAjBgkqhkiG9w0BCQQxFgQUhtjAF5nKuRW0
# arMcbxpLsGq1M3swDQYJKoZIhvcNAQEBBQAEggEAEiqjlDssy2ofAlMh5yd2A9pD
# DpcbntU0vQGmdzWvJBiCLhU2FZkAUlXsSfhpCoSpwCv42i0aMQytLb9NEHuXhC3r
# ArxBrzu3P1qvzAsAc2pFIXBmp6g0jGJ2AkbCZ98OyBZveIkOjX9xRyfpwjpRWP4s
# UHC+wOYdHOgCmgQMq3VQOKs5HzO1/HIgvgZy77RZmrKbjLfK1oB/4hM0ripE//DR
# YQJFKggMrkjiiR4muamrFstyyUyFmCsWqQ5ZdXh5cmwz6/1C0R2/2K9gEgSywoFA
# 1reaiylYgsZM4MsyJP5lv/tazlOItHwa/ygv0tpdkwPQAusjjhTbjTd8Vq66fw==
# SIG # End signature block
