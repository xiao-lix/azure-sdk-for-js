# This script is intended to update docs.ms CI configuration (currently supports Java, Python, C#, JS) in nightly build
# For details on calling, check `docindex.yml`. 

# In this script, we will do the following business logic.
# 1. Filter out the packages from release csv file by `New=true`, `Hide!=true`
# 2. Compare current package list with the csv packages, and keep them in sync. Leave other packages as they are.
# 3. Update the tarage packages back to CI config files. 
param (
  [Parameter(Mandatory = $true)]
  $DocRepoLocation # the location of the cloned doc repo
)

. (Join-Path $PSScriptRoot common.ps1)

function GetDocsMetadataForMoniker($moniker) { 
  $searchPath = Join-Path $DocRepoLocation 'metadata' $moniker
  if (!(Test-Path $searchPath)) { 
    return @() 
  }
  $paths = Get-ChildItem -Path $searchPath -Filter *.json

  $metadata = @() 
  foreach ($path in $paths) { 
    $fileContents = Get-Content $path -Raw
    $fileObject = ConvertFrom-Json -InputObject $fileContents
    $versionGa = ''
    $versionPreview = '' 
    if ($moniker -eq 'latest') { 
      $versionGa = $fileObject.Version
    } else { 
      $versionPreview = $fileObject.Version
    }

    $metadata += @{ 
      Package = $fileObject.Name; 
      VersionGA = $versionGa;
      VersionPreview = $versionPreview;
      RepoPath = $fileObject.ServiceDirectory;
      Type = $fileObject.SdkType;
      New = $fileObject.IsNewSdk;
    }
  }

  return $metadata
}
function GetDocsMetadata() {
  # Read metadata from CSV
  $csvMetadata = (Get-CSVMetadata).Where({ $_.New -eq 'true' -and $_.Hide -ne 'true' })

  # Read metadata from docs repo
  $metadataByPackage = @{}
  foreach ($package in GetDocsMetadataForMoniker 'latest') { 
    if ($metadataByPackage.ContainsKey($package.Package)) { 
      LogWarning "Duplicate package in latest metadata: $($package.Package)"
    }
    $metadataByPackage[$package.Package] = $package
  }

  foreach ($package in GetDocsMetadataForMoniker 'preview') {
    if ($metadataByPackage.ContainsKey($package.Package)) {
      # Merge VersionPreview of each object
      $metadataByPackage[$package.Package].VersionPreview = $package.VersionPreview
    } else { 
      $metadataByPackage[$package.Package] = $package
    }
  }

  # Override CSV metadata version information before returning
  $outputMetadata = @()
  foreach ($item in $csvMetadata) { 
    if ($metadataByPackage.ContainsKey($item.Package)) {
      Write-Host "Overriding CSV metadata from docs repo for $($item.Package)"
      $matchingPackage = $metadataByPackage[$item.Package]
      # TODO: Only mutate the verison if there is a version update?
      if ($matchingPackage.VersionGA) {
        $item.VersionGA = $matchingPackage.VersionGA
      }
      if ($matchingPackage.VersionPreview) { 
        $item.VersionPreview = $matchingPackage.VersionPreview
      }
    }
    $outputMetadata += $item
  }

  return $outputMetadata
}

if ($UpdateDocsMsPackagesFn -and (Test-Path "Function:$UpdateDocsMsPackagesFn")) {

  try {
    $docsMetadata = GetDocsMetadata
    &$UpdateDocsMsPackagesFn -DocsRepoLocation $DocRepoLocation -DocsMetadata $docsMetadata
  } catch { 
    LogError "Exception while updating docs.ms packages"
    LogError $_ 
    LogError $_.ScriptStackTrace
    exit 1
  }
  
} else {
  LogError "The function for '$UpdateFn' was not found.`
  Make sure it is present in eng/scripts/Language-Settings.ps1 and referenced in eng/common/scripts/common.ps1.`
  See https://github.com/Azure/azure-sdk-tools/blob/master/doc/common/common_engsys.md#code-structure"
  exit 1
}
