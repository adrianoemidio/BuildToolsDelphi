# Function to write a 32-bit integer to a binary writer
function Write-Int32 {
    param (
        [System.IO.BinaryWriter]$writer,
        [int]$value
    )
    $writer.Write([System.BitConverter]::GetBytes([int32]$value))
}

# Function to compile a .po file into a .mo file
function Compile-POToMO {
    param (
        [string]$poFilePath,
        [string]$moFilePath
    )
    
    $poContent = Get-Content -Path $poFilePath -Raw
    $entries = @()
    $entry = @{}
    foreach ($line in $poContent -split "`n") {
        $line = $line.Trim()
        if ($line -match '^msgid "(.*)"$') {
            $entry['msgid'] = $matches[1]
        } elseif ($line -match '^msgstr "(.*)"$') {
            $entry['msgstr'] = $matches[1]
        } elseif ($line -eq "") {
            if ($entry.ContainsKey('msgid') -and $entry.ContainsKey('msgstr')) {
                $entries += $entry
            }
            $entry = @{}
        }
    }
    if ($entry.ContainsKey('msgid') -and $entry.ContainsKey('msgstr')) {
        $entries += $entry
    }

    # Create a MemoryStream to build the .mo file content
    $memoryStream = New-Object System.IO.MemoryStream
    $writer = New-Object System.IO.BinaryWriter($memoryStream)
    
    # Write the .mo file header
    Write-Int32 $writer 0x950412de # Magic number
    Write-Int32 $writer 0 # Version (0)
    Write-Int32 $writer $entries.Count # Number of strings
    Write-Int32 $writer 28 # Offset of original strings table
    Write-Int32 $writer (28 + $entries.Count * 8) # Offset of translations table
    Write-Int32 $writer 0 # Hash table size (not used)
    Write-Int32 $writer 0 # Hash table offset (not used)

    $originalStrings = @()
    $translatedStrings = @()
    $offset = (28 + $entries.Count * 16)
    
    foreach ($entry in $entries) {
        $originalStrings += $entry['msgid']
        $translatedStrings += $entry['msgstr']
        
        Write-Int32 $writer ([System.Text.Encoding]::UTF8.GetByteCount($entry['msgid'])) # Length of original string
        Write-Int32 $writer $offset # Offset of original string
        $offset += ([System.Text.Encoding]::UTF8.GetByteCount($entry['msgid']) + 1) # +1 for null terminator
    }

    foreach ($entry in $entries) {
        Write-Int32 $writer ([System.Text.Encoding]::UTF8.GetByteCount($entry['msgstr'])) # Length of translated string
        Write-Int32 $writer $offset # Offset of translated string
        $offset += ([System.Text.Encoding]::UTF8.GetByteCount($entry['msgstr']) + 1) # +1 for null terminator
    }

    foreach ($originalString in $originalStrings) {
        $writer.Write([System.Text.Encoding]::UTF8.GetBytes($originalString + "`0")) # Null-terminated string
    }

    foreach ($translatedString in $translatedStrings) {
        $writer.Write([System.Text.Encoding]::UTF8.GetBytes($translatedString + "`0")) # Null-terminated string
    }

    # Save the MemoryStream to the .mo file
    $memoryStream.Seek(0, 'Begin')
    $moFileContent = $memoryStream.ToArray()
    [System.IO.File]::WriteAllBytes($moFilePath, $moFileContent)

    $writer.Close()
    $memoryStream.Close()
}

# Directory paths
$poDirectory = "C:\path\to\po\files"
$moDirectory = "C:\path\to\mo\files"

# Ensure the output directory exists
if (-not (Test-Path -Path $moDirectory)) {
    New-Item -ItemType Directory -Path $moDirectory
}

# Get all .po files in the directory
$poFiles = Get-ChildItem -Path $poDirectory -Filter "*.po"

# Compile each .po file to .mo
foreach ($poFile in $poFiles) {
    $moFileName = [System.IO.Path]::ChangeExtension($poFile.Name, ".mo")
    $moFilePath = Join-Path -Path $moDirectory -ChildPath $moFileName
    Compile-POToMO -poFilePath $poFile.FullName -moFilePath $moFilePath
}

Write-Host "Compilation complete. .mo files are saved in $moDirectory"
