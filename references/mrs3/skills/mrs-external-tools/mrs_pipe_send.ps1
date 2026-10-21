<#
  mrs_pipe_send.ps1  --  MRS external tool pipe client / sender (multi-instance).

  GENERIC, REUSABLE SCRIPT. It ships with this skill and lives in the skill
  directory (the directory that contains SKILL.md) together with
  mrs_pipe_host.ps1. It is meant to be CALLED, never regenerated, overwritten
  or rewritten during a workflow.

  Role
    Wait for the target instance readiness marker, connect to that instance's
    named pipe, send the pending commands (one line per command) and optionally
    keep sending a heartbeat until the task is declared finished with the
    instance stop flag. -Instance selects WHICH host instance to talk to, so a
    single script drives every instance independently.

    Health reporting: the sender keeps mrs_pipe_send_stateSUFFIX.json up to date
    (starting / done / error) and fails with a non-zero exit code on any error,
    so the orchestrator can notice a blocked or killed sender at once. -Status
    reports host / tool / sender liveness, -Reset cleans one instance state and
    kills its leftover processes, -List enumerates the registered instances.

  Launch (relative -File + -WorkingDirectory keeps paths with spaces safe;
  -ArgumentList is never asked to carry a path):
    Start-Process pwsh -WorkingDirectory $ScriptDir `
        -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File','mrs_pipe_send.ps1','-Instance','a') `
        -WindowStyle Hidden -PassThru
    (use powershell.exe instead of pwsh when only Windows PowerShell 5.1 exists)

  Command source priority
    1) -CommandFile <path>     preferred, one command per line, spaces are safe
    2) -Command <token>        ONLY for a single token without spaces (e.g. read)
    3) default                 <WorkDir>\mrs_cmdsSUFFIX.txt when that file exists
                               (SUFFIX is '' for the single instance mode,
                               otherwise '.' plus the instance name)

  Parameters (all optional; resolution order: parameter -> environment -> default)
    -WorkDir          writable coordination directory
                      -> $env:MRS_PIPE_WORKDIR -> <TEMP>\mrs_pipe
    -Instance         target instance name ([A-Za-z0-9_-]); empty = single instance
    -KeepAlive        keep sending the heartbeat until the instance stop flag appears
    -KeepAliveCommand full heartbeat command line (default: "read /timeout <IntervalMs>")
    -IntervalMs       heartbeat timeout used by the default heartbeat command, default 1500
    -MaxSeconds       heartbeat cap, default 300
    -ReadyTimeoutSec  max wait for the instance readiness marker, default 30
    -List             list every instance registered in -WorkDir, then return
    -Status           report host / tool / sender liveness of the target instance, then return
    -Stop             create the stop flag of the target instance, then return
    -Reset            clean the target instance state and kill its leftover
                      processes (host / tool / sender), then return
    -KeepHost         use with -Reset: clear only the sender state / leftover
                      sender and keep the host instance running

  Delegation note: only ONE process may read a given output stream at a time.
  Do not run several -KeepAlive senders concurrently against the same instance.
#>
param(
    [string]$WorkDir,
    [string]$Instance,
    [string]$CommandFile,
    [string]$Command,
    [switch]$KeepAlive,
    [string]$KeepAliveCommand,
    [int]$IntervalMs = 1500,
    [int]$MaxSeconds = 300,
    [int]$ReadyTimeoutSec = 30,
    [switch]$List,
    [switch]$Status,
    [switch]$Stop,
    [switch]$Reset,
    [switch]$KeepHost
)
$ErrorActionPreference = 'Stop'
$enc = New-Object System.Text.UTF8Encoding($false)

# ---------- 0) resolve work directory / instance: parameter -> environment -> default ----------
if (-not $WorkDir -or $WorkDir.Trim() -eq '') {
    if ($env:MRS_PIPE_WORKDIR -and $env:MRS_PIPE_WORKDIR.Trim() -ne '') {
        $WorkDir = $env:MRS_PIPE_WORKDIR
    } else {
        $WorkDir = Join-Path ([System.IO.Path]::GetTempPath()) 'mrs_pipe'
    }
}
$Instance = if ($null -eq $Instance) { '' } else { $Instance.Trim() }
if ($Instance -ne '' -and $Instance -notmatch '^[A-Za-z0-9_-]+$') {
    throw "Invalid -Instance '$Instance': use only letters, digits, '-' and '_'."
}
$suffix = ''
if ($Instance -ne '') { $suffix = '.' + $Instance }
$label = if ($Instance -ne '') { $Instance } else { '(single)' }

