# SCRIPT BEGINS HERE

# ======================================================================================
# Variable Declarations
# ======================================================================================
$sampleTime = 15 
$durationRaw = Read-Host "Enter duration to run the monitoring (in minutes)"

# ======================================================================================
# Input Validation
# ======================================================================================
if (-not ($durationRaw -match '^-?\d+$')) { 
    Write-Error "Please enter a valid positive integer for duration." 
    exit 
} 
$duration_min = [int]$durationRaw 
if ($duration_min -le 0) { 
    Write-Error "Please enter a valid positive integer greater than zero." 
    exit 
}

# ======================================================================================
# Setup File and Hostname
# ======================================================================================
$endTime = (Get-Date).AddMinutes($duration_min) 
$hostname = $env:COMPUTERNAME 
$dateString = Get-Date -Format "yyyy-MM-dd_HH-mm-ss" 
$scriptFolder = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent 
$outputFile = Join-Path -Path $scriptFolder -ChildPath ("Perform_" + $hostname + "_" + $dateString + ".csv")

# Create CSV file with header
"timestamp,cpu,memory" | Out-File -FilePath $outputFile -Encoding utf8

# ======================================================================================
# Function Definitions
# ======================================================================================
function Get-MemoryUsage { 
    $os = Get-CimInstance -ClassName Win32_OperatingSystem 
    $totalMem = $os.TotalVisibleMemorySize 
    $freeMem = $os.FreePhysicalMemory 
    $usedMem = $totalMem - $freeMem 
    $memUsagePercent = ($usedMem / $totalMem) * 100 
    return [math]::Round($memUsagePercent, 2) 
} 

function Get-CPUUsage { 
    $cpuSample = Get-Counter '\Processor(_Total)\% Processor Time' 
    return [math]::Round($cpuSample.CounterSamples[0].CookedValue, 2) 
}

# ======================================================================================
# Core Monitoring Loop
# ======================================================================================
while ((Get-Date) -lt $endTime) { 
    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss" 
    $CPU = Get-CPUUsage 
    $Memory = Get-MemoryUsage 
    $line = "$TimeStamp,$CPU,$Memory" 
    Add-Content -Path $outputFile -Value $line 
    Start-Sleep -Seconds $sampleTime 
} 

Write-Host "Monitoring complete. Data saved to $outputFile"

# ======================================================================================
# Function to Create Graphs using .NET libraries
# ======================================================================================
function Create-PerformanceGraphs {
    param (
        [string]$CsvPath,
        [string]$HostName,
        [int]$Duration
    )

    # Load required .NET assemblies
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Windows.Forms.DataVisualization

    # Define chart properties
    $chartFont = 'Segoe UI, 10pt'
    $chartTitleFont = 'Segoe UI, 12pt, style=Bold'
    $chartLegendFont = 'Segoe UI, 9pt'
    $chartMarkerSize = 5

    # Read data from CSV
    $data = Import-Csv -Path $CsvPath | Select-Object timestamp, cpu, memory

    # Helper function to create a chart
    function Create-Chart {
        param (
            [string]$Title,
            [string]$SeriesName,
            [string]$XAxisTitle,
            [string]$YAxisTitle,
            [string]$ValueField,
            [string]$OutputPath,
            [System.Drawing.Color]$SeriesColor
        )

        $chart = New-Object System.Windows.Forms.DataVisualization.Charting.Chart
        $chart.Size = New-Object System.Drawing.Size(1920, 1080)
        $chart.BackColor = [System.Drawing.Color]::White

        $chartArea = New-Object System.Windows.Forms.DataVisualization.Charting.ChartArea
        $chartArea.Name = "MainArea"
        $chartArea.AxisX.Title = $XAxisTitle
        $chartArea.AxisX.TitleFont = $chartFont
        $chartArea.AxisX.LabelStyle.Format = "yyyy-MM-dd HH:mm:ss"
        $chartArea.AxisX.LabelStyle.Font = $chartLegendFont
		$chartArea.AxisX.LabelStyle.Angle = -45  # Rotate X-axis labels
        $chartArea.AxisX.IntervalAutoMode = [System.Windows.Forms.DataVisualization.Charting.IntervalAutoMode]::VariableCount
        $chartArea.AxisX.IsLabelAutoFit = $false

        $chartArea.AxisX.MajorGrid.LineColor = 'LightGray'

        $chartArea.AxisY.Title = $YAxisTitle
        $chartArea.AxisY.TitleFont = $chartFont
        $chartArea.AxisY.Minimum = 0
        $chartArea.AxisY.Maximum = 100
        $chartArea.AxisY.MajorGrid.LineColor = 'LightGray'

        $chart.ChartAreas.Add($chartArea) | Out-Null

        $series = New-Object System.Windows.Forms.DataVisualization.Charting.Series
        $series.Name = $SeriesName
        $series.ChartType = [System.Windows.Forms.DataVisualization.Charting.SeriesChartType]::Spline
        $series.Color = $SeriesColor
        $series.MarkerStyle = [System.Windows.Forms.DataVisualization.Charting.MarkerStyle]::Circle
        $series.MarkerSize = $chartMarkerSize
		$series.BorderWidth = 3
        $series.ToolTip = "Time: #VALX{HH:mm:ss}`n${SeriesName}: #VALY{F2}%"
        $series.IsVisibleInLegend = $true
        $series.IsValueShownAsLabel = $false

        $chart.Series.Add($series) | Out-Null

        $data | ForEach-Object {
            $series.Points.AddXY($_."timestamp", $_.$ValueField) | Out-Null
        }

        $chart.Titles.Add($Title).Font = $chartTitleFont

        $legend = New-Object System.Windows.Forms.DataVisualization.Charting.Legend("Legend1")
        $legend.Docking = [System.Windows.Forms.DataVisualization.Charting.Docking]::Bottom
        $legend.Font = $chartLegendFont
        $legend.BackColor = [System.Drawing.Color]::White
        $legend.BorderColor = [System.Drawing.Color]::Gray
        $chart.Legends.Add($legend) | Out-Null

        $chart.SaveImage($OutputPath, [System.Windows.Forms.DataVisualization.Charting.ChartImageFormat]::Png)
    }

    # Create CPU Chart
    $cpuChartPath = $CsvPath.Replace(".csv", "_cpu.png")
    Create-Chart -Title "$HostName CPU Usage over $Duration minutes" `
                 -SeriesName "CPU Usage (%)" `
                 -XAxisTitle "Timestamp" `
                 -YAxisTitle "CPU Usage (%)" `
                 -ValueField "cpu" `
                 -OutputPath $cpuChartPath `
                 -SeriesColor ([System.Drawing.Color]::RoyalBlue)

    # Create Memory Chart
    $memChartPath = $CsvPath.Replace(".csv", "_memory.png")
    Create-Chart -Title "$HostName Memory Usage over $Duration minutes" `
                 -SeriesName "Memory Usage (%)" `
                 -XAxisTitle "Timestamp" `
                 -YAxisTitle "Memory Usage (%)" `
                 -ValueField "memory" `
                 -OutputPath $memChartPath `
                 -SeriesColor ([System.Drawing.Color]::ForestGreen)

    Write-Host "✅ CPU graph saved to: $cpuChartPath"
    Write-Host "✅ Memory graph saved to: $memChartPath"
}


# ======================================================================================
# Call the Graphing Function after Monitoring
# ======================================================================================
Create-PerformanceGraphs -CsvPath $outputFile -HostName $hostname -Duration $duration_min

# SCRIPT ENDS HERE
