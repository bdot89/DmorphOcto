# Runs tests/run_tests.lua on Windows without a Lua interpreter: builds
# tools\LuaHost (needs the .NET 8 SDK) and runs the tests through it.
#   powershell -ExecutionPolicy Bypass -File tools\run_tests.ps1
$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$host_ = Join-Path $PSScriptRoot "LuaHost"
$exe = Join-Path $host_ "bin\LuaHost.exe"
$newest = Get-ChildItem $host_ -Include *.cs, *.csproj -Recurse | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not (Test-Path $exe) -or (Get-Item $exe).LastWriteTime -lt $newest.LastWriteTime) {
  dotnet build $host_ -c Release -o (Join-Path $host_ "bin") --nologo -v quiet | Out-Host
  if ($LASTEXITCODE -ne 0) { throw "LuaHost build failed" }
}
Push-Location $root
try { & $exe "tests/run_tests.lua"; exit $LASTEXITCODE } finally { Pop-Location }
