# Requires -Version 5.1
<#
.SYNOPSIS
    GUI launcher for Secure-ADtrust.ps1 using WPF.
#>

# 1. Load the required .NET assemblies for WPF
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# 2. Dot-source the main engine script (matching your exact filename)
$EngineScript = Join-Path -Path $PSScriptRoot -ChildPath "Secure-ADtrust.ps1"
if (Test-Path $EngineScript) {
    . $EngineScript
} else {
    [System.Windows.MessageBox]::Show("Cannot find Secure-ADtrust.ps1 in the current directory. Please ensure both files are in the same folder.", "Error", "OK", "Error")
    exit
}

# 3. Define the WPF GUI in XAML (Native System Theme)
$XAML = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xml:lang="en-US"
        Title="SecureAD Trust Configuration" Height="600" Width="480"
        ThemeMode="System"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize"
        FontFamily="Segoe UI">
    <Grid Margin="15, 15, 15, 15">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
        </Grid.RowDefinitions>

        <GroupBox Grid.Row="0" Margin="0, 0, 0, 15" Padding="10">
            <GroupBox.Header>
                <TextBlock Text="Source Domain Configuration" FontWeight="Bold"/>
            </GroupBox.Header>
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="130"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <TextBlock Text="Source DC FQDN:" Grid.Row="0" Grid.Column="0" Margin="0, 5, 0, 5"/>
                <TextBox Name="txtSourceDC" Grid.Row="0" Grid.Column="1" Margin="0, 5, 0, 5" Padding="2"/>

                <TextBlock Text="Domain FQDN:" Grid.Row="1" Grid.Column="0" Margin="0, 5, 0, 5"/>
                <TextBox Name="txtSourceDomain" Grid.Row="1" Grid.Column="1" Margin="0, 5, 0, 5" Padding="2"/>

                <TextBlock Text="Admin User (UPN):" Grid.Row="2" Grid.Column="0" Margin="0, 5, 0, 5"/>
                <TextBox Name="txtSourceUser" Grid.Row="2" Grid.Column="1" Margin="0, 5, 0, 5" Padding="2" ToolTip="e.g. administrator@domain.local"/>

                <TextBlock Text="Admin Password:" Grid.Row="3" Grid.Column="0" Margin="0, 5, 0, 5"/>
                <PasswordBox Name="pwdSourcePass" Grid.Row="3" Grid.Column="1" Margin="0, 5, 0, 5" Padding="2"/>
            </Grid>
        </GroupBox>

        <GroupBox Grid.Row="1" Margin="0, 0, 0, 15" Padding="10">
            <GroupBox.Header>
                <TextBlock Text="Target Domain Configuration" FontWeight="Bold"/>
            </GroupBox.Header>
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="130"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <TextBlock Text="Target DC FQDN:" Grid.Row="0" Grid.Column="0" Margin="0, 5, 0, 5"/>
                <TextBox Name="txtTargetDC" Grid.Row="0" Grid.Column="1" Margin="0, 5, 0, 5" Padding="2"/>

                <TextBlock Text="Domain FQDN:" Grid.Row="1" Grid.Column="0" Margin="0, 5, 0, 5"/>
                <TextBox Name="txtTargetDomain" Grid.Row="1" Grid.Column="1" Margin="0, 5, 0, 5" Padding="2"/>

                <TextBlock Text="Admin User (UPN):" Grid.Row="2" Grid.Column="0" Margin="0, 5, 0, 5"/>
                <TextBox Name="txtTargetUser" Grid.Row="2" Grid.Column="1" Margin="0, 5, 0, 5" Padding="2" ToolTip="e.g. administrator@domain.local"/>

                <TextBlock Text="Admin Password:" Grid.Row="3" Grid.Column="0" Margin="0, 5, 0, 5"/>
                <PasswordBox Name="pwdTargetPass" Grid.Row="3" Grid.Column="1" Margin="0, 5, 0, 5" Padding="2"/>
            </Grid>
        </GroupBox>

        <GroupBox Grid.Row="2" Margin="0, 0, 0, 15" Padding="10">
            <GroupBox.Header>
                <TextBlock Text="Trust Settings" FontWeight="Bold"/>
            </GroupBox.Header>
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="130"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <TextBlock Text="Direction:" Grid.Row="0" Grid.Column="0" Margin="0, 5, 0, 10"/>
                <ComboBox Name="cmbDirection" Grid.Row="0" Grid.Column="1" Margin="0, 5, 0, 10" SelectedIndex="0">
                    <ComboBoxItem Content="BiDirectional"/>
                    <ComboBoxItem Content="Inbound"/>
                    <ComboBoxItem Content="Outbound"/>
                </ComboBox>

                <CheckBox Name="chkSelectiveAuth" Content="Enable Selective Authentication" Grid.Row="1" Grid.ColumnSpan="2" Margin="0, 5, 0, 5" FontWeight="Bold"/>
            </Grid>
        </GroupBox>

        <Button Name="btnExecute" Content="Create Trust" Grid.Row="3" Height="35" FontWeight="Bold" FontSize="14" Cursor="Hand" Margin="0,5,0,0"/>
    </Grid>
