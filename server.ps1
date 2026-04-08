param(
  [string]$BindHost = '127.0.0.1',
  [int]$Port = 8000
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSCommandPath
$ui = Join-Path $root 'ui'
$trainingPath = Join-Path $root 'datasets\epoch_training_log.jsonl'
$agentLogPath = Join-Path $root 'datasets\task1_agent_log.jsonl'

function Read-JsonBody {
  param([System.Net.HttpListenerRequest]$Request)

  if (-not $Request.HasEntityBody) {
    return $null
  }

  $reader = New-Object System.IO.StreamReader($Request.InputStream, $Request.ContentEncoding)
  try {
    $raw = $reader.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) {
      return $null
    }
    return $raw | ConvertFrom-Json
  } catch {
    return $null
  } finally {
    $reader.Close()
  }
}

function Send-Bytes {
  param(
    [System.Net.HttpListenerContext]$Context,
    [byte[]]$Bytes,
    [string]$ContentType = 'application/octet-stream',
    [int]$StatusCode = 200
  )

  $Context.Response.StatusCode = $StatusCode
  $Context.Response.ContentType = $ContentType
  $Context.Response.ContentLength64 = $Bytes.Length
  $Context.Response.OutputStream.Write($Bytes, 0, $Bytes.Length)
  $Context.Response.OutputStream.Close()
}

function Send-Json {
  param(
    [System.Net.HttpListenerContext]$Context,
    $Payload,
    [int]$StatusCode = 200
  )

  $json = $Payload | ConvertTo-Json -Depth 20 -Compress
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
  Send-Bytes -Context $Context -Bytes $bytes -ContentType 'application/json' -StatusCode $StatusCode
}

function Get-MimeType {
  param([string]$Path)

  switch ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
    '.html' { 'text/html; charset=utf-8' }
    '.css' { 'text/css; charset=utf-8' }
    '.js' { 'application/javascript; charset=utf-8' }
    '.json' { 'application/json; charset=utf-8' }
    '.svg' { 'image/svg+xml' }
    '.png' { 'image/png' }
    '.jpg' { 'image/jpeg' }
    '.jpeg' { 'image/jpeg' }
    default { 'application/octet-stream' }
  }
}

function Load-Jsonl {
  param([string]$Path)

  $items = @()
  if (-not (Test-Path $Path)) {
    return $items
  }

  Get-Content $Path | ForEach-Object {
    if ([string]::IsNullOrWhiteSpace($_)) { return }
    try {
      $items += ($_ | ConvertFrom-Json)
    } catch {
    }
  }
  return $items
}

$trainingState = Load-Jsonl -Path $trainingPath
$agentLogState = Load-Jsonl -Path $agentLogPath
$nextEpoch = if ($trainingState.Count -gt 0) { [int]$trainingState[-1].epoch + 1 } else { 1 }

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://${BindHost}:$Port/")
$listener.Start()
Write-Host ("[OK] Server running: http://${BindHost}:$Port/") -ForegroundColor Green

