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
$timestamp = Get-Date -Format "yyyy-MM-dd_HHmm"
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
	Write-Host "2. Generate dataSQL.csv (Required: products.txt)" -ForegroundColor Cyan
	Write-Host "3. Process dataSQL.csv" -ForegroundColor Cyan
	Write-Host "4. Generate ProductsNotInBigCommerce.csv (Required: BigCommerceProducts.txt)" -ForegroundColor Cyan
	Write-Host "5. Quit" -ForegroundColor Cyan
	$selection = Read-Host "Enter your selection"
	Write-Host ""
	
	switch ($selection) {
		"1" {
			Write-Host "Not built yet."
			Write-Host ""
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
		}
		"3" {
			Write-Host "Not built yet."
			Write-Host ""
			
			$FileToProcess = $DataSQL
		}
		"4" {
			Write-Host "Not built yet."
			Write-Host ""
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
		if (Test-Path $FileToProcess) {
			Write-Host "Processing $FileToProcess..."
			Write-Host ""
			
			$RowsToProcess = Import-Csv -Path $FileToProcess
			$TransformedData = [System.Collections.Generic.List[PSCustomObject]]::new()
			
			# Counter to track row number
			$RowNum = 0
			
			foreach ($row in $RowsToProcess) {
				$Product = $row.Product
				$CleanName = $row.Name.Trim()
				$RowNum += 1
				
				if ($Product -ne $LastProduct) {
					if ($LastProduct.Trim() -ne "") {
						$LastProduct = $Product
					} else {
						Write-Host "There is a problem with your data.csv on line $RowNum. Aborting."
					}
				}
				
				if ($Product -ne $LastProduct) {
					if ($row."Primary Barcode".Trim() -ne "") {
						Write-Host "New product found on a variant entry. Check line $RowNum. Aborting."
						Pause
						exit
					}
					
					Write-Host "New product found. Inserting product entry then any variant entries if present."
					Write-Host "Product: $Product, Name: $CleanName, Price: $row.Price, Item Type: $row.'Item Type'"
					$LastProduct = $Product
					$LastPrice = $row.Price
					
					$TaxClass = 0
					$Weight = 5
					$Width = 10
					$Height = 8
					$Depth = 6
					
					REM Update Tax Class, Weight, and Dimensions for current product
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
					} elseif ($ItemType -eq "3") { # Apparel
						$TaxClass = 1
						$Weight = 2
						$Width = 7
						$Height = 7
						$Depth = 2
					} elseif ($ItemType -eq "4") { # Other (pet supplies)
						$ContainsPetItem = 1
					} else {
						Write-Host "Unknown Item Type. Using default values."
					}
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
					"Name"                   = $CleanName
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
			}
		}
	}
} until ($selection -eq "5")

Pause
exit