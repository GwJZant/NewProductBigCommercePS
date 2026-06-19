#requires -Version 7.0
# Load the configuration file
$configFile = "$PSScriptRoot\config.json"
$version = "0.5.0"

# Check if the folder exists; if not, create it
if (-not (Test-Path -Path "$PSScriptRoot\Output")) {
    # -Force ensures it creates the entire tree if multiple levels are missing
    New-Item -ItemType Directory -Path "$PSScriptRoot\Output" -Force | Out-Null
}

# Check if the folder exists; if not, create it
if (-not (Test-Path -Path "$PSScriptRoot\tmp")) {
    # -Force ensures it creates the entire tree if multiple levels are missing
    New-Item -ItemType Directory -Path "$PSScriptRoot\tmp" -Force | Out-Null
}

# Assign file to process, relevant for SQL import
$FileToProcess = "Input\data.csv"
$DataSQL = "Input\dataSQL.csv"
$outputFolderPath = "$PSScriptRoot\Output\"

# Load the config file and ensure it exists
if (Test-Path $configFile) {
    # Read the file and convert JSON into a PowerShell Object
    $config = Get-Content -Path $configFile -Raw | ConvertFrom-Json
} else {
    Write-Host "ERROR: config.json not found!" -ForegroundColor Red
    exit
}

