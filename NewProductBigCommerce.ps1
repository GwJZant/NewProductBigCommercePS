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
		}
		"3" {
			$FileToProcess = $DataSQL
		}
		"4" {
			$InputFile = "Input\BigCommerceProducts.txt"
			$ScriptBigCommerceProducts = "Queries\BigCommerceProducts.sql"
			$ScriptProductsNotInBC     = "Queries\ProductsNotInBigCommerce.sql"
			
			$ProductsNotInBigCommerce  = "Output\ProductsNotInBigCommerce_" + $timestamp + ".csv"
			
			if (Test-Path $InputFile) {
				Write-Host "Reading products list from $InputFile..." -ForegroundColor Cyan
				
				# Clean data natively in memory: trim spaces, tabs, quotes, and remove empty rows
				$CleanProducts = Get-Content -Path $InputFile | ForEach-Object {
					# Strips out quotes, literal tabs, spaces, and trims ends
					$_.Replace('"', '').Replace("`t", "").Replace(" ", "").Trim()
				} | Where-Object { $_ -ne "" }
				
				Write-Host "Total products found in file: $($CleanProducts.Count)"
				Write-Host "Fetching data from SQL Server..."
				
				$BatchSize   = 300
				$MatchedSKUs = [System.Collections.Generic.List[string]]::new()
				$BatchCount  = 0
				
				for ($i = 0; $i -lt $CleanProducts.Count; $i += $BatchSize) {
					# Grab a clean array slice of up to 300 items
					$BatchArray = $CleanProducts[$i..($i + $BatchSize - 1)] | Where-Object { $_ -ne $null }
					
					# Turn into a SQL-safe string format: 'prod1','prod2','prod3'
					$ProductsParamString = ($BatchArray | ForEach-Object { "'$_'" }) -join ","

					$BatchSqlParams = @{
						ServerInstance         = $config.Celerant.ServerInstance
						Database               = $config.Celerant.Database
						Username               = $config.Celerant.Username
						Password               = $config.Celerant.Password
						InputFile              = $ScriptBigCommerceProducts
						Variable               = @("Products=$ProductsParamString")
						Encrypt                = "Mandatory"
						TrustServerCertificate = $true
					}
					
					# Run the command with our explicit hash table
					$BatchResult = Invoke-Sqlcmd @BatchSqlParams

					# Collect resulting StyleIDs/SKUs into our matched array list
					if ($BatchResult) {
						foreach ($Row in $BatchResult) {
							# Drops values cleanly into memory (automatically avoids --- dashes or spacing issues)
							if ($Row[0]) { $MatchedSKUs.Add("('$($Row[0])')") }
						}
					}

					$BatchCount++
					Write-Host "Processed batch $BatchCount..."
				}
				
				if ($MatchedSKUs.Count -gt 0) {
					Write-Host "Assembling unified SQL transaction in memory..." -ForegroundColor Cyan
					
					# We use a .NET StringBuilder to fast-track appending thousands of string components
					$SqlScriptBuilder = [System.Text.StringBuilder]::new()

					# Append the initial table creation configuration script block
					[void]$SqlScriptBuilder.AppendLine("SET NOCOUNT ON;")
					[void]$SqlScriptBuilder.AppendLine("IF OBJECT_ID('tempdb..##BigCommerceList') IS NOT NULL DROP TABLE ##BigCommerceList;")
					[void]$SqlScriptBuilder.AppendLine("CREATE TABLE ##BigCommerceList (StyleID VARCHAR(255));")

					# Dynamically loop and build all our multi-row INSERT queries straight into memory
					for ($j = 0; $j -lt $MatchedSKUs.Count; $j += $BatchSize) {
						$InsertSlice = $MatchedSKUs[$j..($j + $BatchSize - 1)] | Where-Object { $_ -ne $null }
						
						# Force clean and guarantee syntax safety ('Value') for every item
						$ValuesString = ($InsertSlice | ForEach-Object {
							$RawCode = $_.ToString().Replace("(", "").Replace(")", "").Replace("'", "").Trim()
							"('$RawCode')"
						}) -join ","
						
						# Append this batch line to our overall script sequence
						[void]$SqlScriptBuilder.AppendLine("INSERT INTO ##BigCommerceList (StyleID) VALUES $ValuesString;")
					}

					# Append your final lookup query file directly to the very tail end of the transaction script
					Write-Host "Appending final comparison query script payload..." -ForegroundColor Cyan
					$FinalQueryText = Get-Content -Path $ScriptProductsNotInBC -Raw
					[void]$SqlScriptBuilder.AppendLine($FinalQueryText)

					# Base configuration parameters dictionary
					$QuerySqlParams = @{
						ServerInstance         = $config.Celerant.ServerInstance
						Database               = $config.Celerant.Database
						Username               = $config.Celerant.Username
						Password               = $config.Celerant.Password
						Query                  = $SqlScriptBuilder.ToString() # Hand over the whole unified script payload!
						Encrypt                = "Mandatory"
						TrustServerCertificate = $true
						QueryTimeout           = 600                          # Gives large comparisons plenty of execution time
					}

					Write-Host "Executing transaction on SQL Server (This may take a moment)..." -ForegroundColor Yellow
					
					# Fire everything off at once! The table creation, population, and final SELECT all run in 1 session.
					$FinalResults = Invoke-Sqlcmd @QuerySqlParams

					# Export data objects smoothly straight to your output destination
					if ($FinalResults) {
						$FinalResults | Export-Csv -Path $ProductsNotInBigCommerce -NoTypeInformation -Delimiter "," -Encoding utf8
						Write-Host "Success! Generated: $ProductsNotInBigCommerce" -ForegroundColor Green
					} else {
						Write-Warning "Comparison complete, but no missing products were found."
					}

				} else {
					Write-Warning "No product codes matched your Celerant Database during processing."
				}
			}
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
			$RowNum = 1
			
			foreach ($row in $RowsToProcess) {
				$Product = $row.Product
				$CleanName = $row.Name.Trim()
				$RowNum += 1
				
				if ($Product -ne $LastProduct) {
					if ($LastProduct.Trim() -ne "") {
						$LastProduct = $Product
					}
					
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
							$OptionsText = $OptionsText + "Type=Rectangle|Name=Size|Value=$($row.Size)"
						}
						
						if (-not [string]::IsNullOrWhiteSpace($row.width)) {
							$OptionsText = $OptionsText + "Type=Rectangle|Name=Width|Value=$($row.width)"
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
				$TransformedData | Export-Csv -Path $OutputFile -NoTypeInformation -Delimiter "," -Encoding utf8
				
				Write-Host "Export complete! Your file is ready for BigCommerce." -ForegroundColor Green
			} else {
				Write-Warning "No rows were processed, so no file was generated."
			}
		}
	}
} until ($selection -eq "5")

Pause
exit