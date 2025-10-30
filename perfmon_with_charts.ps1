# ======================================================================================
# Performance Monitor with Timestamp X-axis and Fixed 0-100 Y-axis Charts
# ======================================================================================

# ---------------------------------------------
# Configuration
# ---------------------------------------------
$SampleIntervalSec = 15
$DurationInput = Read-Host "Enter monitoring duration (in minutes)"

# ---------------------------------------------
# Validate Input
# ---------------------------------------------
if (-not ($DurationInput -match '^\d+$')) {
    Write-Error "Please enter a valid positive integer for duration."
    exit
}
$DurationMin = [int]$DurationInput
if ($DurationMin -le 0) {
    Write-Error "Duration must be greater than zero."
    exit
}

# ---------------------------------------------
# Setup Paths and Variables
# ---------------------------------------------
$Hostname   = $env:COMPUTERNAME
$DateString = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$ScriptDir  = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
$OutputFile = Join-Path $ScriptDir "Perf_${Hostname}_$DateString.csv"
$EndTime    = (Get-Date).AddMinutes($DurationMin)
$StartTime  = Get-Date

"timestamp,cpu,memory" | Out-File -FilePath $OutputFile -Encoding utf8
Write-Host "Monitoring started on $Hostname for $DurationMin minute(s)..."
Write-Host "Sampling every $SampleIntervalSec seconds."
Write-Host "Press Ctrl+C to stop early.`n"

# ---------------------------------------------
# Helper Functions
# ---------------------------------------------
function Get-MemoryUsage {
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        $total = $os.TotalVisibleMemorySize
        $free  = $os.FreePhysicalMemory
        return [math]::Round((($total - $free) / $total) * 100, 2)
    } catch {
        return 0
    }
}

function Get-CPUUsage {
    try {
        $cpu = Get-Counter '\Processor(_Total)\% Processor Time'
        return [math]::Round($cpu.CounterSamples[0].CookedValue, 2)
    } catch {
        return 0
    }
}

# ---------------------------------------------
# Monitoring Loop
# ---------------------------------------------
$sampleCount = 0
try {
    while ((Get-Date) -lt $EndTime) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $cpu = Get-CPUUsage
        $mem = Get-MemoryUsage
        "$timestamp,$cpu,$mem" | Add-Content $OutputFile

        $sampleCount++
        $cpuFmt = ("{0:N2}" -f $cpu)
        $memFmt = ("{0:N2}" -f $mem)
        Write-Host ("[{0}] CPU={1}% | MEM={2}%" -f $sampleCount, $cpuFmt, $memFmt)

        Start-Sleep -Seconds $SampleIntervalSec
    }
} catch {
    Write-Error "Monitoring interrupted: $_"
}

Write-Host "`nMonitoring complete. Data saved to:`n$OutputFile`n"

# ---------------------------------------------
# Chart Creation Function
# ---------------------------------------------
function Create-PerformanceGraphs {
    param (
        [string]$CsvPath,
        [string]$HostName,
        [datetime]$StartTime,
        [int]$Duration
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Windows.Forms.DataVisualization

    $data = Import-Csv $CsvPath
    if (-not $data) {
        Write-Error "No data found in CSV: $CsvPath"
        return
    }

    function Make-Chart {
        param (
            [string]$Title,
            [string]$ValueField,
            [string]$OutputPath,
            [System.Drawing.Color]$Color
        )

        $chart = New-Object System.Windows.Forms.DataVisualization.Charting.Chart
        $chart.Width = 1920
        $chart.Height = 1080
        $chart.BackColor = [System.Drawing.Color]::White
        $chart.AntiAliasing = [System.Windows.Forms.DataVisualization.Charting.AntiAliasingStyles]::All

        # Define chart area
        $area = New-Object System.Windows.Forms.DataVisualization.Charting.ChartArea "MainArea"
        $area.AxisX.Title = "Timestamp"
        $area.AxisX.TitleFont = "Segoe UI, 11pt"
        $area.AxisY.Title = "Usage (%)"
        $area.AxisY.TitleFont = "Segoe UI, 11pt"

        # Y-axis setup (0-100 with 10 unit intervals)
        $area.AxisY.Minimum = 0
        $area.AxisY.Maximum = 100
        $area.AxisY.Interval = 10
        $area.AxisY.MajorGrid.LineColor = "LightGray"
        $area.AxisY.IsStartedFromZero = $true

        # X-axis setup for timestamps
        $area.AxisX.LabelStyle.Angle = -45
        $area.AxisX.MajorGrid.LineColor = "LightGray"
        $area.AxisX.IntervalAutoMode = [System.Windows.Forms.DataVisualization.Charting.IntervalAutoMode]::VariableCount
        $area.AxisX.LabelStyle.Format = "HH:mm:ss"
        
        # Position adjustments
        $area.Position.X = 5
        $area.Position.Y = 10
        $area.Position.Width = 90
        $area.Position.Height = 80
        
        $area.InnerPlotPosition.X = 10
        $area.InnerPlotPosition.Y = 5
        $area.InnerPlotPosition.Width = 85
        $area.InnerPlotPosition.Height = 85

        $chart.ChartAreas.Add($area)

        # Series setup
        $series = New-Object System.Windows.Forms.DataVisualization.Charting.Series $ValueField
        $series.ChartType = [System.Windows.Forms.DataVisualization.Charting.SeriesChartType]::Spline
        $series.BorderWidth = 3
        $series.Color = $Color
        $series.MarkerStyle = "Circle"
        $series.MarkerSize = 5
        $series.IsVisibleInLegend = $false
        $series.XValueType = [System.Windows.Forms.DataVisualization.Charting.ChartValueType]::DateTime

        # Plot points with timestamps
        foreach ($row in $data) {
            try {
                $timestamp = [DateTime]::ParseExact($row.timestamp, "yyyy-MM-dd HH:mm:ss", $null)
                $value = [double]$row.$ValueField
                $series.Points.AddXY($timestamp, $value)
            } catch {
                Write-Warning "Skipped invalid data point: $($row.timestamp)"
            }
        }

        $chart.Series.Add($series)
        $chart.Titles.Add("$Title ($HostName)").Font = "Segoe UI, 14pt, style=Bold"

        # Save chart
        $chart.SaveImage($OutputPath, "Png")
    }

    # CPU Chart
    $cpuChart = $CsvPath.Replace(".csv", "_CPU.png")
    Make-Chart -Title "CPU Usage over $Duration min" -ValueField "cpu" -OutputPath $cpuChart -Color ([System.Drawing.Color]::RoyalBlue)
    Write-Host "CPU chart saved: $cpuChart"

    # Memory Chart
    $memChart = $CsvPath.Replace(".csv", "_Memory.png")
    Make-Chart -Title "Memory Usage over $Duration min" -ValueField "memory" -OutputPath $memChart -Color ([System.Drawing.Color]::ForestGreen)
    Write-Host "Memory chart saved: $memChart"
}

# ---------------------------------------------
# Generate Charts
# ---------------------------------------------
Create-PerformanceGraphs -CsvPath $OutputFile -HostName $Hostname -StartTime $StartTime -Duration $DurationMin

Write-Host "`nAll charts created successfully!`n"
