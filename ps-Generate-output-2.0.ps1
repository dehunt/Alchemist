# This script will process pdfs using Alchemist
# Arguments:
#	Alchemist executable directory
#	input file directory - Point this script at the test pdf file directory, not a specific file
#	output file directory - If it doesn't exist it will be created. If it does exist, it will be cleaned.
#							When cleaning, script makes sure there are NO pdfs in output-directory, so input-file-directory isn't accidently deleted

$alchOutputFormats = @("html", "xml", "epub")

# Create directory to store alchemist output for that pdf, then run the pdf through alchemist
function Run-Test($inPath, $outPath, $testFile) {
	New-Item -ItemType Directory -Path $(Join-Path $outPath $testFile) | Out-Null
	foreach ($format in $alchOutputFormats) {
		&$alchExe $(Join-Path $inPath $testFile".pdf") $(Join-Path $outPath $testFile) "-outputFormat" $format
	}
}

function Run-Compare($basePath, $outPath) {
    &$bcExe "@bcscript.txt" $basePath $outPath "compare.log" -silent | Out-Null
}

function Rename-Epub([string]$oldExt, [string]$newExt, [string]$location) {
	Push-Location $location | Out-Null
	Get-ChildItem -File -Recurse | % { Rename-Item -Path $_.PSPath -NewName $_.Name.replace($oldExt, $newExt)} | Out-Null
	Pop-Location | Out-Null
}

# Check correct number of args
if ($args.length -ne 3 -and $args.length -ne 5) {
	Write-Output "Usage: $($MyInvocation.MyCommand.Name) <Alchemist-installation-directory> <input-file-directory> <output-directory> <BeyondCompare-installation-directory> <baseline-directory>"
	Exit
}

# Check if BC directories provided
$compare = $false
if ($args.length -eq 5) {
    $compare = $true
}

$temp = "_temp"
if ($IsLinux -or $IsMacOS) {
	$alchExe=Join-Path $args[0] "Alchemist"
	Write-Output "IOS or Linux detected"
}
else {
	$alchExe=Join-Path $args[0] "Alchemist.exe"
	Write-Output "Windows detected"
}
$inDir="$($args[1])"
$outDir="$($args[2])"
$bcExe=""
$baselineDir=""
Write-Output "Starting Alchemist Test..."
Write-Output "	Alchemist path:             $alchExe"
Write-Output "	Input directory:            $inDir"
Write-Output "	Output directory:           $outDir"

if ($compare) {
	if ($IsLinux -or $IsMacOS) {
		$bcExe=Join-Path $args[3] "BCompare"
		Write-Output "BeyondCompare for IOS or Linux"
	}
    else {
		$bcExe=Join-Path $args[3] "BCompare.exe"
		Write-Output "BeyondCompare for Windows"
	}
    $baselineDir = "$($args[4])"
    Write-Output "	Beyond Compare Exe path:    $bcExe"
    Write-Output "	Baseline directory:         $baselineDir"
}

# Check Alchemist installation directory
if (!(Test-Path -Path $alchExe -PathType leaf)) {
	Write-Output "Cannot find Alchemist at $alchExe"
	Exit
}

# Check BeyondCompare installation directory
if ($compare -and !(Test-Path -Path $bcExe -PathType leaf)) {
	Write-Output "Cannot find BCompare in $bcExe"
	Exit
}

# Check baseline directory
if ($compare -and !(Test-Path $baselineDir)) {
    Write-Output "Cannot find baseline directory at $baselineDir"
	Exit
}

# If output directory doesn't exist, create it. If it does exist, clean it
if(!(Test-Path $outDir)) {
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
	Write-Output "Output directory created at: $outDir"
}
else {
	Write-Output "Output directory found."
	if ((Get-ChildItem -Path $outDir -Recurse -Filter *.pdf).count -eq 0){
		Write-Output "No PDF files found in output-directory. Cleaning output-directory"
		Get-ChildItem -Path $outDir -Recurse | Remove-Item -Recurse
	}
	else {
		Write-Output "PDF files found in output-directory. Are you sure that isn't the input-file-directory?"
		Exit
	}
}

