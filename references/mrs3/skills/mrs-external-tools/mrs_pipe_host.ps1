<#
  mrs_pipe_host.ps1  --  MRS external tool resident pipe host (multi-instance).

  GENERIC, REUSABLE SCRIPT. It ships with this skill and lives in the skill
  directory (the directory that contains SKILL.md). It is meant to be CALLED,
  never regenerated, overwritten or rewritten during a workflow.

  Role
    Start ONE tool instance with /pipe (that instance's only launch in the whole
    workflow), keep its stdin open, expose a named pipe for the sender process,
    forward every command line to that instance's stdin, write its stdout back
    to the pipe, and record everything to the instance result file.

    One host process = one tool instance. Start several hosts only when the
    parameter manual shows that a single instance cannot cover the requirement
    (for example the tool can only open one port / one device / one link at a
    time); give each of them a distinct -Instance name. Every instance is still
    launched exactly once and stays resident until the workflow ends.

    Health reporting: the host keeps mrs_pipe_stateSUFFIX.json up to date so the
    orchestrator can tell a healthy instance from a process that died before
    readiness (for example when security software blocks the script or the tool):
      starting -> tool-started -> ready -> exited   (error carries a reason)
    A kill can never be caught inside this process; the phase file left behind is
    what lets the caller detect it and decide to reset and retry once.

  Launch (relative -File + -WorkingDirectory keeps paths with spaces safe;
  -ArgumentList is never asked to carry a path):
    Start-Process pwsh -WorkingDirectory $ScriptDir `
        -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File','mrs_pipe_host.ps1','-Instance','a') `
        -WindowStyle Hidden -PassThru
    (use powershell.exe instead of pwsh when only Windows PowerShell 5.1 exists)

  Parameters (all optional; resolution order: parameter -> environment -> default)
    -Exe                 tool executable (full path)
                         -> $env:MRS_PIPE_EXE_<INSTANCE> -> $env:MRS_PIPE_EXE
                         -> the single *.exe beside this script
    -WorkDir             writable coordination directory
                         -> $env:MRS_PIPE_WORKDIR -> <TEMP>\mrs_pipe
    -Instance            instance name ([A-Za-z0-9_-]); empty = single instance
                         mode, whose file names stay the historical ones
    -HostTimeoutSec      host lifetime cap, default 3600 (anti process-leak backstop)
    -HandshakeTimeoutSec max wait for the startup handshake line, default 20
                         (a timeout is only logged, it never aborts the flow)
    -ResponseTimeoutMs   max wait for one command response, default 60000

  Files written into -WorkDir (SUFFIX is '' for the single instance mode,
  otherwise '.' plus the instance name):
    mrs_pipe_readySUFFIX.json   readiness marker: pipe name + instance + PIDs
    mrs_pipe_stateSUFFIX.json   lifecycle phase: starting / tool-started / ready / exited / error
    mrs_pipe_resultSUFFIX.txt   append-only log of ">> command" / "<< response"
    mrs_pipe_stopSUFFIX.flag    created by the orchestrator to end this instance
#>
param(
    [string]$Exe,
    [string]$WorkDir,
    [string]$Instance,
    [int]$HostTimeoutSec = 3600,
    [int]$HandshakeTimeoutSec = 20,
    [int]$ResponseTimeoutMs = 60000
)
$ErrorActionPreference = 'Continue'

# ---------- 0) resolve parameters: parameter -> environment -> default ----------
$Instance = if ($null -eq $Instance) { '' } else { $Instance.Trim() }
if ($Instance -ne '' -and $Instance -notmatch '^[A-Za-z0-9_-]+$') {
    throw "Invalid -Instance '$Instance': use only letters, digits, '-' and '_'."
}
$suffix = ''
if ($Instance -ne '') { $suffix = '.' + $Instance }

if (-not $Exe -or $Exe.Trim() -eq '') {
    $scopedExe = ''
    if ($Instance -ne '') {
        $scopedKey = 'MRS_PIPE_EXE_' + (($Instance -replace '[^A-Za-z0-9]', '_').ToUpper())
        $scopedExe = [Environment]::GetEnvironmentVariable($scopedKey)
    }
    if ($scopedExe -and $scopedExe.Trim() -ne '') {
        $Exe = $scopedExe
    } elseif ($env:MRS_PIPE_EXE -and $env:MRS_PIPE_EXE.Trim() -ne '') {
        $Exe = $env:MRS_PIPE_EXE
    } else {
        $cand = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.exe' -File -ErrorAction SilentlyContinue)
        if ($cand.Count -eq 1) {
            $Exe = $cand[0].FullName
        } else {
            throw "Exe not specified and not auto-detectable beside '$PSScriptRoot' (found $($cand.Count) .exe). Set `$env:MRS_PIPE_EXE or -Exe."
        }
    }
}
if (-not (Test-Path -LiteralPath $Exe)) { throw "Exe not found: $Exe" }

if (-not $WorkDir -or $WorkDir.Trim() -eq '') {
    if ($env:MRS_PIPE_WORKDIR -and $env:MRS_PIPE_WORKDIR.Trim() -ne '') {
        $WorkDir = $env:MRS_PIPE_WORKDIR
    } else {
        $WorkDir = Join-Path ([System.IO.Path]::GetTempPath()) 'mrs_pipe'
    }
}
if (-not (Test-Path -LiteralPath $WorkDir)) { New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null }

$script:enc        = New-Object System.Text.UTF8Encoding($false)
$script:proc       = $null
$script:pending    = $null          # single pending ReadLineAsync task (single reader rule)
$script:handshake  = $false
$script:stopAsked  = $false