$readyFile             = Join-Path $WorkDir ("mrs_pipe_ready$suffix.json")
$hostStateFile         = Join-Path $WorkDir ("mrs_pipe_state$suffix.json")
$script:sendStateFile  = Join-Path $WorkDir ("mrs_pipe_send_state$suffix.json")
$stopFile              = Join-Path $WorkDir ("mrs_pipe_stop$suffix.flag")
$resultFile            = Join-Path $WorkDir ("mrs_pipe_result$suffix.txt")

function Get-StateJson([string]$path) {
    try {
        # -Encoding UTF8 matters on Windows PowerShell 5.1: without it a BOM-less
        # UTF-8 file would be decoded with the ANSI code page and garble paths.
        if (Test-Path -LiteralPath $path) { return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json) }
    } catch { }
    return $null
}
function Test-PidAlive([int]$TargetPid) {
    if (-not $TargetPid -or $TargetPid -le 0) { return $false }
    $p = Get-Process -Id $TargetPid -ErrorAction SilentlyContinue
    if ($null -eq $p) { return $false }
    # A terminated process can linger in the process table (and a stale PID may
    # even be recycled), so HasExited is the authoritative check.
    try { if ($p.HasExited) { return $false } } catch { }
    return $true
}
function Set-SendState([string]$phase, [string]$detail, [int]$sent) {
    try {
        $json = @{ instance = $Instance; phase = $phase; pid = $PID; sent = $sent; detail = $detail;
                   updated = (Get-Date).ToString('s') } | ConvertTo-Json -Compress
        # .NET write keeps the file UTF-8 without BOM on both PS 5.1 and PS 7+
        [System.IO.File]::WriteAllText($script:sendStateFile, $json, $enc)
    } catch { }
}
function Send([string]$c) {               # one command -> one response (strict pairing)
    $writer.WriteLine($c)
    return $reader.ReadLine()
}

