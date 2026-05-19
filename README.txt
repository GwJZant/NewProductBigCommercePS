NewProductBigCommercePS
Created by: David Barnes
Requirements: ImportExcel, SqlServer

*******************************************************************************
* To use this tool you need to install the ImportExcel and SqlServer modules. *
* All you need to do is run the below commands in Powershell.                 *
* It does not require Administrator credentials.                              *
*                                                                             *
* Install-Module -Name ImportExcel -Scope CurrentUser -Force                  *     
* Install-Module -Name SqlServer -Scope CurrentUser -Force                    *
*******************************************************************************

This is a conversion of the NewProductBigCommerce.bat tool to a PowerShell script. The README for that script should still be accurate:

Link: https://docs.google.com/document/d/1KQpJjEAmqLumo8iFNzXuyDnqmMzy7cYo3Tvp9uTRSHE/edit?usp=sharing

HOW TO RUN:
Right-click NewProductBigCommercePS.ps1 and select "Run with PowerShell"

Alternatively, Shift + Right-click anywhere in the folder (don't Shift + Right-click the file itself) and select "Open PowerShell window here" to open a PowerShell window first. This will make it so the command prompt window won't close as soon as this tool finishes which will let you inspect the output if you wish. To run the script with this method, type (or copy and paste) the following:

./NewProductBigCommercePS.ps1

HOW TO INSTALL MODULES:
Open PowerShell by searching for it with the Start menu or shift + right-click the whitespace of any folder's window and click "Open PowerShell window here"
Copy and paste the Install-Module commands into PowerShell. If the modules are already installed, they will be ignored.