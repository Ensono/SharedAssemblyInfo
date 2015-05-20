function Initialize-SharedAssemblyInfo {
  Param(
    [Parameter(Mandatory=$False)]
    [Switch]$RemoveComments = $False
    )
  process {
    $crlf = [System.Environment]::NewLine;

    $current = $PSScriptRoot;
    while ((-Not (Test-Path "$current\Solutions")) -Or ($current.Length -lt 4)) {
      $current = (Get-Item $current).Parent.FullName;
    }

    $solutions = "$current\Solutions";

    if (-Not (Test-Path $solutions)) {
      throw "Unable to find solutions directory.";
    }

    Write-Host -ForegroundColor Green "Found Solutions at $solutions";

    $sharedAssemblyInfo = Join-Path $solutions "SharedAssemblyInfo.cs";
    $assemblyInfoFragment = "<Compile Include=`"Properties\AssemblyInfo.cs`" />";
    $sharedAssemblyInfoFragment = "`t`t<Compile Include=`"{0}`">" + $crlf + "`t`t`t<Link>Properties\SharedAssemblyInfo.cs</Link>" + $crlf + "`t`t</Compile>";

    $sharedAttributes = Get-Content $sharedAssemblyInfo `
                | Where-Object { -not [String]::IsNullOrWhiteSpace($_) } `
                | Where-Object { -not $_.StartsWith("//") } `
                | Where-Object { -not $_.StartsWith("using") } `
                | ForEach-Object { $_.Split((' ', '('))[1] };

    if (Test-Path $sharedAssemblyInfo) {
      Write-Host -ForegroundColor Green "Found SharedAssemblyInfo.cs in $solutions";
    } else {
      throw "Could not find SharedAssemblyInfo.cs... exiting.";
    }

    $projects = (Get-ChildItem -Recurse $solutions *.csproj);

    foreach ($project in $projects) {
      $projectXml = [xml](Get-Content $project.VersionInfo.FileName);
      $assemblyInfo = ($projectXml.Project.ItemGroup `
                        | Where-Object { `
                          ($_.GetType().Name -eq "XmlElement") `
                          -And (($_.ChildNodes | Select-Object -Last 1).Name -eq "Compile")}).Compile.Include `
                        | Where-Object { $_.EndsWith("AssemblyInfo.cs") };

      if ($assemblyInfo | Where-Object { $_.EndsWith("SharedAssemblyInfo.cs")}) {
        Write-Host -ForegroundColor Green "  $project already contains SharedAssemblyInfo.cs";
      } else { 
        Write-Host -ForegroundColor Yellow -NoNewLine "  $project dosn't contain SharedAssemblyInfo.cs";

        Push-Location ($project.DirectoryName);
        $relativeSharedAssemblyPath = Resolve-Path -Relative $sharedAssemblyInfo; 
        Pop-Location;
        $projectFile = (Get-Content $project.VersionInfo.FileName);
        $projectFile = $projectFile.Replace($assemblyInfoFragment, $assemblyInfoFragment + $crlf + ($sharedAssemblyInfoFragment -f $relativeSharedAssemblyPath));
        Set-Content -Path $project.VersionInfo.FileName $projectFile;

        Write-Host -ForegroundColor Green "... added.";
      }

      $assemblyInfoPath = (Join-Path $project.DirectoryName "properties/AssemblyInfo.cs");
      $assemblyInfo = Get-Content $assemblyInfoPath;
      $newAssemblyInfo = New-Object System.Text.StringBuilder ;

      Write-Host -ForegroundColor White "    Inspecting AssemblyInfo.cs in $project"
      $previousLine = "";

      foreach ($line in $assemblyInfo) {
        $found = $False;

        foreach ($attribute in $sharedAttributes) {
          if ($line.StartsWith("[assembly: $attribute")) {
            Write-Host -ForegroundColor Yellow "      Removing shared attribute: $attribute"
            $found = $True;
          } 
        }

        if (-not $found) {
          if ($RemoveComments -and $line.StartsWith("//")) {
            continue;
          }

          if ([String]::IsNullOrWhiteSpace($line) -and [String]::IsNullOrWhiteSpace($previousLine)) {
            continue; 
          }

          $newAssemblyInfo.AppendLine($line) | Out-Null;
        }

        $previousLine = $line;
      }

      Set-Content -Path $assemblyInfoPath -Value $newAssemblyInfo.ToString().Trim() -Encoding UTF8;
    }
  }
}

Initialize-SharedAssemblyInfo -RemoveComments