if ($Instance -ne '') {
    $pipeName = "mrs_pipe_${Instance}_$PID"
} else {
    $pipeName = "mrs_pipe_$PID"
}
$readyFile         = Join-Path $WorkDir ("mrs_pipe_ready$suffix.json")
$script:stateFile  = Join-Path $WorkDir ("mrs_pipe_state$suffix.json")
$script:resultFile = Join-Path $WorkDir ("mrs_pipe_result$suffix.txt")
$stopFile          = Join-Path $WorkDir ("mrs_pipe_stop$suffix.flag")

# One host per instance: refuse to start a second host for an instance that is
# still alive, otherwise the two hosts would fight over the same marker files.
# This check stays OUTSIDE the try/catch below: it must never overwrite the
# phase file of the instance that is still running.
if (Test-Path -LiteralPath $readyFile) {
    $prev = $null
    try { $prev = Get-Content -LiteralPath $readyFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $prev = $null }
    $prevAlive = $false
    if ($prev -and $prev.hostPid) {
        $prevProc = Get-Process -Id ([int]$prev.hostPid) -ErrorAction SilentlyContinue
        if ($prevProc) {
            # HasExited is authoritative: a killed process can linger in the
            # process table and must not block a legitimate restart.
            try { $prevAlive = -not $prevProc.HasExited } catch { $prevAlive = $true }
        }
    }
    if ($prevAlive) {
        throw "Instance '$Instance' is already running (hostPid $($prev.hostPid), pipe $($prev.pipe)). Stop that instance before starting a new one."
    }
    Remove-Item -LiteralPath $readyFile -Force -ErrorAction SilentlyContinue
}
Remove-Item -LiteralPath $script:resultFile,$stopFile,$script:stateFile -Force -ErrorAction SilentlyContinue

function Add-Result([string]$line) {
    try { [System.IO.File]::AppendAllText($script:resultFile, $line + [Environment]::NewLine, $script:enc) } catch { }
}
function Set-State([string]$phase, [string]$detail) {
    try {
        $json = @{ instance = $Instance; phase = $phase; hostPid = $PID;
                   toolPid = $(if ($script:proc) { $script:proc.Id } else { 0 });
                   pipe = $pipeName; exe = $Exe; workDir = $WorkDir; detail = $detail;
                   updated = (Get-Date).ToString('s') } | ConvertTo-Json -Compress
        # .NET write keeps the file UTF-8 without BOM on both PS 5.1 and PS 7+
        [System.IO.File]::WriteAllText($script:stateFile, $json, $script:enc)
    } catch { }
}
function Write-Tool([string]$cmd) {
    $b = $script:enc.GetBytes($cmd + "`n")
    $script:proc.StandardInput.BaseStream.Write($b, 0, $b.Length)
    $script:proc.StandardInput.BaseStream.Flush()
}
# One reader only: always reuse the same pending ReadLineAsync task so that a
# timed-out read never races with a later read on the same stream.
function Read-ToolLine([int]$timeoutMs) {
    if ($null -eq $script:pending) {
        try { $script:pending = $script:proc.StandardOutput.ReadLineAsync() } catch { return $null }
    }
    try {
        if ($script:pending.Wait($timeoutMs)) {
            $line = $script:pending.Result
            $script:pending = $null
            return $line
        }
    } catch {
        $script:pending = $null
        return $null
    }
    return $null
}

Set-State 'starting' 'host process started, tool not launched yet'