</Window>
"@

# 4. Parse the XAML into a WPF Window object
try {
    $Window = [Windows.Markup.XamlReader]::Parse($XAML)
} catch {
    Write-Error "Failed to load XAML.`nMessage: $($_.Exception.Message)`nInner: $($_.Exception.InnerException.Message)"
    exit
}

# 5. Map XAML controls to PowerShell variables
$txtSourceDC      = $Window.FindName("txtSourceDC")
$txtSourceDomain  = $Window.FindName("txtSourceDomain")
$txtSourceUser    = $Window.FindName("txtSourceUser")
$pwdSourcePass    = $Window.FindName("pwdSourcePass")

$txtTargetDC      = $Window.FindName("txtTargetDC")
$txtTargetDomain  = $Window.FindName("txtTargetDomain")
$txtTargetUser    = $Window.FindName("txtTargetUser")
$pwdTargetPass    = $Window.FindName("pwdTargetPass")

$cmbDirection     = $Window.FindName("cmbDirection")
$chkSelectiveAuth = $Window.FindName("chkSelectiveAuth")
$btnExecute       = $Window.FindName("btnExecute")

# 6. Button Click Event Logic
$btnExecute.Add_Click({
    # Validate required fields
    if ([string]::IsNullOrWhiteSpace($txtSourceDC.Text) -or [string]::IsNullOrWhiteSpace($txtTargetDC.Text)) {
        [System.Windows.MessageBox]::Show("Please fill in all Domain Controller FQDN fields.", "Validation Error", "OK", "Warning")
        return
    }

    # Convert plain text passwords to SecureString securely
    $SourceSecurePass = ConvertTo-SecureString -String $pwdSourcePass.Password -AsPlainText -Force
    $TargetSecurePass = ConvertTo-SecureString -String $pwdTargetPass.Password -AsPlainText -Force

    # Create PSCredential objects
    $SourceCred = New-Object System.Management.Automation.PSCredential ($txtSourceUser.Text, $SourceSecurePass)
    $TargetCred = New-Object System.Management.Automation.PSCredential ($txtTargetUser.Text, $TargetSecurePass)

    # Change cursor to Wait
    $Window.Cursor = [System.Windows.Input.Cursors]::Wait
    $btnExecute.IsEnabled = $false
    $btnExecute.Content = "Executing..."

    # Create parameter hash table for splatting
    $TrustParams = @{
        SourceDC     = $txtSourceDC.Text
        SourceDomain = $txtSourceDomain.Text
        SourceCred   = $SourceCred
        TargetDC     = $txtTargetDC.Text
        TargetDomain = $txtTargetDomain.Text
        TargetCred   = $TargetCred
        Direction    = $cmbDirection.Text
    }

    if ($chkSelectiveAuth.IsChecked) {
        $TrustParams.SelectiveAuthentication = $true
    }

    # Execute the backend function
    try {
        Set-ADtrust @TrustParams
        [System.Windows.MessageBox]::Show("Trust setup operation has completed! Check the console output for detailed validation logs.", "Success", "OK", "Information")
    } catch {
        [System.Windows.MessageBox]::Show("An error occurred during execution: $_", "Execution Error", "OK", "Error")
    } finally {
        # Restore UI state
        $Window.Cursor = [System.Windows.Input.Cursors]::Arrow
        $btnExecute.IsEnabled = $true
        $btnExecute.Content = "Create Trust"
    }
})

# 7. Launch the GUI
$Window.ShowDialog() | Out-Null