# Check input directory exists
if (!(Test-Path -Path $inDir -PathType Container)) {
	Write-Output "Cannot find input file directory at $inDir"
	Exit
}
else {
	# Check that input directory has pdf files somewhere
	if ((Get-ChildItem -Path $inDir -Recurse -Filter *.pdf).count -eq 0){
		Write-Output "No PDF files located at input directory"
		Exit
	}
	else {
		# Get list of PDFs from input-file-directory
		Get-ChildItem -Path $inDir -Recurse -Filter *.pdf -Name | ForEach-object{
			Write-Output "Processing test file: $($_)"
			
			# For each object, split and store the path and filename (w/o extension) separately. Use -Leaf if extension is needed
			$aPath=Split-Path -Path $_				# set $aPath to just file path
			$aName=Split-Path -Path $_ -LeafBase	# set $aName to filename without extension
			
			# Currently PDF Alchemist will throw an error if you specify an outputDir and it doesn't already exist. So we make it.
			# Test if file is in a subdirectory
			if (!([string]::IsNullOrEmpty($aPath))){
				# Test if that subdirectory needs to be created
				if(!(Test-Path -Path $(Join-Path $outDir $aPath) -PathType Container)) {
					New-Item -ItemType Directory -Path $(Join-Path $outDir $aPath) | Out-Null
				}
				
				# Create test file's output folder and run Alchemist
				Run-Test $(Join-Path $inDir $aPath) $(Join-Path $outDir $aPath) $aName | Out-Null
			}
			
			# Else, just create an output folder for this test file, and run Alchemist with the output going here
			else {
				Run-Test $(Join-Path $inDir $aPath) $(Join-Path $outDir $aPath) $aName | Out-Null
			}
			
			# BeyondCompare won't show contents of EPUBs when scripting. If we want to compare, we rename the EPUBs to ZIP, then unpack them.
			if ($compare) {
				$zip = ".zip"
				$epub = ".epub"
				if ((Test-Path -Path $(Join-Path $baselineDir $aPath $aName $aName$zip)) -and (Test-Path -Path $(Join-Path $baselineDir $aPath $aName $aName$epub))) {
					# A ZIP and EPUB were both detected in this PDF's baseline folder. Removing the extant ZIP file.
					Remove-Item -Path $(Join-Path $baselineDir $aPath $aName $aName$zip) -Recurse | Out-Null
				}
				
				Rename-Epub ".epub" ".zip" $(Join-Path $baselineDir $aPath $aName) | Out-Null
				Rename-Epub ".epub" ".zip" $(Join-Path $outDir $aPath $aName) | Out-Null
				
				if (!(Test-Path -Path $(Join-Path $outDir $aPath $aName $aName$temp) -PathType Container)) {
					Expand-Archive -Path $(Join-Path $outDir $aPath $aName $aName$zip) -DestinationPath $(Join-Path $outDir $aPath $aName $aName$temp) | Out-Null
				}
				
				if (!(Test-Path -Path $(Join-Path $baselineDir $aPath $aName $aName$temp) -PathType Container)) {
					Expand-Archive -Path $(Join-Path $baselineDir $aPath $aName $aName$zip) -DestinationPath $(Join-Path $baselineDir $aPath $aName $aName$temp) | Out-Null
				}
			}
		}
	}
}

# If we don't want to compare to baseline, just exit now.
if (!$compare) {
	Exit
}

# Now that the EPUBs were expanded, revert them back
Rename-Epub ".zip" ".epub" "$outDir" | Out-Null
Rename-Epub ".zip" ".epub" "$baselineDir" | Out-Null
 
# Run BeyondCompare
Write-Output "Comparing output with the baseline."
Run-Compare $outDir $baselineDir | Out-Null
Write-Output "Check the results in compare.log."


# Get rid of the expanded "ZIP" files
Write-Output "Cleaning up temp files."
Get-ChildItem -Path $outDir -Include "*$temp" -Recurse -Force | Remove-Item -Force -Recurse | Out-Null
Get-ChildItem -Path $baselineDir -Include "*$temp" -Recurse -Force | Remove-Item -Force -Recurse | Out-Null