try {
    # ---------- 1) start this instance once, with /pipe, stdin kept open ----------
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = $Exe
    $psi.Arguments              = '/pipe'
    $psi.RedirectStandardInput  = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $false      # not redirected: avoids a full stderr buffer blocking the child
    $psi.UseShellExecute        = $false
    $psi.CreateNoWindow         = $true
    $script:proc = [System.Diagnostics.Process]::Start($psi)
    Add-Result "START: $Exe (pid $($script:proc.Id), instance '$Instance')"
    Set-State 'tool-started' "tool pid $($script:proc.Id)"

    # ---------- 2) align the startup handshake line (never aborts on timeout) ----------
    $first = Read-ToolLine ($HandshakeTimeoutSec * 1000)
    if ($null -ne $first) {
        Add-Result "HANDSHAKE: $first"
        $script:handshake = $true
    } else {
        Add-Result "HANDSHAKE: (timeout ${HandshakeTimeoutSec}s)"
    }
    # A tool that is already gone before readiness means this launch is a failure
    # (typical for a security-software block); never publish a ready marker then.
    if ($script:proc.HasExited) {
        throw "Tool exited before readiness (exit code $($script:proc.ExitCode)); no ready marker was published."
    }

    # ---------- 3) named pipe server + readiness marker ----------
    $server = [System.IO.Pipes.NamedPipeServerStream]::new(
        $pipeName,
        [System.IO.Pipes.PipeDirection]::InOut,
        1,
        [System.IO.Pipes.PipeTransmissionMode]::Byte,
        [System.IO.Pipes.PipeOptions]::Asynchronous)

    $readyJson = @{ pipe = $pipeName; instance = $Instance; hostPid = $PID; toolPid = $script:proc.Id; exe = $Exe; workDir = $WorkDir;
                    started = (Get-Date).ToString('s') } | ConvertTo-Json -Compress
    [System.IO.File]::WriteAllText($readyFile, $readyJson, $script:enc)
    Set-State 'ready' "pipe $pipeName"

    # ---------- 4) serve senders: forward commands, return responses ----------
    $deadline    = (Get-Date).AddSeconds($HostTimeoutSec)
    $connectTask = $null
    while ((Get-Date) -lt $deadline -and $script:proc -and -not $script:proc.HasExited `
           -and -not (Test-Path -LiteralPath $stopFile) -and -not $script:stopAsked) {

        if ($null -eq $connectTask) { $connectTask = $server.WaitForConnectionAsync() }
        if (-not $connectTask.Wait(1000)) { continue }        # 1s short poll, no long fixed sleep
        $connectTask = $null

        $reader = New-Object System.IO.StreamReader($server, $script:enc)
        $writer = New-Object System.IO.StreamWriter($server, $script:enc)
        $writer.AutoFlush = $true
        try { $writer.WriteLine('{"status":"connected"}') } catch { }

        while ($server.IsConnected) {
            $cmd = $null
            try { $cmd = $reader.ReadLine() } catch { break }
            if ($null -eq $cmd) { break }
            if ($cmd.Trim() -eq '') { continue }

            # Late handshake: resolve it before the first command so responses stay aligned.
            if (-not $script:handshake) {
                $late = Read-ToolLine 800
                if ($null -ne $late) { Add-Result "HANDSHAKE(late): $late" }
                $script:handshake = $true
            }

            if ($cmd.Trim() -eq '/stop') { $script:stopAsked = $true; break }

            Write-Tool $cmd
            Add-Result ">> $cmd"

            $resp = Read-ToolLine $ResponseTimeoutMs
            if ($null -eq $resp) {
                if ($script:proc.HasExited) {
                    Add-Result "<< (tool exited, code $($script:proc.ExitCode))"
                    break
                }
                $resp = '{"status":"timeout"}'
                Add-Result "<< (timeout ${ResponseTimeoutMs}ms)"
            } else {
                Add-Result "<< $resp"
            }
            try { $writer.WriteLine($resp) } catch { break }
        }
        try { $server.Disconnect() } catch { }
    }

    # ---------- 5) shutdown: close stdin first, never leave a zombie ----------
    Add-Result "HOST: exiting (instance '$Instance', stopFlag=$(Test-Path -LiteralPath $stopFile), stopAsked=$($script:stopAsked), toolExited=$($script:proc.HasExited))"
    Set-State 'exited' "stopFlag=$(Test-Path -LiteralPath $stopFile); stopAsked=$($script:stopAsked); toolExited=$($script:proc.HasExited)"
    try { $script:proc.StandardInput.Close() } catch { }
    try { if (-not $script:proc.WaitForExit(8000)) { $script:proc.Kill() } } catch { }
    try { $server.Dispose() } catch { }
    Remove-Item -LiteralPath $readyFile -Force -ErrorAction SilentlyContinue
}
catch {
    # Terminating failure: record the reason, clean up the child, remove the
    # readiness marker so the caller never sees a half-ready instance, rethrow.
    Add-Result "HOST-ERROR: $($_.Exception.Message)"
    Set-State 'error' $_.Exception.Message
    try { $script:proc.StandardInput.Close() } catch { }
    try { if ($script:proc -and -not $script:proc.HasExited) { $script:proc.Kill() } } catch { }
    Remove-Item -LiteralPath $readyFile -Force -ErrorAction SilentlyContinue
    throw
}

# SIG # Begin signature block
# MIIqHAYJKoZIhvcNAQcCoIIqDTCCKgkCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBJyLObogfGzdvq
# 4su/NSNnnzGrl89NPrgWr7QOeZWgjKCCDtEwggawMIIEmKADAgECAhAIrUCyYNKc
# TJ9ezam9k67ZMA0GCSqGSIb3DQEBDAUAMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQK
# EwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNV
# BAMTGERpZ2lDZXJ0IFRydXN0ZWQgUm9vdCBHNDAeFw0yMTA0MjkwMDAwMDBaFw0z
# NjA0MjgyMzU5NTlaMGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwg
# SW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBDb2RlIFNpZ25pbmcg
# UlNBNDA5NiBTSEEzODQgMjAyMSBDQTEwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAw
# ggIKAoICAQDVtC9C0CiteLdd1TlZG7GIQvUzjOs9gZdwxbvEhSYwn6SOaNhc9es0
# JAfhS0/TeEP0F9ce2vnS1WcaUk8OoVf8iJnBkcyBAz5NcCRks43iCH00fUyAVxJr
# Q5qZ8sU7H/Lvy0daE6ZMswEgJfMQ04uy+wjwiuCdCcBlp/qYgEk1hz1RGeiQIXhF
# LqGfLOEYwhrMxe6TSXBCMo/7xuoc82VokaJNTIIRSFJo3hC9FFdd6BgTZcV/sk+F
# LEikVoQ11vkunKoAFdE3/hoGlMJ8yOobMubKwvSnowMOdKWvObarYBLj6Na59zHh
# 3K3kGKDYwSNHR7OhD26jq22YBoMbt2pnLdK9RBqSEIGPsDsJ18ebMlrC/2pgVItJ
# wZPt4bRc4G/rJvmM1bL5OBDm6s6R9b7T+2+TYTRcvJNFKIM2KmYoX7BzzosmJQay
# g9Rc9hUZTO1i4F4z8ujo7AqnsAMrkbI2eb73rQgedaZlzLvjSFDzd5Ea/ttQokbI
# YViY9XwCFjyDKK05huzUtw1T0PhH5nUwjewwk3YUpltLXXRhTT8SkXbev1jLchAp
# QfDVxW0mdmgRQRNYmtwmKwH0iU1Z23jPgUo+QEdfyYFQc4UQIyFZYIpkVMHMIRro
# OBl8ZhzNeDhFMJlP/2NPTLuqDQhTQXxYPUez+rbsjDIJAsxsPAxWEQIDAQABo4IB
# WTCCAVUwEgYDVR0TAQH/BAgwBgEB/wIBADAdBgNVHQ4EFgQUaDfg67Y7+F8Rhvv+
# YXsIiGX0TkIwHwYDVR0jBBgwFoAU7NfjgtJxXWRM3y5nP+e6mK4cD08wDgYDVR0P
# AQH/BAQDAgGGMBMGA1UdJQQMMAoGCCsGAQUFBwMDMHcGCCsGAQUFBwEBBGswaTAk
# BggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tMEEGCCsGAQUFBzAC
# hjVodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkUm9v
# dEc0LmNydDBDBgNVHR8EPDA6MDigNqA0hjJodHRwOi8vY3JsMy5kaWdpY2VydC5j
# b20vRGlnaUNlcnRUcnVzdGVkUm9vdEc0LmNybDAcBgNVHSAEFTATMAcGBWeBDAED
# MAgGBmeBDAEEATANBgkqhkiG9w0BAQwFAAOCAgEAOiNEPY0Idu6PvDqZ01bgAhql
# +Eg08yy25nRm95RysQDKr2wwJxMSnpBEn0v9nqN8JtU3vDpdSG2V1T9J9Ce7FoFF
# UP2cvbaF4HZ+N3HLIvdaqpDP9ZNq4+sg0dVQeYiaiorBtr2hSBh+3NiAGhEZGM1h
# mYFW9snjdufE5BtfQ/g+lP92OT2e1JnPSt0o618moZVYSNUa/tcnP/2Q0XaG3Ryw
# YFzzDaju4ImhvTnhOE7abrs2nfvlIVNaw8rpavGiPttDuDPITzgUkpn13c5Ubdld
# AhQfQDN8A+KVssIhdXNSy0bYxDQcoqVLjc1vdjcshT8azibpGL6QB7BDf5WIIIJw
# 8MzK7/0pNVwfiThV9zeKiwmhywvpMRr/LhlcOXHhvpynCgbWJme3kuZOX956rEnP
# LqR0kq3bPKSchh/jwVYbKyP/j7XqiHtwa+aguv06P0WmxOgWkVKLQcBIhEuWTatE
# QOON8BUozu3xGFYHKi8QxAwIZDwzj64ojDzLj4gLDb879M4ee47vtevLt/B3E+bn
# KD+sEq6lLyJsQfmCXBVmzGwOysWGw/YmMwwHS6DTBwJqakAwSEs0qFEgu60bhQji
# WQ1tygVQK+pKHJ6l/aCnHwZ05/LWUpD9r4VIIflXO7ScA+2GRfS0YW6/aOImYIbq
# yK+p/pQd52MbOoZWeE4wgggZMIIGAaADAgECAhALjH3AYnDqHkWPMWmzjmIXMA0G
# CSqGSIb3DQEBCwUAMGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwg
# SW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBDb2RlIFNpZ25pbmcg
# UlNBNDA5NiBTSEEzODQgMjAyMSBDQTEwHhcNMjYwMzA0MDAwMDAwWhcNMjcwMzAz
# MjM1OTU5WjCCASAxEzARBgsrBgEEAYI3PAIBAxMCQ04xGDAWBgsrBgEEAYI3PAIB
# AhMHSmlhbmdzdTEYMBYGCysGAQQBgjc8AgEBEwdOYW5qaW5nMR0wGwYDVQQPDBRQ
# cml2YXRlIE9yZ2FuaXphdGlvbjEbMBkGA1UEBRMSOTEzMjAxMTQ3NjIxMDUwODdC
# MQswCQYDVQQGEwJDTjEQMA4GA1UECBMHSmlhbmdzdTEQMA4GA1UEBxMHTmFuamlu
# ZzEzMDEGA1UEChMqTmFuamluZyBRaW5oZW5nIE1pY3JvZWxlY3Ryb25pY3MgQ28u
# LCBMdGQuMTMwMQYDVQQDEypOYW5qaW5nIFFpbmhlbmcgTWljcm9lbGVjdHJvbmlj
# cyBDby4sIEx0ZC4wggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQClpnev
# GiTwZLo0vTb3IvY76x2P2rBlDbCaqL7tnh4dAlnFaOfRqKeHdK4jqjPTp1FaRm+Z
# IkWOdkNwqtEiv67qYTB6IOeVkS83HVc9o+U7yWZNFUs2UUUElXBHr9ZUC2+mSYOP
# rcWd9p5nDNJK703gxBhVoDuSATBkYYJues546t3506OQz3eiaI2yVxwD/aH6ajOe
# GGDObVS3UREGGy8Y71Uo1PMPG6vri+QxRpQOJz1bGmbLDP7HDYpAiwX6rABBrdxm
# A5/g6McMCTRETiYGoge9Cmuy+WLGiaHxYNcQPP9nCyNzGQ6sQhFrFc+ogTlp8TGr
# wYCwdJVKaTBO6Rf8Y/T6xsKDPb+mjAUujZrRgOmvZA7I45tE6RQY6COL+VMpB/cG
# ZboPBoFu7RDhUGHrC/0iBkqHlO1Mnfl94oAe/eMKR6H69E1wbGYSclsD/YOL30RQ
# /HnJZbrEdfgOHeclrt+3zmb+lSPViRV/1lrdQdZhha46r4tZSz/fUk7EH2enrEMT
# ZzHeO2DCXJqf9Q2I+z94VB4X9bLbe5egVs4qUT0Vx2M2NPDvZ22fSZk/+pN9E+4K
# 3gc2JwpU14MH8Rc98Lk4S8nPC9pr7BRjsxNjoh8f0uePl70eml3kosKm2HkyK15t
# Zo/oCuWjq3zjaGWAS8tVZ98diOvgrLN/rYPpwQIDAQABo4ICAjCCAf4wHwYDVR0j
# BBgwFoAUaDfg67Y7+F8Rhvv+YXsIiGX0TkIwHQYDVR0OBBYEFILbxvoa2KmiauIL
# zSfMDMYcbpMZMD0GA1UdIAQ2MDQwMgYFZ4EMAQMwKTAnBggrBgEFBQcCARYbaHR0
# cDovL3d3dy5kaWdpY2VydC5jb20vQ1BTMA4GA1UdDwEB/wQEAwIHgDATBgNVHSUE
# DDAKBggrBgEFBQcDAzCBtQYDVR0fBIGtMIGqMFOgUaBPhk1odHRwOi8vY3JsMy5k
# aWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkRzRDb2RlU2lnbmluZ1JTQTQwOTZT
# SEEzODQyMDIxQ0ExLmNybDBToFGgT4ZNaHR0cDovL2NybDQuZGlnaWNlcnQuY29t
# L0RpZ2lDZXJ0VHJ1c3RlZEc0Q29kZVNpZ25pbmdSU0E0MDk2U0hBMzg0MjAyMUNB
# MS5jcmwwgZQGCCsGAQUFBwEBBIGHMIGEMCQGCCsGAQUFBzABhhhodHRwOi8vb2Nz
# cC5kaWdpY2VydC5jb20wXAYIKwYBBQUHMAKGUGh0dHA6Ly9jYWNlcnRzLmRpZ2lj
# ZXJ0LmNvbS9EaWdpQ2VydFRydXN0ZWRHNENvZGVTaWduaW5nUlNBNDA5NlNIQTM4
# NDIwMjFDQTEuY3J0MAkGA1UdEwQCMAAwDQYJKoZIhvcNAQELBQADggIBABOjVli1
# b8dFYal1yrYaa+EC24I9qvAaGd1LANQJF2+Es72AdzN7WwgNmlcb3jyrFNJ63snv
# hAou6yvYTY6KVoyfkNBdylEWyQJuWKrwmfFQMzH8vw8doMcCA672ELjFwN6n4Ya8
# Xxn2FoV4Y2MK8uy8fpz9jSXR+P0SeMPujihB19UpSFPLmmGtfE8Bl7eYm3BjUtGr
# FDBbVEMC/JDJJDWUDD4bdf8/Iq5/VN0/hbfKWdZhZkKfj/aAxpj6jS3bWRCjTZIb
# /Hr2Z/j3a7PVdbUyTYbiYD6blJfUCdoTZXXymTiXkZNFzJv4TN7+lGaW0fsSr0pQ
# oOK/YjzLCEsw7cQrIXN4NDip/RIdmyE2Ny2r9og2HmLsL6a+2DJYNX0qD7aRzqgK
# CLOAywVYXwimyRFV9Asp0dPLkV58i6foqvOEx7yANlJ2u16HqgyEiKPE+BlsZMyV
# j1ZV2uHGHVtzBfcG9ahgBEKDSjwJCIVTfhU+kJ9Q/NqZoR06nvwJbEyNESI3plTz
# Z6eXAmBVvkOIfKW3yvrQ+BxdEp9q9uMzmkl3JkNfcEdRAMAAJgZzZcEdhvvDCGpL
# HGJQpZVHRV5z9nB12oOMxBKVMmE2XocDedpk9V1Xa0NmtOvwC6+Sp8+mB2ER9WHL
# XspyEsA+dpAHRHAYUViFvybRrjzZWfY2eu0sMYIaoTCCGp0CAQEwfTBpMQswCQYD
# VQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4xQTA/BgNVBAMTOERpZ2lD
# ZXJ0IFRydXN0ZWQgRzQgQ29kZSBTaWduaW5nIFJTQTQwOTYgU0hBMzg0IDIwMjEg
# Q0ExAhALjH3AYnDqHkWPMWmzjmIXMA0GCWCGSAFlAwQCAQUAoHwwEAYKKwYBBAGC
# NwIBDDECMAAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGCNwIB
# CzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIF7NioeRFJWYgYgfLa6a
# b68T0y7xpbHLnhi0WtTvH+dTMA0GCSqGSIb3DQEBAQUABIICAFXGq8QJOfG4rc7+
# VkF9eWY6Yoq/iUKjMx7ze358xFJCoME+RDr9bii3hLPQFd/PL91iuVwT6n7cUXfr
# YoJ6oVf9DCjN4VJSuMahJvILrnazirAhSq3x1GW4GRcCvWAxpQdarAAlEKaAAyce
# kbNfLFlELg9DKZqMf2+ZUb+GbeSCd7D1mgdZ62/OeIX9xH3JbztG0O1Lf33PyzPB
# NRE+d6spvMq/3qcgj71wvO8ce+0cC4l1nhxIgLoOvd534x7jPip1X9e8nRrPTNt/
# pj7UOeb00pQUvuUIgu+TiHPc3MfPekAOVnRQ4iP8jurd4Tb/sypVDWIDwsxoD3bv
# YjPOhcDb19cdHKEMNeV8FW2atNTjTBnw3wDvy6sluzujdxBQUcmjXJeGkxukuEDh
# aWnTlmzHIQJ1lhBxeBvGS6Msa8zVViHHKrDxm9mr8M3VCniekaa9jrooANA56dEn
# knfZZWsrOHklJXrx+uLiVkaqw00055xDEz34hvwEZyvcvDPqtTiqvezAEwsnKWvf
# PPPG62uGb8OwqKXsrVXdHj8Rr7jeAYAJU1Gt960TK3qByfUKqUDCYYMI2dT2j2mw
# JheNLCj6XPrDpaJqEr4CEx3ExfTJPrpA0rz1YBSl9MlxWTxRq2pw/ofRpCOTLLwl
# GCk4uguID3YiKtT0geDZ2EPWhXD3oYIXdzCCF3MGCisGAQQBgjcDAwExghdjMIIX
# XwYJKoZIhvcNAQcCoIIXUDCCF0wCAQMxDzANBglghkgBZQMEAgEFADB4BgsqhkiG
# 9w0BCRABBKBpBGcwZQIBAQYJYIZIAYb9bAcBMDEwDQYJYIZIAWUDBAIBBQAEIJXZ
# d7lzZ13bgsF33csgTcapoc+InkGvWUWVUWVnFcStAhEAmVQLwZV2A9JYe/fFeI7/
# wBgPMjAyNjEwMTAwODMwMjhaoIITOjCCBu0wggTVoAMCAQICEAhP3DNPfkVO28MP
# j/mSGDUwDQYJKoZIhvcNAQELBQAwaTELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRp
# Z2lDZXJ0LCBJbmMuMUEwPwYDVQQDEzhEaWdpQ2VydCBUcnVzdGVkIEc0IFRpbWVT
# dGFtcGluZyBSU0E0MDk2IFNIQTI1NiAyMDI1IENBMTAeFw0yNjA4MDUwMDAwMDBa
# Fw0zNzExMDQyMzU5NTlaMGMxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2Vy
# dCwgSW5jLjE7MDkGA1UEAxMyRGlnaUNlcnQgU0hBMjU2IFJTQTQwOTYgVGltZXN0
# YW1wIFJlc3BvbmRlciAyMDI2IDEwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIK
# AoICAQC2e6byyf7NSvjUm0xls/04xjD4fAkOkbnGQi7+Wpx81iYxfzViaxSIctuH
# 3KSl5YEYpMuFgGsA31N2D9ATMbfZdw5uaAhuWevQKhDdZIB4NnqcfpfpWQXJiQnD
# dAElETC+bhSEvNLGbA8DtwUpFMQ4yyYQSPqomT92osQAv6hBi47ATZS6JfVWe6Xx
# hF4jJZ3iSAuf2Cros1czRSmWRHqMv9AfGZvp8ygYElhudpQjtcPpwoOl6QrZJUyV
# 3iINvN4cO05prGV0fkjG426xDr2d3z9lcSIHkdvGPdGUrXdxfVbgOUVcp2/8ISEz
# wKPW++Wa+E2ujI91EZtukGWDJ/xZ27k3oHKEXBRGfRTqjOU+jE3ba/5++JSE/7oN
# Hnjs5mekExYN96LV/mxUbCKJb8pBNY4r3uD7hEmk/M81XhVgwDA7aMzYC3LZBg9W
# Y5BMmbSay5ecmtJuXaB/0nKWmQmVZeqTVDgsmzHP5MQuhAJkiWNuC9MmCg9TZHXb
# J2/yLVSov9p16UDTLtT0+aa1vN71fHeu1qMLlLNB3WOB/ADCxr3S/1hxI92Z6jKg
# EED/btwIvbfuXkNNhg8MtDg43c4tMZae9FvqMOt/9PvmAxF9TNIsIFB8G6yb36ZJ
# ZGUL8N/pL971DyLXcK6HM5PYnH5X+eVtczhCgHCVQCF6XDAlPQIDAQABo4IBlTCC
# AZEwDAYDVR0TAQH/BAIwADAdBgNVHQ4EFgQUFMljijAu1Er7bpTz5uNAfvXszeIw
# HwYDVR0jBBgwFoAU729TSunkBnx6yuKQVvYv1Ensy04wDgYDVR0PAQH/BAQDAgeA
# MBYGA1UdJQEB/wQMMAoGCCsGAQUFBwMIMIGVBggrBgEFBQcBAQSBiDCBhTAkBggr
# BgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tMF0GCCsGAQUFBzAChlFo
# dHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkRzRUaW1l
# U3RhbXBpbmdSU0E0MDk2U0hBMjU2MjAyNUNBMS5jcnQwXwYDVR0fBFgwVjBUoFKg
# UIZOaHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZEc0VGlt
# ZVN0YW1waW5nUlNBNDA5NlNIQTI1NjIwMjVDQTEuY3JsMCAGA1UdIAQZMBcwCAYG
# Z4EMAQQCMAsGCWCGSAGG/WwHATANBgkqhkiG9w0BAQsFAAOCAgEAjcU6YR6dUgrf
# mawJgH59KECxa9Ji8sEi2g10CBDaMiqsaxWyW5cwlT/6ZF5sFznazqVsoC85U9dq
# LOYqQwst+UQQoNlDHgKRLa3xoc+OReFreFhnTXSG0Vrd2E2CZqUfm+5a+He1MJ/h
# +tNLuA+0Zzhn/Fo+FDYAHWZHx4R79ZsfRFYe9UiXpXBDf6DkUo183Y38NYmR/XfD
# Yf7YZ+oR9t3flbDwK+hgGMs0gNNp1w9Z2CyOyI5or/sSwomAuNQ0hWC9xoU4stD8
# aWsD7RkcmgVRs6vlIk3zPKQ+ylcheWkMlj+CoVRlFE55pv0ZWCaFt04lwP/rdGHE
# 9qEVQZtyRE42ox7oNgC/r+Y4bSlZ3dw9K2x1xLtu6PkPKeLBFjzKigwfqm3Hm+k/
# +lnME8F5kPZTgiy2HLEHklpryqs6QHnPXrRNeIzkAMyylnRN8P0wmirS0WkU+ywp
# EWFZ4QNg+9xS43tTuW9x0eXh7NDc1P/sV+zWxHXKH8tFt1ncHdVzqrZaYPyYMLSn
# 2TOXajveJW1L3joiQSPsWRGxkbDDW15jERFE4LvjnGu2O9zD1nLJSMdlYZEikl4w
# 2w+q4IN/R+TIe0H4ngCI1moJCTbevGH4punIxM1Uoi0nmX3ZK+XbRT01uowE5ViX
# WHng0RgsmrX/EdYUo80r3TfMlkD0/YMwgga0MIIEnKADAgECAhANx6xXBf8hmS5A
# QyIMOkmGMA0GCSqGSIb3DQEBCwUAMGIxCzAJBgNVBAYTAlVTMRUwEwYDVQQKEwxE
# aWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20xITAfBgNVBAMT
# GERpZ2lDZXJ0IFRydXN0ZWQgUm9vdCBHNDAeFw0yNTA1MDcwMDAwMDBaFw0zODAx
# MTQyMzU5NTlaMGkxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5j
# LjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBHNCBUaW1lU3RhbXBpbmcgUlNB
# NDA5NiBTSEEyNTYgMjAyNSBDQTEwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIK
# AoICAQC0eDHTCphBcr48RsAcrHXbo0ZodLRRF51NrY0NlLWZloMsVO1DahGPNRcy
# bEKq+RuwOnPhof6pvF4uGjwjqNjfEvUi6wuim5bap+0lgloM2zX4kftn5B1IpYzT
# qpyFQ/4Bt0mAxAHeHYNnQxqXmRinvuNgxVBdJkf77S2uPoCj7GH8BLuxBG5AvftB
# dsOECS1UkxBvMgEdgkFiDNYiOTx4OtiFcMSkqTtF2hfQz3zQSku2Ws3IfDReb6e3
# mmdglTcaarps0wjUjsZvkgFkriK9tUKJm/s80FiocSk1VYLZlDwFt+cVFBURJg6z
# MUjZa/zbCclF83bRVFLeGkuAhHiGPMvSGmhgaTzVyhYn4p0+8y9oHRaQT/aofEnS
# 5xLrfxnGpTXiUOeSLsJygoLPp66bkDX1ZlAeSpQl92QOMeRxykvq6gbylsXQskBB
# BnGy3tW/AMOMCZIVNSaz7BX8VtYGqLt9MmeOreGPRdtBx3yGOP+rx3rKWDEJlIqL
# XvJWnY0v5ydPpOjL6s36czwzsucuoKs7Yk/ehb//Wx+5kMqIMRvUBDx6z1ev+7ps
# NOdgJMoiwOrUG2ZdSoQbU2rMkpLiQ6bGRinZbI4OLu9BMIFm1UUl9VnePs6BaaeE
# WvjJSjNm2qA+sdFUeEY0qVjPKOWug/G6X5uAiynM7Bu2ayBjUwIDAQABo4IBXTCC
# AVkwEgYDVR0TAQH/BAgwBgEB/wIBADAdBgNVHQ4EFgQU729TSunkBnx6yuKQVvYv
# 1Ensy04wHwYDVR0jBBgwFoAU7NfjgtJxXWRM3y5nP+e6mK4cD08wDgYDVR0PAQH/
# BAQDAgGGMBMGA1UdJQQMMAoGCCsGAQUFBwMIMHcGCCsGAQUFBwEBBGswaTAkBggr
# BgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tMEEGCCsGAQUFBzAChjVo
# dHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkUm9vdEc0
# LmNydDBDBgNVHR8EPDA6MDigNqA0hjJodHRwOi8vY3JsMy5kaWdpY2VydC5jb20v
# RGlnaUNlcnRUcnVzdGVkUm9vdEc0LmNybDAgBgNVHSAEGTAXMAgGBmeBDAEEAjAL
# BglghkgBhv1sBwEwDQYJKoZIhvcNAQELBQADggIBABfO+xaAHP4HPRF2cTC9vgvI
# tTSmf83Qh8WIGjB/T8ObXAZz8OjuhUxjaaFdleMM0lBryPTQM2qEJPe36zwbSI/m
# S83afsl3YTj+IQhQE7jU/kXjjytJgnn0hvrV6hqWGd3rLAUt6vJy9lMDPjTLxLgX
# f9r5nWMQwr8Myb9rEVKChHyfpzee5kH0F8HABBgr0UdqirZ7bowe9Vj2AIMD8liy
# rukZ2iA/wdG2th9y1IsA0QF8dTXqvcnTmpfeQh35k5zOCPmSNq1UH410ANVko43+
# Cdmu4y81hjajV/gxdEkMx1NKU4uHQcKfZxAvBAKqMVuqte69M9J6A47OvgRaPs+2
# ykgcGV00TYr2Lr3ty9qIijanrUR3anzEwlvzZiiyfTPjLbnFRsjsYg39OlV8cipD
# oq7+qNNjqFzeGxcytL5TTLL4ZaoBdqbhOhZ3ZRDUphPvSRmMThi0vw9vODRzW6Ax
# nJll38F0cuJG7uEBYTptMSbhdhGQDpOXgpIUsWTjd6xpR6oaQf/DJbg3s6KCLPAl
# Z66RzIg9sC+NJpud/v4+7RWsWCiKi9EOLLHfMR2ZyJ/+xhCx9yHbxtl5TPau1j/1
# MIDpMPx0LckTetiSuEtQvLsNz3Qbp7wGWqbIiOWCnb5WqxL3/BAPvIXKUjPSxyZs
# q8WhbaM2tszWkPZPubdcMIIFjTCCBHWgAwIBAgIQDpsYjvnQLefv21DiCEAYWjAN
# BgkqhkiG9w0BAQwFADBlMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQg
# SW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSQwIgYDVQQDExtEaWdpQ2Vy
# dCBBc3N1cmVkIElEIFJvb3QgQ0EwHhcNMjIwODAxMDAwMDAwWhcNMzExMTA5MjM1
# OTU5WjBiMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYD
# VQQLExB3d3cuZGlnaWNlcnQuY29tMSEwHwYDVQQDExhEaWdpQ2VydCBUcnVzdGVk
# IFJvb3QgRzQwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQC/5pBzaN67
# 5F1KPDAiMGkz7MKnJS7JIT3yithZwuEppz1Yq3aaza57G4QNxDAf8xukOBbrVsaX
# bR2rsnnyyhHS5F/WBTxSD1Ifxp4VpX6+n6lXFllVcq9ok3DCsrp1mWpzMpTREEQQ
# Lt+C8weE5nQ7bXHiLQwb7iDVySAdYyktzuxeTsiT+CFhmzTrBcZe7FsavOvJz82s
# NEBfsXpm7nfISKhmV1efVFiODCu3T6cw2Vbuyntd463JT17lNecxy9qTXtyOj4Da
# tpGYQJB5w3jHtrHEtWoYOAMQjdjUN6QuBX2I9YI+EJFwq1WCQTLX2wRzKm6RAXwh
# TNS8rhsDdV14Ztk6MUSaM0C/CNdaSaTC5qmgZ92kJ7yhTzm1EVgX9yRcRo9k98Fp
# iHaYdj1ZXUJ2h4mXaXpI8OCiEhtmmnTK3kse5w5jrubU75KSOp493ADkRSWJtppE
# GSt+wJS00mFt6zPZxd9LBADMfRyVw4/3IbKyEbe7f/LVjHAsQWCqsWMYRJUadmJ+
# 9oCw++hkpjPRiQfhvbfmQ6QYuKZ3AeEPlAwhHbJUKSWJbOUOUlFHdL4mrLZBdd56
# rF+NP8m800ERElvlEFDrMcXKchYiCd98THU/Y+whX8QgUWtvsauGi0/C1kVfnSD8
# oR7FwI+isX4KJpn15GkvmB0t9dmpsh3lGwIDAQABo4IBOjCCATYwDwYDVR0TAQH/
# BAUwAwEB/zAdBgNVHQ4EFgQU7NfjgtJxXWRM3y5nP+e6mK4cD08wHwYDVR0jBBgw
# FoAUReuir/SSy4IxLVGLp6chnfNtyA8wDgYDVR0PAQH/BAQDAgGGMHkGCCsGAQUF
# BwEBBG0wazAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tMEMG
# CCsGAQUFBzAChjdodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRB
# c3N1cmVkSURSb290Q0EuY3J0MEUGA1UdHwQ+MDwwOqA4oDaGNGh0dHA6Ly9jcmwz
# LmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5jcmwwEQYDVR0g
# BAowCDAGBgRVHSAAMA0GCSqGSIb3DQEBDAUAA4IBAQBwoL9DXFXnOF+go3QbPbYW
# 1/e/Vwe9mqyhhyzshV6pGrsi+IcaaVQi7aSId229GhT0E0p6Ly23OO/0/4C5+KH3
# 8nLeJLxSA8hO0Cre+i1Wz/n096wwepqLsl7Uz9FDRJtDIeuWcqFItJnLnU+nBgMT
# dydE1Od/6Fmo8L8vC6bp8jQ87PcDx4eo0kxAGTVGamlUsLihVo7spNU96LHc/RzY
# 9HdaXFSMb++hUD38dglohJ9vytsgjTVgHAIDyyCwrFigDkBjxZgiwbJZ9VVrzyer
# bHbObyMt9H5xaiNrIv8SuFQtJ37YOtnwtoeW/VvRXKwYw02fc7cBqZ9Xql4o4rmU
# MYIDfDCCA3gCAQEwfTBpMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQs
# IEluYy4xQTA/BgNVBAMTOERpZ2lDZXJ0IFRydXN0ZWQgRzQgVGltZVN0YW1waW5n
# IFJTQTQwOTYgU0hBMjU2IDIwMjUgQ0ExAhAIT9wzT35FTtvDD4/5khg1MA0GCWCG
# SAFlAwQCAQUAoIHRMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAcBgkqhkiG
# 9w0BCQUxDxcNMjYxMDEwMDgzMDI4WjArBgsqhkiG9w0BCRACDDEcMBowGDAWBBRR
# 2avaA0lz2E9CZqykgkjms2nEOTAvBgkqhkiG9w0BCQQxIgQgbRYPW2Mc78UKl1hP
# bpD3okVPSaPm+Ymz/EzHty5SPwwwNwYLKoZIhvcNAQkQAi8xKDAmMCQwIgQgLaCd
# p/QTH5/nLbbF5unJZWdVrwQ/HqdCzA0hIOFB6/wwDQYJKoZIhvcNAQEBBQAEggIA
# d4KvDkbf9jWNA23uq4gG8xkoVkTrhfVxJQj+CNm+LLsdS4ytS/xtwVO3G2kLPDqM
# 79wulllkxLVNBykMlKSDUFkNogfMjrpCxMNTEwZ1cTJjSZHmK8oZCy9K0dRlimGg
# 9hDGdnshsrnSIofvXXNpbA2C92E9ZpKtTTAs4u3TfMO9G/f9rGwTqcvhzW+jEU8J
# OmS3tyKp1Muw8IEmlC9cM9WZJ6sxzah6thhDJu0XGmXRUvWa5Bfrb3cSJNw0d4cq
# HpFcuG8ZIr+OR17pamOrTrovLYUXxHCp3qIxZBivwtb29pNOUjK5fRuttqJiDbPb
# DEHuUm8UV8knRFbjj9x95y88PueVCsr7LLfD1N4LcNFuTPFXARKqC3FAcvna9mEV
# wTeDK5kzp35uEGDFJ8I/gluqWAmd02d1mIO0ofjZU6tKIcKzqwCARLCeldb97G7L
# p/OXBfX5QJGMfgNfCMc7i9NadlGK6uS3jh/lPCyPjYFB899f9WGVylbbmw+8cvXF
# kGSx+AJZpv7ApXhfqa/xhOyGzm1qL/yqmzXe14xX9LMJRCR0T9Cw1HNOGjb58wfo
# Okl8vYQSsZTCy2s5wSzmZoHk488dSUhY4V3wzlvF4viMi1TSLtVtwgjQkxjWp26p
# rPzemGnAXLgXoIm3yrXdRXiJnqArSsjvWAS4VUm6InI=
# SIG # End signature block
