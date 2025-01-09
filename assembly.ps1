# Define the main function
function AssembleEngine {
    param (
        [string]$ExeFilename,
        [string]$BaseDirectory = "",
        [string]$FileMask = "*",
        [string]$DetectionCode,
        [string]$StartHeader,
        [string]$EndHeader
    )

    # Utility function to write raw bytes to a file
    function Write-RawBytes {
        param (
            [System.IO.FileStream]$Stream,
            [byte[]]$Bytes
        )
        $Stream.Write($Bytes, 0, $Bytes.Length)
    }

    # Utility function to write an Int64 value to a file
    function Write-Int64 {
        param (
            [System.IO.FileStream]$Stream,
            [long]$Value
        )
        $Bytes = [BitConverter]::GetBytes($Value)
        Write-RawBytes -Stream $Stream -Bytes $Bytes
    }

    # Prepare the file list
    function Prepare-FileList {
        param (
            [string]$Dir
        )
        Get-ChildItem -Path $Dir -Recurse -Filter $FileMask -File | ForEach-Object {
            $_.FullName
        }
    }

    # Find signature in file stream
    function Find-Signature {
        param (
            [string]$Signature,
            [System.IO.FileStream]$Stream
        )
        $Buffer = New-Object byte[] 100000
        $Stream.Seek(0, [System.IO.SeekOrigin]::Begin) > $null
        while ($Stream.Read($Buffer, 0, $Buffer.Length) -gt 0) {
            $Content = [System.Text.Encoding]::Default.GetString($Buffer)
            if ($Content.Contains($Signature)) {
                return $true
            }
        }
        return $false
    }

    # Try opening the .exe file with retry logic
    function Try-OpenExeStream {
        $MaxTries = 10
        for ($Try = 1; $Try -le $MaxTries; $Try++) {
            try {
                return [System.IO.FileStream]::new($ExeFilename, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite)
            } catch {
                if ($Try -eq $MaxTries) {
                    throw "Failed to open $ExeFilename after $MaxTries attempts."
                }
                Start-Sleep -Seconds 1
            }
        }
    }

    # Main execution logic
    $BaseDirectory = if ($BaseDirectory -eq "") { Split-Path -Path $ExeFilename -Parent } else { $BaseDirectory }
    $BaseDirectory = Join-Path -Path $BaseDirectory -ChildPath "locale"

    $FileList = Prepare-FileList -Dir $BaseDirectory
    if ($FileList.Count -eq 0) {
        Write-Host "No files matching '$FileMask' found in '$BaseDirectory'. Exiting."
        return
    }

    $Stream = Try-OpenExeStream
    try {
        if (-not (Find-Signature -Signature $DetectionCode -Stream $Stream)) {
            throw "Signature '$DetectionCode' not found in $ExeFilename."
        }

        if ((Find-Signature -Signature $StartHeader -Stream $Stream) -or (Find-Signature -Signature $EndHeader -Stream $Stream)) {
            throw "The file has already been modified."
        }

        $Stream.Seek(0, [System.IO.SeekOrigin]::End) > $null
        Write-RawBytes -Stream $Stream -Bytes ([System.Text.Encoding]::Default.GetBytes($StartHeader))
        $RelativeOffsetHelper = $Stream.Position

        foreach ($File in $FileList) {
            Write-Host "Adding file: $File"
            $FileStream = [System.IO.FileStream]::new($File, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read)
            try {
                $Offset = $Stream.Position
                $Size = $FileStream.Length
                $Stream.CopyTo($FileStream)
            } finally {
                $FileStream.Close()
            }
        }

        $TableOffset = $Stream.Position
        foreach ($File in $FileList) {
            $NextPos = $Stream.Position
            Write-Int64 -Stream $Stream -Value ($NextPos - $RelativeOffsetHelper)
            Write-Int64 -Stream $Stream -Value ($Offset - $RelativeOffsetHelper)
            Write-Int64 -Stream $Stream -Value $Size
            $RelativeFilename = "locale\" + ($File -replace [Regex]::Escape($BaseDirectory), "")
            Write-RawBytes -Stream $Stream -Bytes ([System.Text.Encoding]::UTF8.GetBytes($RelativeFilename))
        }

        Write-Int64 -Stream $Stream -Value ($TableOffset - $RelativeOffsetHelper)
        Write-RawBytes -Stream $Stream -Bytes ([System.Text.Encoding]::Default.GetBytes($EndHeader))
    } finally {
        $Stream.Close()
    }

    Write-Host "Successfully added $($FileList.Count) files to $ExeFilename"
}

# Example usage
AssembleEngine -ExeFilename "path\to\your.exe" -DetectionCode "2E23E563-31FA-4C24-B7B3-90BE720C6B1A" -StartHeader "DXGBD7F1BE4-9FCF-4E3A-ABA7-3443D11AB362" -EndHeader "DXG1C58841C-D8A0-4457-BF54-D8315D4CF49D"
