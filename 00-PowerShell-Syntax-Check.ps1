#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$files = @(Get-ChildItem -LiteralPath $PSScriptRoot -Recurse -File -Filter '*.ps1')
$errorsFound = New-Object System.Collections.Generic.List[object]

foreach ($file in $files) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $file.FullName,
        [ref]$tokens,
        [ref]$errors
    )

    foreach ($err in @($errors)) {
        $errorsFound.Add([pscustomobject]@{
            File = $file.FullName
            Line = $err.Extent.StartLineNumber
            Column = $err.Extent.StartColumnNumber
            ErrorId = $err.ErrorId
            Message = $err.Message
            Text = $err.Extent.Text
        })
    }
}

if ($errorsFound.Count -gt 0) {
    foreach ($e in $errorsFound) {
        Write-Host ("{0}:{1}:{2}: {3} ({4})" -f $e.File,$e.Line,$e.Column,$e.Message,$e.ErrorId) -ForegroundColor Red
        if ($e.Text) { Write-Host ("  " + $e.Text) -ForegroundColor DarkRed }
    }
    exit 91
}

exit 0
