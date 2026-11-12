# Kairos / Wealth Tree - full functional test (backend + both AI agents)
# Needs: kairos_server.py running (port 8090) and the backend running (port 8080).
# Run from anywhere:   powershell -ExecutionPolicy Bypass -File backend\tools\smoke-test.ps1
# Options:             -Base http://localhost:8080  -Bridge http://localhost:8090  -Wait 150

param(
    [string]$Base = "http://localhost:8080",
    [string]$Bridge = "http://localhost:8090",
    [int]$Wait = 150
)

$ErrorActionPreference = "Stop"
$script:pass = 0; $script:fail = 0; $script:warn = 0
$people = @("lena", "alex", "maya", "max")

function Check($name, [bool]$ok, $detail = "") {
    if ($ok) { $script:pass++; Write-Host ("  PASS  " + $name + "  " + $detail) -ForegroundColor Green }
    else { $script:fail++; Write-Host ("  FAIL  " + $name + "  " + $detail) -ForegroundColor Red }
}
function Note($text) { $script:warn++; Write-Host ("  NOTE  " + $text) -ForegroundColor Yellow }
function Section($t) { Write-Host ""; Write-Host ("== " + $t) -ForegroundColor Cyan }
function Get($path) { Invoke-RestMethod -Uri ($Base + $path) -TimeoutSec 130 }
function Post($path) { Invoke-RestMethod -Method Post -Uri ($Base + $path) -TimeoutSec 130 }

function WaitPrediction($id) {
    $t0 = Get-Date
    do {
        $r = Get "/api/users/$id/prediction"
        if ($r.status -ne "RUNNING") { break }
        Start-Sleep -Seconds 3
    } while (((Get-Date) - $t0).TotalSeconds -lt $Wait)
    return @{ r = $r; secs = [math]::Round(((Get-Date) - $t0).TotalSeconds) }
}

# ------------------------------------------------------------------------------------------------
Section "0. Services are up"
try { $h = Invoke-RestMethod -Uri ($Bridge + "/health") -TimeoutSec 5
      Check "Kairos bridge" $true ("engine " + $h.engine_version + ", prediction agent " + $h.prediction_agent + ", action agent " + $h.action_agent)
      if ($h.live_ai) { Check "Live AI key loaded" $true } else { Note "Bridge has NO key: agents will use rule-based text (put HIP_API_KEY in prediction-agent\.env, restart the bridge)" } }
catch { Check "Kairos bridge reachable at $Bridge" $false "start it: python backend\tools\kairos_server.py --agent-dir prediction-agent" }
try { $users = Get "/api/users"; Check "Backend reachable" $true ("$(@($users).Count) customers") }
catch { Check "Backend reachable at $Base" $false "start the backend first"; exit 1 }

Section "1. Reset to demo data"
$r = Post "/api/demo/reset"
Check "Reset" ($r.status -like "reset*")
Check "Four demo customers" (@($users).Count -eq 4) (($users | ForEach-Object { $_.id }) -join ", ")

# ------------------------------------------------------------------------------------------------
Section "2. Tree, scanner, benchmarks, recommendations, storm (per customer)"
foreach ($id in $people) {
    $t = Get "/api/users/$id/tree"
    Check "$id tree" ((@($t.roots).Count -eq 4) -and (@($t.leaves).Count -gt 0) -and ($t.overallHealth -ge 0)) ("health " + $t.overallHealth + ", " + $t.headline)
    Check "$id wellbeing (CFPB) in tree" ($null -ne $t.wellbeing.predictedScore) ("CFPB " + [math]::Round($t.wellbeing.predictedScore, 1) + ", percentile " + [math]::Round($t.wellbeing.percentile))
    $peer = @($t.leaves | Where-Object { $_.peerGroup -like "*Destatis*" })
    Check "$id leaves judged vs Destatis peers" ($peer.Count -eq @($t.leaves).Count) ($t.leaves[0].detail)
    $s = Get "/api/users/$id/scanner"
    Check "$id scanner" ($null -ne $s.predicted_score) ("age band " + $s.age_band + ", missing: " + ($s.missing_dimensions -join ","))
    $recs = Get "/api/users/$id/recommendations"
    Check "$id recommendations" (@($recs).Count -gt 0) ("$(@($recs).Count) - top: " + @($recs)[0].title)
    $st = Post "/api/users/$id/storm"
    Check "$id storm test" ($st.message.Length -gt 0) ($st.message)
    $in = Get "/api/users/$id/intake"
    Check "$id intake for the team's engine" (($in.wealth_total -gt 0) -and (@($in.goals).Count -gt 0) -and ($null -ne $in.spending)) ("wealth " + $in.wealth_total + ", cash " + $in.cash + ", crash " + $in.crash_reaction)
}
$wi = Invoke-RestMethod -Method Post -Uri ($Base + "/api/users/lena/scanner/what-if") -ContentType "application/json" -Body '{"ABSORBSHOCK":4}' -TimeoutSec 30
Check "Scanner what-if" ($null -ne $wi.predicted_gain) ("Lena ABSORBSHOCK 4: gain " + [math]::Round($wi.predicted_gain, 2) + " CFPB points")
$sim = Invoke-RestMethod -Method Post -Uri ($Base + "/api/users/maya/simulate") -ContentType "application/json" -Body '{"months":12}' -TimeoutSec 30
Check "12-month projection" ($sim.scoreAfter -gt $sim.scoreBefore) ("Maya " + $sim.scoreBefore + " -> " + $sim.scoreAfter)