if ($List) {
    # ---------- 0a) report every instance currently registered in -WorkDir ----------
    $found = @(Get-ChildItem -LiteralPath $WorkDir -Filter 'mrs_pipe_ready*.json' -File -ErrorAction SilentlyContinue | Sort-Object Name)
    if ($found.Count -eq 0) {
        'INSTANCES: (none)'
    } else {
        foreach ($f in $found) {
            $info = Get-StateJson $f.FullName
            if ($null -eq $info) { continue }
            $sfx   = ($f.Name.Substring('mrs_pipe_ready'.Length)) -replace '\.json$', ''
            $name  = if ($info.instance) { $info.instance } else { '(single)' }
            $phase = '(none)'
            $st    = Get-StateJson (Join-Path $WorkDir ("mrs_pipe_state$sfx.json"))
            if ($st -and $st.phase) { $phase = $st.phase }
            $hostAlive = Test-PidAlive ([int]$info.hostPid)
            $toolAlive = Test-PidAlive ([int]$info.toolPid)
            "INSTANCE=$name; PHASE=$phase; PIPE=$($info.pipe); HOSTPID=$($info.hostPid); HOSTALIVE=$hostAlive; TOOLPID=$($info.toolPid); TOOLALIVE=$toolAlive; EXE=$($info.exe)"
        }
    }
} elseif ($Status) {
    # ---------- 0b) report host / tool / sender state of the target instance ----------
    $st    = Get-StateJson $hostStateFile
    $ready = Get-StateJson $readyFile
    $ss    = Get-StateJson $script:sendStateFile
    $phase = '(none)'; $hostPid = 0; $toolPid = 0; $pipe = ''; $detail = ''
    if ($st) {
        $phase = $st.phase; $hostPid = [int]$st.hostPid; $toolPid = [int]$st.toolPid; $pipe = $st.pipe; $detail = $st.detail
    }
    if ($ready) {
        if (-not $hostPid) { $hostPid = [int]$ready.hostPid }
        if (-not $toolPid) { $toolPid = [int]$ready.toolPid }
        if (-not $pipe)    { $pipe    = $ready.pipe }
        if ($phase -eq '(none)') { $phase = 'ready' }
    }
    $sendPhase = '(none)'; $sendPid = 0
    if ($ss) { $sendPhase = $ss.phase; $sendPid = [int]$ss.pid }
    "INSTANCE=$label; HOSTPHASE=$phase; HOSTPID=$hostPid; HOSTALIVE=$(Test-PidAlive $hostPid); TOOLPID=$toolPid; TOOLALIVE=$(Test-PidAlive $toolPid); SENDPHASE=$sendPhase; SENDPID=$sendPid; SENDALIVE=$(Test-PidAlive $sendPid); PIPE=$pipe; DETAIL=$detail"
} elseif ($Stop) {
    # ---------- 0c) end the target instance without sending any command ----------
    New-Item -ItemType File -Path $stopFile -Force | Out-Null
    "STOP: requested for instance '$label'"
} elseif ($Reset) {
    # ---------- 0d) clean instance state and kill its leftover processes ----------
    if ($KeepHost) {
        # Sender-scoped reset: a healthy host must survive a sender retry, so
        # only the sender state and a leftover sender process are cleared.
        $sendPid = 0
        $ss = Get-StateJson $script:sendStateFile
        if ($ss -and $ss.pid) { $sendPid = [int]$ss.pid }
        $killed = @()
        if ($sendPid -gt 0 -and $sendPid -ne $PID -and (Test-PidAlive $sendPid)) {
            try { Stop-Process -Id $sendPid -Force -ErrorAction SilentlyContinue; $killed += $sendPid } catch { }
        }
        $removed = 0
        if (Test-Path -LiteralPath $script:sendStateFile) {
            Remove-Item -LiteralPath $script:sendStateFile -Force -Confirm:$false -ErrorAction SilentlyContinue
            if (-not (Test-Path -LiteralPath $script:sendStateFile)) { $removed++ }
        }
        "RESET: instance '$label'; scope=sender; removed=$removed; killed=$(($killed -join ','))"
    } else {
        $pids = @()
        foreach ($src in @((Get-StateJson $hostStateFile), (Get-StateJson $readyFile), (Get-StateJson $script:sendStateFile))) {
            if ($src) {
                foreach ($n in 'hostPid', 'toolPid', 'pid') {
                    if ($src.$n) { $pids += [int]$src.$n }
                }
            }
        }
        $pids   = @($pids | Sort-Object -Unique | Where-Object { $_ -gt 0 -and $_ -ne $PID })
        $killed = @()
        foreach ($tp in $pids) {
            if (Test-PidAlive $tp) {
                try { Stop-Process -Id $tp -Force -ErrorAction SilentlyContinue; $killed += $tp } catch { }
            }
        }
        $removed = 0
        foreach ($t in @($readyFile, $hostStateFile, $script:sendStateFile, $stopFile, $resultFile)) {
            if (Test-Path -LiteralPath $t) {
                Remove-Item -LiteralPath $t -Force -Confirm:$false -ErrorAction SilentlyContinue
                if (-not (Test-Path -LiteralPath $t)) { $removed++ }
            }
        }
        "RESET: instance '$label'; scope=full; removed=$removed; killed=$(($killed -join ','))"
    }
} else {
    # ---------- 1) send commands (strict: any error exits non-zero) ----------
    $client = $null
    $sent   = 0
    try {
        if (-not $CommandFile -and -not $Command) {
            $defaultCmds = Join-Path $WorkDir ("mrs_cmds$suffix.txt")
            if (Test-Path -LiteralPath $defaultCmds) { $CommandFile = $defaultCmds }
        }
        Set-SendState 'starting' 'waiting for host readiness' 0

        # Wait for readiness with a short poll, but abort at once when the host
        # process is gone or has recorded an error (killed / blocked).
        $deadline = (Get-Date).AddSeconds($ReadyTimeoutSec)
        $pipeName = ''
        while ($true) {
            if (Test-Path -LiteralPath $readyFile) {
                $rd = Get-StateJson $readyFile
                if ($rd -and $rd.pipe) {
                    # A ready marker can be stale when the host was killed (for
                    # example by security software); never trust it blindly.
                    $hp = 0
                    $stx = Get-StateJson $hostStateFile
                    if ($stx -and $stx.hostPid) { $hp = [int]$stx.hostPid } elseif ($rd.hostPid) { $hp = [int]$rd.hostPid }
                    if ($hp -and -not (Test-PidAlive $hp)) {
                        throw "Host process $hp is gone although a ready marker exists; the instance state is stale."
                    }
                    $pipeName = $rd.pipe
                    break
                }
            }
            $st = Get-StateJson $hostStateFile
            if ($st) {
                if ($st.phase -eq 'error') { throw "Host reported a startup error: $($st.detail)" }
                if ($st.hostPid -and -not (Test-PidAlive ([int]$st.hostPid))) {
                    throw "Host process $($st.hostPid) is gone (phase '$($st.phase)'); no readiness."
                }
            }
            if ((Get-Date) -ge $deadline) { throw "Pipe host not ready: '$readyFile' did not appear within ${ReadyTimeoutSec}s." }
            Start-Sleep -Milliseconds 200
        }

        # ---------- 2) connect ----------
        $client = [System.IO.Pipes.NamedPipeClientStream]::new('.', $pipeName, [System.IO.Pipes.PipeDirection]::InOut)
        $client.Connect(10000)
        $reader = New-Object System.IO.StreamReader($client, $enc)
        $writer = New-Object System.IO.StreamWriter($client, $enc)
        $writer.AutoFlush = $true
        $null = $reader.ReadLine()                 # {"status":"connected"}

        # ---------- 3) send the explicit commands ----------
        if ($CommandFile) {
            foreach ($c in (Get-Content -LiteralPath $CommandFile -Encoding UTF8)) {
                if ($c -and $c.Trim() -ne '') { $null = Send $c.Trim(); $sent++ }
            }
        }
        if ($Command) { $null = Send $Command; $sent++ }

        # ---------- 4) keep-alive until the instance task is declared finished ----------
        if ($KeepAlive) {
            if (-not $KeepAliveCommand -or $KeepAliveCommand.Trim() -eq '') {
                $KeepAliveCommand = "read /timeout $IntervalMs"
            }
            $limit = (Get-Date).AddSeconds($MaxSeconds)
            while ((Get-Date) -lt $limit -and -not (Test-Path -LiteralPath $stopFile)) {
                $null = Send $KeepAliveCommand
                $sent++
                Start-Sleep -Milliseconds 50
            }
        }

        Set-SendState 'done' "sent=$sent" $sent
        try { $client.Dispose() } catch { }
        $client = $null
    }
    catch {
        Set-SendState 'error' $_.Exception.Message $sent
        try { if ($client) { $client.Dispose() } } catch { }
        throw
    }
}