while ($listener.IsListening) {
  $context = $listener.GetContext()
  $path = $context.Request.Url.AbsolutePath
  $method = $context.Request.HttpMethod

  try {
    if ($path -eq '/health') {
      Send-Json -Context $context -Payload @{
        status = 'ok'
        environment = 'email-triage-env'
        tasks = @('task_1', 'task_2', 'task_3')
      }
      continue
    }

    if ($path -eq '/' -or $path -eq '/ui' -or $path -eq '/index.html') {
      $file = Join-Path $ui 'index.html'
      Send-Bytes -Context $context -Bytes ([System.IO.File]::ReadAllBytes($file)) -ContentType 'text/html; charset=utf-8'
      continue
    }

    if ($path -eq '/ui/logs' -or $path -eq '/logs.html') {
      $file = Join-Path $ui 'logs.html'
      Send-Bytes -Context $context -Bytes ([System.IO.File]::ReadAllBytes($file)) -ContentType 'text/html; charset=utf-8'
      continue
    }

    if ($path -match '^/ui-assets/(.+)$') {
      $relative = ($Matches[1] -replace '/', '\\')
      $file = Join-Path $ui $relative
      if (Test-Path $file) {
        Send-Bytes -Context $context -Bytes ([System.IO.File]::ReadAllBytes($file)) -ContentType (Get-MimeType -Path $file)
      } else {
        Send-Json -Context $context -Payload @{ detail = 'Asset not found' } -StatusCode 404
      }
      continue
    }

    if ($path -match '^/reset(?:/([^/?]+))?$') {
      $taskId = if ($Matches[1]) { $Matches[1] } else { 'task_1' }
      $availableActions = switch ($taskId) {
        'task_1' { @('classify_email') }
        'task_2' { @('query_policy', 'draft_response') }
        'task_3' { @('query_order_db', 'query_inventory', 'issue_refund', 'ship_order') }
        default { @('classify_email') }
      }
      Send-Json -Context $context -Payload @{
        observation = @{
          task_id = $taskId
          step_number = 0
          available_actions = $availableActions
          tool_traces = @()
          current_email = @{
            subject = 'Sample support request'
            body = 'Please help with my order.'
          }
        }
      }
      continue
    }

    if ($path -match '^/step/([^/?]+)$') {
      $taskId = $Matches[1]
      $body = Read-JsonBody -Request $context.Request
      $action = if ($body -and $body.PSObject.Properties.Name -contains 'action_type') { $body } else { @{ action_type = 'classify_email' } }
      $reward = [math]::Round((Get-Random -Minimum 50 -Maximum 100) / 100.0, 2)
      Send-Json -Context $context -Payload @{
        observation = @{
          task_id = $taskId
          step_number = 1
          current_email = @{
            subject = 'Sample support request'
            body = 'Please help with my order.'
          }
          tool_traces = @()
        }
        reward = @{
          value = $reward
        }
        done = $false
        info = @{
          action_received = $action
        }
      }
      continue
    }

    if ($path -match '^/auto-step/([^/?]+)$') {
      $taskId = $Matches[1]
      $reward = [math]::Round((Get-Random -Minimum 60 -Maximum 100) / 100.0, 2)
      Send-Json -Context $context -Payload @{
        observation = @{
          task_id = $taskId
          step_number = 1
          current_email = @{
            subject = 'Sample support request'
            body = 'Please help with my order.'
          }
          tool_traces = @()
        }
        reward = @{
          value = $reward
        }
        done = $false
        action_used = @{
          action_type = 'classify_email'
          category = 'General Inquiry'
          priority = 'Normal'
          order_id = $null
        }
        info = @{}
      }
      continue
    }

    if ($path -eq '/pipeline/run') {
      Send-Json -Context $context -Payload @{
        use_api = $false
        pipeline_order = @('task_1', 'task_2', 'task_3')
        results = @{
          task_1 = @{ score = 1.0; steps = 1; done = $true }
          task_2 = @{ score = 1.0; steps = 2; done = $true }
          task_3 = @{ score = 0.9; steps = 3; done = $true }
        }
        average_score = 0.9667
      }
      continue
    }

    if ($path -eq '/training/logs') {
      $limit = 100
      if ($context.Request.QueryString['limit']) {
        try { $limit = [int]$context.Request.QueryString['limit'] } catch { }
      }
      if ($limit -le 0) { $limit = 100 }
      $entries = @($trainingState | Select-Object -Last $limit)
      $best = 0.0
      foreach ($entry in $entries) {
        try {
          $best = [math]::Max($best, [double]$entry.average_score)
        } catch { }
      }
      Send-Json -Context $context -Payload @{
        limit = $limit
        entries = $entries
        summary = @{
          epochs = $entries.Count
          best_average_score = [math]::Round($best, 4)
          latest_epoch = if ($entries.Count -gt 0) { $entries[-1].epoch } else { $null }
        }
      }
      continue
    }

    if ($path -eq '/training/run') {
      $body = Read-JsonBody -Request $context.Request
      $epochs = 1
      if ($body -and $body.PSObject.Properties.Name -contains 'epochs') {
        try { $epochs = [Math]::Max(1, [int]$body.epochs) } catch { }
      }
      $created = @()
      for ($i = 0; $i -lt $epochs; $i++) {
        $entry = @{
          epoch = $nextEpoch
          timestamp = (Get-Date).ToUniversalTime().ToString('o')
          use_api = $false
          tasks = @{
            task_1 = @{ score = 1.0; steps = 1; done = $true }
            task_2 = @{ score = 1.0; steps = 2; done = $true }
            task_3 = @{ score = 0.9; steps = 3; done = $true }
          }
          average_score = 0.9667
        }
        $trainingState += [pscustomobject]$entry
        $created += $entry
        $nextEpoch += 1
      }
      Send-Json -Context $context -Payload @{
        ran_epochs = $epochs
        entries = $created
        latest = if ($created.Count -gt 0) { $created[-1] } else { $null }
      }
      continue
    }

    if ($path -eq '/agent/task_1') {
      Send-Json -Context $context -Payload @{
        recommended_model = 'TF-IDF + Logistic Regression'
        model_in_use = 'Policy fallback'
        is_using_recommended_model = $false
        updates = 15
        examples_seen = 246
      }
      continue
    }

    if ($path -eq '/agent/task_1/logs') {
      $limit = 100
      if ($context.Request.QueryString['limit']) {
        try { $limit = [int]$context.Request.QueryString['limit'] } catch { }
      }
      if ($limit -le 0) { $limit = 100 }
      Send-Json -Context $context -Payload @{ entries = @($agentLogState | Select-Object -Last $limit) }
      continue
    }

    if ($path -eq '/support/stats') {
      Send-Json -Context $context -Payload @{
        entries = 0
        epochs = $trainingState.Count
        records = 1200
      }
      continue
    }

    if ($path -eq '/support/search') {
      $body = Read-JsonBody -Request $context.Request
      $query = if ($body -and $body.PSObject.Properties.Name -contains 'query') { [string]$body.query } else { '' }
      $topK = if ($body -and $body.PSObject.Properties.Name -contains 'top_k') { [int]$body.top_k } else { 5 }
      if ($topK -le 0) { $topK = 5 }
      $results = @(
        @{ title = 'Password reset workflow'; score = 0.96; snippet = 'Reset account access and confirm identity before proceeding.' }
        @{ title = 'Refund policy'; score = 0.91; snippet = 'Refunds are approved within the published return window.' }
      ) | Select-Object -First $topK
      Send-Json -Context $context -Payload @{
        query = $query
        top_k = $topK
        matches = $results
        results = $results
      }
      continue
    }

    Send-Json -Context $context -Payload @{ detail = 'Not found'; path = $path } -StatusCode 404
  } catch {
    Send-Json -Context $context -Payload @{ detail = $_.Exception.Message } -StatusCode 500
  }
}