# ------------------------------------------------------------------------------------------------
Section "3. AI agents: engine + prediction agent + action agent (per customer)"
Write-Host "  Starting a fresh AI run for everyone (the 4 run in parallel; up to a few minutes with live AI)..."
foreach ($id in $people) { $null = Post "/api/users/$id/prediction/refresh" }
foreach ($id in $people) {
    $w = WaitPrediction $id
    $r = $w.r
    if ($r.status -ne "READY") { Check "$id pipeline" $false ($r.status + " " + $r.error); continue }
    $ps = $r.prediction.source; $as = $r.actions.source
    Check "$id pipeline READY" $true ("in $($w.secs) s")
    Check "$id engine scenarios" (@($r.engine.scenarios).Count -ge 2) (($r.engine.scenarios | ForEach-Object { $_.id }) -join ", ")
    if (@($r.engine.intake_warnings).Count -gt 0) { Note ("$id intake warnings: " + ($r.engine.intake_warnings -join " | ")) }
    Check "$id prediction agent answered" ($null -ne $r.prediction.output.headline) ("source " + $ps + ": " + $r.prediction.output.headline)
    Check "$id action agent answered" (@($r.actions.output.actions).Count -gt 0) ("source " + $as + ", " + @($r.actions.output.actions).Count + " actions: " + (($r.actions.output.actions | Select-Object -First 3 | ForEach-Object { $_.title }) -join " / "))
    foreach ($pair in @(@("prediction", $ps), @("action", $as))) {
        if ($pair[1] -eq "ai") { Check ("$id " + $pair[0] + " agent used LIVE AI") $true }
        elseif ($pair[1] -eq "ai_partial") { Note ("$id " + $pair[0] + " agent: AI text partly replaced by the guardrails (ai_partial)") }
        else { Note ("$id " + $pair[0] + " agent used rule-based text (source " + $pair[1] + ")") }
    }
    if (@($r.prediction.problems).Count -gt 0) { Note ("$id prediction guardrail notes: " + ($r.prediction.problems -join " | ")) }
    Check "$id fan chart" (@($r.chart.todayPath.p50).Count -gt 1) ("years " + $r.chart.years)
    $k = Get "/api/users/$id/kairos?wait=5"
    Check "$id projects-section format (/kairos)" (($null -ne $k.intake) -and ($null -ne $k.prediction_agent) -and ($null -ne $k.action_agent)) ("name " + $k.intake.name)
}

# ------------------------------------------------------------------------------------------------
Section "4. Memory: commit, a month passes, verified by data, predictions follow"
$before = Get "/api/users/maya/tree"
foreach ($a in @("act-limit-eating_out", "act-buffer", "act-protect")) { $c = Post "/api/users/maya/actions/$a/commit" }
Check "Commit 3 actions" (@($c.actions | Where-Object { $_.status -eq "COMMITTED" }).Count -ge 3)
$adv = Post "/api/users/maya/advance-month?months=3"
Check "Advance 3 months" (@($adv.months).Count -eq 3) (($adv.months | ForEach-Object { "" + $_.month + ":" + $_.treeHealth }) -join "  ")
$adv.months[0].events | ForEach-Object { Write-Host ("        " + $_) }
$p = Get "/api/users/maya/progress"
$verified = @($p.actions | Where-Object { $_.status -eq "VERIFIED" }).Count
Check "Actions verified by the data" ($verified -ge 2) ("$verified verified")
Check "Tree changed" ($adv.tree.overallHealth -ne $before.overallHealth) ("" + $before.overallHealth + " -> " + $adv.tree.overallHealth + ", trend " + $p.trend)
$hist = Get "/api/users/maya/history"
Check "History (4 snapshots)" (@($hist.snapshots).Count -eq 4)
$in2 = Get "/api/users/maya/intake"
Check "Intake follows progress" (($in2.disability_cover -eq $true) -and ($in2.has_buffer_plan -eq $true)) ("cover " + $in2.disability_cover + ", buffer plan " + $in2.has_buffer_plan)
$w = WaitPrediction "maya"
$ids = ($w.r.engine.scenarios | ForEach-Object { $_.id })
Check "Prediction re-ran with the new data" (($w.r.status -eq "READY") -and -not ($ids -contains "cover")) ("in $($w.secs) s, scenarios now: " + ($ids -join ", "))

Section "5. Next step replaces the old limit"
$recs = Get "/api/users/maya/recommendations"
$eat = $recs | Where-Object { $_.action.id -eq "act-limit-eating_out" }
if ($eat) {
    $c = Post "/api/users/maya/actions/act-limit-eating_out/commit"
    $rep = @($c.actions | Where-Object { $_.actionId -eq "act-limit-eating_out" -and $_.status -eq "REPLACED" }).Count
    if ($eat.action.monthlyAmount -ne 450) { Check "Next step replaces the old limit" ($rep -ge 1) ("new limit " + $eat.action.monthlyAmount) }
    else { Note "Eating-out limit unchanged after 3 months; next-step check skipped" }
} else { Note "No eating-out recommendation left (already healthy); next-step check skipped" }

Section "6. Clean up"
$r = Post "/api/demo/reset"
Check "Reset to demo data" ($r.status -like "reset*")

Write-Host ""
$color = if ($script:fail -eq 0) { "Green" } else { "Red" }
Write-Host ("RESULT: " + $script:pass + " passed, " + $script:fail + " failed, " + $script:warn + " notes") -ForegroundColor $color