# SIG # Begin signature block
# MIIqHAYJKoZIhvcNAQcCoIIqDTCCKgkCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAwHutm4RqvQON0
# HK9mN6O8Zf9osIeiwo7wK6uSPNb3LaCCDtEwggawMIIEmKADAgECAhAIrUCyYNKc
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
# CzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIPBtn6xa0mjYIy4LTex7
# m3/RF4LSVZukWyXUp1qepDBpMA0GCSqGSIb3DQEBAQUABIICAB+H5bLVoL7sJpM4
# m3xMb8HGcmjTCGD1lPMJ7H1iqf6KDQIEpZHUSHwSXDINRryyVIkAwYLBRUmIB2Gc
# wk0RePpZ7sZevj3MH1uVjHn4WqbvjZbf0dMhUfarDKJQorrBgeSQvzgfvQeusZjP
# Sis/G2SQp61g3po691UmNSFszwIvGqJNJ6R5DOXcmZFgPGJju4yboKls9YKfZoPC
# 1gCLr8jX1MijU3OPsZln0oDR55n0kbVzOp7w34lz2b6Vm4yMZiRWZmH88bOFjyKM
# Kb0D4/cKiIodbmFyd76kp5z5m3vUtlImOG+vtwO7+IPiLSMpokxKq1K/BhY+E5CR
# 9Vod/tOkFC8vudXizcwcMKqK3ckeYsCr2pM7A47T1UCahccZOXWzQtaIbLE2N+fc
# 6mJn7NDStQNFU07PHGO+2x3jODhOKlatD13XZreRTZ2ewsbpx6h7k+7R1mB2AaYh
# LB3Zc7MNgXYJOZkA3H+PIM1qgZlJZ9TWci7Y3iTrV3MlFHX1kd+MEHVWb9uQWHXO
# cKLMT4QX0i2IcHFSU2wBC9dTDjHeA0asovWPeRpA0a6evMGibqb2Umle4evhkNOA
# Y1UYEG6rw0LMQ0Pi44K7dR443GnGa3hnV/aPZm2Vu129kX77vLCY+1auwQmIfatE
# lUM0loBBj+yTjACWZvIIjNjzFIG0oYIXdzCCF3MGCisGAQQBgjcDAwExghdjMIIX
# XwYJKoZIhvcNAQcCoIIXUDCCF0wCAQMxDzANBglghkgBZQMEAgEFADB4BgsqhkiG
# 9w0BCRABBKBpBGcwZQIBAQYJYIZIAYb9bAcBMDEwDQYJYIZIAWUDBAIBBQAEIPqI
# wspvMzgIiwQVgQCupMG0l3H4NHV46EVGb8QPGJg6AhEAqLF8BqWjV8xOZiHGPVlx
# IBgPMjAyNjEwMTAwODMwMzFaoIITOjCCBu0wggTVoAMCAQICEAhP3DNPfkVO28MP
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
# 9w0BCQUxDxcNMjYxMDEwMDgzMDMxWjArBgsqhkiG9w0BCRACDDEcMBowGDAWBBRR
# 2avaA0lz2E9CZqykgkjms2nEOTAvBgkqhkiG9w0BCQQxIgQgvmv3oqGoqDjNEDiN
# CysgTxdVgG7MJv+WLl+GJSklCUMwNwYLKoZIhvcNAQkQAi8xKDAmMCQwIgQgLaCd
# p/QTH5/nLbbF5unJZWdVrwQ/HqdCzA0hIOFB6/wwDQYJKoZIhvcNAQEBBQAEggIA
# AGjj3kuFzwxibteaf9TweJPYWKM2LH6bZlz61mh6Euu0SeLM/DUz/eZaESBHrtnL
# ZYwI77R+pL1vl+r3oPVnNdKMP+XkGyVEq3xs7vwkOmSl5Tv7Xokf1D1qvQmFXTvy
# PzgQf4m7j6dQhfoBD7d9l9yQZCjP1Tom0KLRqOh7N6hmD9Kq2HmZTLVbPH06HqDU
# bC1zVsK1l6rHdfnLkdVdAeUVfp8IISiBiawQUkZH3+QxokwUvcOs1nkFKq4xWnj2
# 4W/fatNlypXQbaO3gTFn4+KHFJQrRCgX0mvDQK6FyBZ2gFl6KtNwZd8BONQ0amZO
# c4RUo5IRtj9uESpwPIfHDsloxTK0HLbCiBEsOR3/aPIM+P+mgKYD0/KRSd/rwX+s
# 6dgvWvP684QbaWnq6oH2u7gCzlCN5VKdNM2vV+O2D6z5Nym0EnUJB6nYsOmeb2bW
# XHEjMEEfo29yS+mcHsleAgfAgAps6O2lWuKmz4ULXZMT8sY7ckFVW2pR21awgZar
# nYg3UfJ0EYwcPOy3p60Uwsf6k/SQUb6SBLlRFmlL6YnjcKi0cuF1AuPrEUDhVshQ
# LC8GibcreLJqxmXECpYrrtBig6apcrtM/oSzT1jvS6Jfe8DJ3oNsHeOuWu2KnYTj
# EYghKB6ITDVq6f46W7/dcwnznFWqVUzZbhJQU9RHq0Q=
# SIG # End signature block