do {
	Write-Host "1. Process data.csv" -ForegroundColor Cyan
	Write-Host "2. Generate dataSQL.csv (Required: Input\products.txt)" -ForegroundColor Cyan
	Write-Host "3. Process dataSQL.csv" -ForegroundColor Cyan
	Write-Host "4. Generate ProductsNotInBigCommerce.csv" -ForegroundColor Cyan
	Write-Host "5. Quit" -ForegroundColor Cyan
	$selection = Read-Host "Enter your selection"
	Write-Host ""
	
	switch ($selection) {
		"1" {
			$FileToProcess = "Input\data.csv"
		}
		"2" {
			$ScriptDataCsvQuery = "Queries\dataCsvQuery.sql"
			$OutputFileTemp = "tmp\dataSQLTemp.csv"
			$InputProducts = "Input\products.txt"
			
			Write-Host "This process ONLY generates a dataSQL.csv file. After that is done, then do '3. Process dataSQL.csv'" -ForegroundColor Cyan
			Write-Host ""
			Write-Host "Wiping dataSQL.csv if it exists. Make sure you do NOT have this file open or it won't be wiped." -ForegroundColor Cyan
			Write-Host ""
			Write-Host "Reading products list from products.txt" -ForegroundColor Cyan
			
			Clear-Content -Path $OutputFileTemp -ErrorAction SilentlyContinue
			Clear-Content -Path $DataSQL -ErrorAction SilentlyContinue
			$products = ""
			
			if (Test-Path $InputProducts) {
				$ProductList = Get-Content -Path $InputProducts | Where-Object { $_.Trim() -ne "" }
				# Join the lines with quotes and commas
				$products = ($ProductList | ForEach-Object { "'$_'" }) -join ","
			}
			
			Write-Host ""
			# Connect to Celerant Database
			Write-Host "Connecting to Celerant Database..." -ForegroundColor Cyan

			# Set up SQL parameters
			$sqlParams = @{
				ServerInstance         = $config.Celerant.ServerInstance
				Database               = $config.Celerant.Database
				InputFile              = $ScriptDataCsvQuery
				Username               = $config.Celerant.Username
				Password               = $config.Celerant.Password
				Variable               = @("Products=$products")
				Encrypt                = "Mandatory"
				TrustServerCertificate = $true
			}
			
			try {
				$productData = Invoke-Sqlcmd @sqlParams
				
				$productData | Export-Csv -Path $DataSQL -NoTypeInformation -Delimiter ","
			} catch {
				Write-Host "Error: $_" -ForegroundColor DarkRed
			}
			
			Write-Host "Input\dataSQL.csv has been generated."  -ForegroundColor Green
		}
		"3" {
			$FileToProcess = $DataSQL
		}
		"4" {
			Write-Host "This has been moved to BigCommerceAudit"
		}
		"5" {
			Write-Host "Exiting..."
			Write-Host ""
		}
		Default {
            Write-Warning "Invalid selection, please try again."
            Start-Sleep -Seconds 2
        }
	}
	
	if ($selection -eq "1" -or $selection -eq "3") {
		$timestamp = Get-Date -Format "yyyy-MM-dd_HHmm"
		
		if (Test-Path $FileToProcess) {
			Write-Host "Processing $FileToProcess..."
			Write-Host ""
			
			$RowsToProcess = Import-Csv -Path $FileToProcess
			$TransformedData = [System.Collections.Generic.List[PSCustomObject]]::new()
			
			# Initialize variables
			$RowNum = 1
			$LastProduct = ""
			
			foreach ($row in $RowsToProcess) {
				$Product = $row.Product
				$CleanName = $row.Name.Trim()				
				$RowNum += 1
				
				if ($Product -ne $LastProduct) {			
					if ($row."Primary Barcode".Trim() -ne "") {
						Write-Host "New product found on a variant entry. Check line $RowNum. Aborting."
						Pause
						exit
					}
					
					# Write-Host "New product found. Inserting product entry then any variant entries if present."
					Write-Host "Product: $Product, Name: $CleanName, Price: $($row.Price), Item Type: $($row.'Item Type')"
					$LastProduct = $Product
					$LastPrice = $row.Price
					$ItemType = $row.'Item Type'
					
					$TaxClass = 0
					$Weight = 5
					$Width = 10
					$Height = 8
					$Depth = 6
					
					# Update Tax Class, Weight, and Dimensions for current product
					if ($ItemType -eq "1") { # Shoe
						$TaxClass = 1
						$Weight = 5
						$Width = 15
						$Height = 10
						$Depth = 5
					} elseif ($ItemType -eq "2") { # Insole/Sock
						$TaxClass = 1
						$Weight = 1
						$Width = 5
						$Height = 3
						$Depth = 1
					} elseif ($ItemType -eq "3" -or $ItemType -eq "5") { # Apparel
						$TaxClass = 1
						$Weight = 2
						$Width = 15
						$Height = 13
						$Depth = 3
					} elseif ($ItemType -eq "4") { # Other (pet supplies)
						$ContainsPetItem = 1
					} else {
						Write-Host "Unknown Item Type. Using default values."
					}
					
					if ($CleanName) {
						# Replace &, /, -, and : with spaces or empty strings as your batch script did
						$CleanName = $CleanName -replace '&', '' `
												-replace '/', ' ' `
												-replace '-', ' ' `
												-replace ':', ' '
					}
					
					# Extract initial keywords from row or fall back to the Product code
					$SearchKeywordsList = [System.Collections.Generic.List[string]]::new()
					
					if (-not [string]::IsNullOrWhiteSpace($row.'Search Keywords')) {
						# If present, we'll keep the existing keywords as our starting point
						$ExistingKeywords = $row.'Search Keywords' -split ','
						foreach ($Keyword in $ExistingKeywords) {
							$TrimmedKeyword = $Keyword.Trim()
							if (-not [string]::IsNullOrEmpty($TrimmedKeyword) -and -not $SearchKeywordsList.Contains($TrimmedKeyword)) {
								$SearchKeywordsList.Add($TrimmedKeyword)
							}
						}
					}

					# Always ensure the Product code is included/prepended per your rules
					if (-not [string]::IsNullOrWhiteSpace($row.Product)) {
						$ProductCode = $Row.Product.Trim()
						if (-not $SearchKeywordsList.Contains($ProductCode)) {
							$SearchKeywordsList.Add($ProductCode)
						}
					}
					
					if ($CleanName) {
						# Split the name by spaces to iterate over each individual word
						$Words = $CleanName -split '\s+'
						
						foreach ($CleanWord in $Words) {
							$CleanWord = $CleanWord.Trim()
							if ([string]::IsNullOrEmpty($CleanWord)) { continue }

							# If the word is "tshirt" (case-insensitive), force it to "T-Shirt"
							if ($CleanWord -ieq "tshirt") {
								$CleanWord = "T-Shirt"
							}

							# Append this word to our keyword collection if it isn't a duplicate
							if (-not $SearchKeywordsList.Contains($CleanWord)) {
								$SearchKeywordsList.Add($CleanWord)
							}
						}
					}
					
					$FinalSearchKeywords = $SearchKeywordsList -join ", "
					
					#Product-level entry
					$NewRow = [PSCustomObject]@{					
						"Item"                   = "Product"
						"ID"                     = ""
						"Name"                   = $row.Name.Trim()
						"Type"                   = "physical"
						"SKU"                    = $row.Product
						"Options"                = ""
						"Inventory"              = "variant"
						"Current Stock"          = 0
						"Price"                  = $row.Price
						"Search Keywords"        = $FinalSearchKeywords
						"UPC/EAN"                = ""
						"Free Shipping"          = $false
						"Fixed Shipping Cost"    = 0
						"Weight"                 = $Weight
						"Width"                  = $Width
						"Height"                 = $Height
						"Depth"                  = $Depth
						"Is Visible"             = $false
						"Is Featured"            = $false
						"Tax Class"              = $TaxClass
						"Product Condition"      = "New"
						"Show Product Condition" = $false
						"Sort Order"             = 0
					}
					
					$TransformedData.Add($NewRow)
				} else {
					# New Variant found
					if (-not [string]::IsNullOrWhiteSpace($row.'Primary Barcode')) {	
						if (-not [string]::IsNullOrWhiteSpace($row.Color)) {
							$OptionsText = "Type=Rectangle|Name=Color|Value=$($row.Color)"
						} else {
							$OptionsText = ""
						}
						
						if (-not [string]::IsNullOrWhiteSpace($row.Size)) {
							if ($ItemType -eq "5") {
								$OptionsText = $OptionsText + "Type=Rectangle|Name=Waist|Value=$($row.Size)"
							} else {
								$OptionsText = $OptionsText + "Type=Rectangle|Name=Size|Value=$($row.Size)"
							}
						}
						
						if (-not [string]::IsNullOrWhiteSpace($row.width)) {
							if ($ItemType -eq "5") {
								$OptionsText = $OptionsText + "Type=Rectangle|Name=Length|Value=$($row.width)"
							} else {
								$OptionsText = $OptionsText + "Type=Rectangle|Name=Width|Value=$($row.width)"
							}
						}
						
						if ($row.Price -eq $LastPrice) {
							$PriceText = ""
						} else {
							$PriceText = $row.Price
						}
						
						# Variant-level entry
						$NewRow = [PSCustomObject]@{					
							"Item"                   = "Variant"
							"ID"                     = ""
							"Name"                   = ""
							"Type"                   = ""
							"SKU"                    = $row.'Primary Barcode'
							"Options"                = $OptionsText
							"Inventory"              = ""
							"Current Stock"          = ""
							"Price"                  = $PriceText
							"Search Keywords"        = ""
							"UPC/EAN"                = $row.UPC
							"Free Shipping"          = $false
							"Fixed Shipping Cost"    = ""
							"Weight"                 = ""
							"Width"                  = ""
							"Height"                 = ""
							"Depth"                  = ""
							"Is Visible"             = ""
							"Is Featured"            = ""
							"Tax Class"              = ""
							"Product Condition"      = ""
							"Show Product Condition" = ""
							"Sort Order"             = ""
						}
						
						$TransformedData.Add($NewRow)
					} else {
						Write-Host "Variant expected on line $RowNum but no Primary Barcode found."
					}
				}
			}
			
			if ($TransformedData.Count -gt 0) {
				$OutputFile = $outputFolderPath + "\NewProducts" + $timestamp + ".csv"
				Write-Host "Exporting $($TransformedData.Count) rows to $OutputFile..." -ForegroundColor Cyan
				
				# 3. Export the collection natively
				$TransformedData | Export-Csv -Path $OutputFile -NoTypeInformation -UseQuotes AsNeeded -Delimiter "," -Encoding utf8
				
				Write-Host "Export complete! Your file is ready for BigCommerce." -ForegroundColor Green
				Write-Host ""
			} else {
				Write-Warning "No rows were processed, so no file was generated."
			}
		}
	}
} until ($selection -eq "5")

exit