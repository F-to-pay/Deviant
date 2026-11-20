<#
  Прогон всех тестов проекта и сравнение с эталонами (tests/golden/*.txt).

  Запуск:   powershell -ExecutionPolicy Bypass -File tests\run_all.ps1
            powershell -ExecutionPolicy Bypass -File tests\run_all.ps1 -Only unit_core,smoke
            powershell -ExecutionPolicy Bypass -File tests\run_all.ps1 -Update          # осознанно переписать эталоны
  Godot:    путь к консольному exe — параметр -Godot или переменная GODOT_BIN (иначе ищется godot в PATH).

  Виды тестов:
   · assert — сами печатают "SMOKE RESULT fails=0"; раннер проверяет ноль провалов и отсутствие ошибок скриптов;
   · golden — печатают «отпечаток» (строки SMOKE ...); раннер сравнивает с tests/golden/<имя>.txt. Эталон меняется только
     осознанно: если поведение изменилось намеренно, прогнать с -Update и посмотреть git diff эталонов.
  Окружение: на время прогона настройки игры подменяются каноническим user://deviant.cfg (язык en, отладчик модов включён), а
  ваш настоящий файл возвращается на место в конце (даже при ошибке). Эталоны привязаны к версии движка (генераторы карт и
  хэши зависят от Godot) и к содержимому data/ и Mods/ репозитория.
  Ограничение: скрипт для Windows (путь пользовательских данных — %APPDATA%\Godot\app_userdata).
#>
param(
    [string]$Godot = $env:GODOT_BIN,
    [switch]$Update,
    [string[]]$Only = @(),
    [int]$TimeoutSec = 900
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
if (-not $Godot) {
    $cmd = Get-Command godot*console* -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $cmd) { $cmd = Get-Command godot -ErrorAction SilentlyContinue | Select-Object -First 1 }
    if ($cmd) { $Godot = $cmd.Source }
}
if (-not $Godot -or -not (Test-Path $Godot)) {
    Write-Error "Не найден Godot. Укажите -Godot <путь к консольному exe> или переменную GODOT_BIN."
}

$ASSERT = @('unit_core', 'skip_zone', 'zone_source', 'mod_data', 'run_save')
$GOLDEN = @('smoke', 'ui_screens', 'ui_actions', 'gen_fingerprint', 'proj_fingerprint', 'player_state', 'controls_state',
    'console_commands', 'data_tables')
$all = $ASSERT + $GOLDEN
if ($Only.Count -gt 0) { $all = $all | Where-Object { $Only -contains $_ } }

$projName = ((Select-String -Path (Join-Path $root 'project.godot') -Pattern '^config/name="(.+)"').Matches[0].Groups[1].Value)
$userDir = Join-Path $env:APPDATA "Godot\app_userdata\$projName"
$cfg = Join-Path $userDir 'deviant.cfg'
$runSave = Join-Path $userDir 'run.save'
$goldenDir = Join-Path $PSScriptRoot 'golden'
New-Item -ItemType Directory -Force -Path $userDir, $goldenDir | Out-Null

$canonical = "[settings]`r`n`r`nlanguage=`"en`"`r`nmod_debug=true`r`n"
$backup = $null
if (Test-Path $cfg) { $backup = Get-Content -Raw -Path $cfg }
$saveBackup = $null
if (Test-Path $runSave) { $saveBackup = [IO.File]::ReadAllBytes($runSave) }
$rootFwd = ($root -replace '\\', '/')

# Вывод в сравнимый вид: только строки теста, без не-ASCII (консоль Windows портит юникод), без путей машины.
function Normalize([string[]]$lines) {
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($l in $lines) {
        if ($l -notmatch 'SMOKE |SCRIPT ERROR|Parse Error|Compile Error') { continue }
        $t = $l -replace [regex]::Escape($rootFwd), '<ROOT>' -replace [regex]::Escape($root), '<ROOT>'
        $t = [regex]::Replace($t, '[^\x09\x20-\x7E]', '').Trim()
        $t = $t -replace '^SMOKE STREAM-END$', ''
        if ($t -ne '') { $out.Add($t) }
    }
    return $out.ToArray()
}

function Run-Test([string]$name) {
    [IO.File]::WriteAllText($cfg, $canonical)   # каждый тест начинает с канонических настроек и без сейва забега
    Remove-Item $runSave -Force -ErrorAction SilentlyContinue
    $outFile = Join-Path $env:TEMP "deviant_test_$name.out"
    $errFile = Join-Path $env:TEMP "deviant_test_$name.err"
    $p = Start-Process -FilePath $Godot -ArgumentList @('--headless', '--path', "`"$root`"", '-s', "res://tests/$name.gd") `
        -NoNewWindow -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        try { $p.Kill() } catch {}
        $part = @()
        if (Test-Path $outFile) { $part += Get-Content -Path $outFile -Encoding UTF8 }
        if (Test-Path $errFile) { $part += Get-Content -Path $errFile -Encoding UTF8 }
        return @{ lines = $part; timeout = $true }
    }
    $lines = @()
    if (Test-Path $outFile) { $lines += Get-Content -Path $outFile -Encoding UTF8 }
    if (Test-Path $errFile) { $lines += Get-Content -Path $errFile -Encoding UTF8 }
    return @{ lines = $lines; timeout = $false }
}

$failed = @()
$started = Get-Date
try {
    # классы могли добавиться: обновить кэш глобальных классов, иначе новые class_name не видны
    & $Godot --headless --path $root --import 2>&1 | Out-Null
    foreach ($name in $all) {
        $t0 = Get-Date
        $r = Run-Test $name
        $norm = Normalize $r.lines
        $secs = [int]((Get-Date) - $t0).TotalSeconds
        $problems = @($norm | Where-Object { $_ -match 'SCRIPT ERROR|Parse Error|Compile Error' })
        if ($r.timeout) {
            Write-Host ("FAIL  {0,-18} timeout after {1}s (скрипт не вышел: ошибка компиляции или зависание)" -f $name, $TimeoutSec) -ForegroundColor Red
            $problems | Select-Object -First 5 | ForEach-Object { Write-Host "        $_" }
            $failed += $name
            continue
        }
        if ($problems.Count -gt 0) {
            Write-Host ("FAIL  {0,-18} script errors:" -f $name) -ForegroundColor Red
            $problems | Select-Object -First 5 | ForEach-Object { Write-Host "        $_" }
            $failed += $name
            continue
        }
        if ($ASSERT -contains $name) {
            $res = $norm | Where-Object { $_ -match 'SMOKE RESULT fails=' } | Select-Object -Last 1
            $bad = @($norm | Where-Object { $_ -match '^SMOKE FAIL' })
            if ($res -match 'fails=0' -and $bad.Count -eq 0) {
                Write-Host ("ok    {0,-18} {1}s" -f $name, $secs) -ForegroundColor Green
            } else {
                Write-Host ("FAIL  {0,-18} {1}" -f $name, $res) -ForegroundColor Red
                $bad | Select-Object -First 8 | ForEach-Object { Write-Host "        $_" }
                $failed += $name
            }
            continue
        }
        $goldenFile = Join-Path $goldenDir "$name.txt"
        if ($Update) {
            [IO.File]::WriteAllText($goldenFile, (($norm -join "`n") + "`n"))
            Write-Host ("upd   {0,-18} {1} lines, {2}s" -f $name, $norm.Count, $secs) -ForegroundColor Yellow
            continue
        }
        if (-not (Test-Path $goldenFile)) {
            Write-Host ("FAIL  {0,-18} нет эталона tests/golden/{0}.txt (запустите с -Update)" -f $name) -ForegroundColor Red
            $failed += $name
            continue
        }
        $want = (Get-Content -Path $goldenFile -Encoding UTF8)
        $diff = Compare-Object -ReferenceObject $want -DifferenceObject $norm -SyncWindow 0
        if (-not $diff -and $want.Count -eq $norm.Count) {
            Write-Host ("ok    {0,-18} {1} lines, {2}s" -f $name, $norm.Count, $secs) -ForegroundColor Green
        } else {
            Write-Host ("FAIL  {0,-18} отпечаток разошёлся с эталоном ({1} vs {2} строк)" -f $name, $want.Count, $norm.Count) -ForegroundColor Red
            $k = 0
            for ($i = 0; $i -lt [Math]::Max($want.Count, $norm.Count) -and $k -lt 3; $i++) {
                $a = if ($i -lt $want.Count) { $want[$i] } else { '<нет>' }
                $b = if ($i -lt $norm.Count) { $norm[$i] } else { '<нет>' }
                if ($a -ne $b) {
                    $k++
                    Write-Host ("        строка {0}:" -f ($i + 1))
                    Write-Host ("          было:  " + $a.Substring(0, [Math]::Min(150, $a.Length)))
                    Write-Host ("          стало: " + $b.Substring(0, [Math]::Min(150, $b.Length)))
                }
            }
            $failed += $name
        }
    }
}
finally {
    if ($null -ne $backup) { [IO.File]::WriteAllText($cfg, $backup) } elseif (Test-Path $cfg) { Remove-Item $cfg -Force }
    if ($null -ne $saveBackup) { [IO.File]::WriteAllBytes($runSave, $saveBackup) } else { Remove-Item $runSave -Force -ErrorAction SilentlyContinue }
}

$total = [int]((Get-Date) - $started).TotalSeconds
if ($failed.Count -gt 0) {
    Write-Host ("`nПровалено: {0} из {1} ({2}) за {3}s" -f $failed.Count, $all.Count, ($failed -join ', '), $total) -ForegroundColor Red
    exit 1
}
Write-Host ("`nВсе тесты прошли ({0}) за {1}s" -f $all.Count, $total) -ForegroundColor Green
exit 0

