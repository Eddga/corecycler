<#
.AUTHOR
    sp00n, Eddga
.VERSION
    0.9.5.0alpha2
.DESCRIPTION
    Sets the affinity of the selected stress test program process to only one core and cycles through
    all the cores to test the stability of a Curve Optimizer setting
.LINK
    https://github.com/sp00n/corecycler
.LICENSE
    Creative Commons "CC BY-NC-SA"
    https://creativecommons.org/licenses/by-nc-sa/4.0/
    https://creativecommons.org/licenses/by-nc-sa/4.0/legalcode
.NOTES
    Please excuse my amateurish code in this file, it's my first attempt at writing in PowerShell ._.
#>

# Workaround PSScriptRoot not populated when manually running and debugging code - https://github.com/PowerShell/vscode-powershell/issues/633#issuecomment-1474495604
$cmd = $PSCommandPath # blank if F8
if ( -not $cmd -and $script:psEditor )  { $cmd = $script:psEditor.GetEditorContext().CurrentFile.Path }
if ( -not $cmd -and $script:psISE    )  { $cmd = $script:psISE.CurrentFile.FullPath                   }
$root = Split-Path $cmd -Parent

# Global variables
$version                    = '0.9.5.0alpha2'
$startDate                  = Get-Date
$startDateTime              = Get-Date -format yyyy-MM-dd_HH-mm-ss
$logFilePath                = 'logs'
$logFilePathAbsolute        = $root + '\' + $logFilePath + '\'
$logFileName                = 'CoreCycler_' + $startDateTime + '.log'
$logFileFullPath            = $logFilePathAbsolute + $logFileName
$helpersPathAbsolute        = $root + '\helpers\'
$settings                   = $null
$selectedStressTestProgram  = $null
$useAutomaticRuntimePerCore = $false
$windowProcess              = $null
$windowProcessId            = $null
$stressTestProcess          = $null
$stressTestProcessId        = $null
$processCounterPathId       = $null
$processCounterPathTime     = $null
$coresWithError             = $null
$coresWithErrorsCounter     = $null
#deletevar? $previousError              = $null
$stressTestLogFileName      = $null
$stressTestLogFilePath      = $null
$prime95CPUSettings         = $null
$FFTSizes                   = $null
$FFTMinMaxValues            = $null
$minFFTSize                 = $null
$maxFFTSize                 = $null
$fftSubarray                = $null
$lastFilePosition           = 0
$lineCounter                = 0
$newLogEntries              = [System.Collections.ArrayList]::new()
$allLogEntries              = [System.Collections.ArrayList]::new()
$allFFTLogEntries           = [System.Collections.ArrayList]::new()
$allTestLogEntries          = [System.Collections.ArrayList]::new()
$cpuTestMode                = $null
$coreTestOrderMode          = $null
$coreTestOrderCustom        = @()
$scriptExit                 = $false
$fatalError                 = $false
#deletevar? $otherError                 = $false
$previousFileSize           = $null
$previousPassedFFTSize      = $null
$previousPassedFFTEntry     = $null
$previousPassedTest         = $null
$previousPassedTestEntry    = $null
$isPrime95                  = $false
$isAida64                   = $false
$isYCruncher                = $false
$isYCruncherWithLogging     = $false
$cpuCheckIterations         = 0

# Parameters that are controllable by debug settings
$debugSettingsActive                        = $false
$disableCpuUtilizationCheckDefault          = 0
$enableCpuFrequencyCheckDefault             = 0
$tickIntervalDefault                        = 10
$delayFirstErrorCheckDefault                = 0
$stressTestProgramPriorityDefault           = 'High'
$stressTestProgramWindowToForegroundDefault = 0
$suspensionTimeDefault                      = 1000


$disableCpuUtilizationCheck                 = $disableCpuUtilizationCheckDefault
$enableCpuFrequencyCheck                    = $enableCpuFrequencyCheckDefault
$tickInterval                               = $tickIntervalDefault
$delayFirstErrorCheck                       = $delayFirstErrorCheckDefault
$stressTestProgramPriority                  = $stressTestProgramPriorityDefault
$stressTestProgramWindowToForeground        = $stressTestProgramWindowToForegroundDefault
$suspensionTime                             = $suspensionTimeDefault


# Set the title
$host.UI.RawUI.WindowTitle = ('CoreCycler ' + $version + ' starting')


# Stress test program executables and paths
# The window behaviours:
# 0 = Hide
# 1 = NormalFocus
# 2 = MinimizedFocus
# 3 = MaximizedFocus
# 4 = NormalNoFocus
# 6 = MinimizedNoFocus
$stressTestPrograms = @{
    'prime95' = @{
        'displayName'         = 'Prime95'
        'processName'         = 'prime95'
        'processNameExt'      = 'exe'
        'processNameForLoad'  = 'prime95'
        'processPath'         = 'test_programs\p95'
        'installPath'         = 'test_programs\p95'
        'configName'          = $null
        'configFilePath'      = $null
        'absolutePath'        = $null
        'absoluteInstallPath' = $null
        'fullPathToExe'       = $null
        'command'             = '"%fullPathToExe%" -t'
        'windowBehaviour'     = 0
        'testModes'           = @(
            'SSE',
            'AVX',
            'AVX2',
            'AVX512',
            'CUSTOM'
        )
        'windowNames'        = @(
            '^Prime95 \- Torture Test$',    # New in 30.7
            '^Prime95 \- Self\-Test$',
            '^Prime95 \- Not running$',
            '^Prime95 \- Waiting for work$',
            '^Prime95$'
        )
    }

    'prime95_dev' = @{
        'displayName'         = 'Prime95 DEV'
        'processName'         = 'prime95_dev'
        'processNameExt'      = 'exe'
        'processNameForLoad'  = 'prime95_dev'
        'processPath'         = 'test_programs\p95_dev'
        'installPath'         = 'test_programs\p95_dev'
        'configName'          = $null
        'configFilePath'      = $null
        'absolutePath'        = $null
        'absoluteInstallPath' = $null
        'fullPathToExe'       = $null
        'command'             = '"%fullPathToExe%"" -t'
        'windowBehaviour'     = 0
        'testModes'           = @(
            'SSE',
            'AVX',
            'AVX2',
            'AVX512',
            'CUSTOM'
        )
        'windowNames'        = @(
            '^Prime95 \- Torture Test$',    # New in 30.7
            '^Prime95 \- Self\-Test$',
            '^Prime95 \- Not running$',
            '^Prime95 \- Waiting for work$',
            '^Prime95$'
        )
    }

    'aida64' = @{
        'displayName'         = 'Aida64'
        'processName'         = 'aida64'
        'processNameExt'      = 'exe'
        'processNameForLoad'  = 'aida_bench64.dll'   # This needs to be with file extension
        'processPath'         = 'test_programs\aida64'
        'installPath'         = 'test_programs\aida64'
        'configName'          = $null
        'configFilePath'      = $null
        'absolutePath'        = $null
        'absoluteInstallPath' = $null
        'fullPathToExe'       = $null
        'command'             = '"%fullPathToExe%" /SAFEST /SILENT /SST %mode%'
        'windowBehaviour'     = 6
        'testModes'           = @(
            'CACHE',
            'CPU',
            'FPU',
            'RAM'
        )
        'windowNames'        = @(
            '^System Stability Test \- AIDA64*'
        )
    }

    'ycruncher' = @{
        'displayName'         = 'y-Cruncher'
        'processName'         = '' # Depends on the selected modeYCruncher
        'processNameExt'      = 'exe'
        'processNameForLoad'  = '' # Depends on the selected modeYCruncher
        'processPath'         = 'test_programs\y-cruncher\Binaries'
        'installPath'         = 'test_programs\y-cruncher'
        'configName'          = 'stressTest.cfg'
        'configFilePath'      = $null
        'absolutePath'        = $null
        'absoluteInstallPath' = $null
        'fullPathToExe'       = $null
        'fullPathToLoadExe'   = $null
        'command'             = 'cmd /C start /MIN "y-Cruncher - %fileName%" "%fullPathToExe%" priority:2 config "%configFilePath%"'
        'commandWithLogging'  = 'cmd /C start /MIN "y-Cruncher - %fileName%" "%helpersPath%WriteConsoleToWriteFileWrapper.exe" "%fullPathToLoadExe%" priority:2 config "%configFilePath%" /dlllog:"%logFilePath%"'
        'windowBehaviour'     = 6
        'testModes'           = @(
            '00-x86',
            '04-P4P',
            '05-A64 ~ Kasumi',
            '08-NHM ~ Ushio',
            '11-SNB ~ Hina',
            '13-HSW ~ Airi',
            '14-BDW ~ Kurumi',
            '17-ZN1 ~ Yukina',
            '19-ZN2 ~ Kagari',
            '20-ZN3 ~ Yuzuki',

            # The following settings seem to be designed for Intel CPUs and don't run on Ryzen CPUs
            '11-BD1 ~ Miyu',
            '17-SKX ~ Kotori',
            '18-CNL ~ Shinoa',

            # This setting is designed for Ryzen 7000 (Zen 4) CPUs and uses AVX-512
            '22-ZN4 ~ Kizuna'
        )
        'availableTests'      = @('BKT', 'BBP', 'SFT', 'FFT', 'N32', 'N64', 'HNT', 'VST', 'C17')
        'defaultTests'        = @('BKT', 'BBP', 'SFT', 'FFT', 'N32', 'N64', 'HNT', 'VST')
        'windowNames'         = @(
            '' # Depends on the selected modeYCruncher
        )
    }
}


# Programs where both the main window and the stress test are the same process
$stressTestProgramsWithSameProcess = @(
    'prime95', 'prime95_dev', 'ycruncher'
)


# Used to get around the localized counter names
$englishCounterNames = @(
    'Process',
    'ID Process',
    '% Processor Time'

    # Possible future use
    #'Processor Information',
    #'% Processor Performance',
    #'% Processor Utility'
)

# This stores the Name:ID pairs of the english counter names
$counterNameIds = @{}

# This holds the localized counter names
# Stores the strings returned by Get-PerformanceCounterLocalName
$counterNames = @{
    'Process'                 = ''
    'ID Process'              = ''
    '% Processor Time'        = ''
    'FullName'                = ''
    'SearchString'            = ''
    'ReplaceString'           = ''

    # Possible future use
    #'Processor Information'   = ''
    #'% Processor Performance' = ''
    #'% Processor Utility'     = ''
}


# The number of physical and logical cores
# This also includes hyperthreading resp. SMT (Simultaneous Multi-Threading)
# We currently only test the first core for each hyperthreaded "package",
# so e.g. only 12 cores for a 24 threaded Ryzen 5900x
# If you disable hyperthreading / SMT, both values should be the same
$processor       = Get-CimInstance -ClassName Win32_Processor
$numLogicalCores = $($processor | Measure-Object -Property NumberOfLogicalProcessors -sum).Sum
$numPhysCores    = $($processor | Measure-Object -Property NumberOfCores -sum).Sum


# Set the flag if Hyperthreading / SMT is enabled or not
$isHyperthreadingEnabled = ($numLogicalCores -gt $numPhysCores)


# Override the HashTable .ToString() method to generate readable output
# https://www.sapien.com/blog/2014/10/21/a-better-tostring-method-for-hash-tables/
Update-TypeData -TypeName System.Collections.HashTable `
-MemberType ScriptMethod `
-MemberName ToString `
-Value { `
    $hashstr = "@{ "; `
    $keys = $this.keys; `
    foreach ($key in $keys) { `
        $v = $this[$key]; `
        if ($key -match "\s") { `
            $hashstr += "`"$key`"" + "=" + "`"$v`"" + "; "; `
        } `
        else { `
            $hashstr += $key + "=" + "`"$v`"" + "; "; `
        } `
    } `
    $hashstr += "}"; `
    return $hashstr; `
} `
-Force


# Prevent Sleep/Standby/Hibernation while the script is running
# https://stackoverflow.com/a/65162017/973927
$PowerUtilDefinition = @'
    // Member variables.
    static IntPtr _powerRequest;
    static bool _mustResetDisplayRequestToo;

    // P/Invoke function declarations.
    [DllImport("kernel32.dll")]
    static extern IntPtr PowerCreateRequest(ref POWER_REQUEST_CONTEXT Context);

    [DllImport("kernel32.dll")]
    static extern bool PowerSetRequest(IntPtr PowerRequestHandle, PowerRequestType RequestType);

    [DllImport("kernel32.dll")]
    static extern bool PowerClearRequest(IntPtr PowerRequestHandle, PowerRequestType RequestType);

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true, ExactSpelling = true)]
    static extern int CloseHandle(IntPtr hObject);

    // Availablity Request Enumerations and Constants
    enum PowerRequestType {
            PowerRequestDisplayRequired = 0,
            PowerRequestSystemRequired,
            PowerRequestAwayModeRequired,
            PowerRequestMaximum
    }

    const int POWER_REQUEST_CONTEXT_VERSION = 0;
    const int POWER_REQUEST_CONTEXT_SIMPLE_STRING = 0x1;

    // Availablity Request Structures
    // Note:  Windows defines the POWER_REQUEST_CONTEXT structure with an
    // internal union of SimpleReasonString and Detailed information.
    // To avoid runtime interop issues, this version of 
    // POWER_REQUEST_CONTEXT only supports SimpleReasonString.  
    // To use the detailed information,
    // define the PowerCreateRequest function with the first 
    // parameter of type POWER_REQUEST_CONTEXT_DETAILED.
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct POWER_REQUEST_CONTEXT {
            public UInt32 Version;
            public UInt32 Flags;
            [MarshalAs(UnmanagedType.LPWStr)]
            public string SimpleReasonString;
    }

    /// <summary>
    /// Prevents the system from going to sleep, by default not including the display.
    /// </summary>
    /// <param name="enable">
    ///   True to turn on, False to turn off. Passing True must be paired with a later call passing False.
    ///   If you pass True repeatedly, subsequent invocations take no actions and ignore the parameters.
    ///   If you pass False, the remaining paramters are ignored.
    //    If you pass False without having passed True earlier, no action is performed.
    //// </param>
    /// <param name="includeDisplay">True to also keep the display awake; defaults to False.</param>
    /// <param name="reasonString">
    ///   A string describing why the system is being kept awake; defaults to the current process' command line.
    ///   This will show in the output from `powercfg -requests` (requires elevation).
    /// </param>
    public static void StayAwake(bool enable, bool includeDisplay = false, string reasonString = null) {
        if (enable) {
            // Already enabled: quietly do nothing.
            if (_powerRequest != IntPtr.Zero) { return; }

            // Configure the reason string.
            POWER_REQUEST_CONTEXT powerRequestContext;
            powerRequestContext.Version = POWER_REQUEST_CONTEXT_VERSION;
            powerRequestContext.Flags = POWER_REQUEST_CONTEXT_SIMPLE_STRING;
            powerRequestContext.SimpleReasonString = reasonString ?? System.Environment.CommandLine; // The reason for making the power request

            // Create the request (returns a handle).
            _powerRequest = PowerCreateRequest(ref powerRequestContext);

            // Set the request(s).
            PowerSetRequest(_powerRequest, PowerRequestType.PowerRequestSystemRequired);
            
            if (includeDisplay) {
                PowerSetRequest(_powerRequest, PowerRequestType.PowerRequestDisplayRequired);
            }

            _mustResetDisplayRequestToo = includeDisplay;

        }
        else {

            // Not previously enabled: quietly do nothing.
            if (_powerRequest == IntPtr.Zero) {
                return;
            }

            // Clear the request
            PowerClearRequest(_powerRequest, PowerRequestType.PowerRequestSystemRequired);

            if (_mustResetDisplayRequestToo) {
                PowerClearRequest(_powerRequest, PowerRequestType.PowerRequestDisplayRequired);
            }

            CloseHandle(_powerRequest);
            _powerRequest = IntPtr.Zero;

        }
    }

    // Overload that allows passing a reason string while defaulting to keeping the display awake too.
    public static void StayAwake(bool enable, string reasonString) {
        StayAwake(enable, false, reasonString);
    }
'@


# Add code definitions so that we can close a window even if it's minimized to the tray
# The regular PowerShell way unfortunetely doesn't work in this case

# The definition to get the main window handle even if the process is minimized to the tray
$GetWindowsDefinition = @'
    using System;
    using System.Text;
    using System.Collections.Generic;
    using System.Runtime.InteropServices;
    
    namespace GetWindows {
        public class WinStruct {
            public string WinTitle {get; set; }
            public int MainWindowHandle { get; set; }
            public string ProcessPath { get; set; }
            public int ProcessId { get; set; }
        }
         
        public class Main {
            private static int PROCESS_QUERY_INFORMATION = (0x00000400);
            private static int PROCESS_VM_READ           = (0x00000010);

            private delegate bool CallBackPtr(int hwnd, int lParam);
            private static CallBackPtr callBackPtr = Callback;
            private static List<WinStruct> _WinStructList = new List<WinStruct>();

            // Get all windows
            [DllImport("user32.dll")]
            [return: MarshalAs(UnmanagedType.Bool)]
            private static extern bool EnumWindows(CallBackPtr lpEnumFunc, IntPtr lParam);

            // Get the window title
            [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
            static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
            
            // Get the process id for the window
            [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
            static extern int GetWindowThreadProcessId(IntPtr hWnd, out int ProcessId);

            // Open a process
            [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
            static extern int OpenProcess(int dwDesiredAccess, bool bInheritHandle, int dwProcessId);

            // Get the process path for a window
            [DllImport("psapi.dll", CharSet = CharSet.Auto, SetLastError = true)]
            static extern int GetModuleFileNameEx(IntPtr hProcess, IntPtr hModule, StringBuilder lpFilename, int nSize);
            

            private static bool Callback(int hWnd, int lparam) {
                int processId;
                StringBuilder sb1 = new StringBuilder(1024);
                StringBuilder sb2 = new StringBuilder(1024);

                int getIdResult         = GetWindowThreadProcessId((IntPtr)hWnd, out processId);
                int getWindowTextResult = GetWindowText((IntPtr)hWnd, sb1, 1024);
                int openProcessResult   = OpenProcess((PROCESS_QUERY_INFORMATION+PROCESS_VM_READ), true, processId);
                int getFileNameResult   = GetModuleFileNameEx((IntPtr)openProcessResult, IntPtr.Zero, sb2, 1024);

                _WinStructList.Add(new WinStruct { MainWindowHandle = hWnd, WinTitle = sb1.ToString(), ProcessPath = sb2.ToString(), ProcessId = processId });
                return true;
            }  

            public static List<WinStruct> GetWindows() {
                _WinStructList = new List<WinStruct>();
                EnumWindows(callBackPtr, IntPtr.Zero);
                return _WinStructList;
            }
        }
    }
'@

# The definition to send a message to a process
$SendMessageDefinition = @'
    using System;
    using System.Runtime.InteropServices;
    
    public static class SendMessageClass {
        // Values for Msg
        public static uint WM_SETFOCUS        = 0x0007;    // Set focus command
        public static uint WM_CLOSE           = 0x0010;    // Close command
        public static uint WM_SYSCOMMAND      = 0x0112;    // Initiate a system command (minimize, maximize, etc)
        public static uint WM_SYSCHAR         = 0x0106;    // Send a system character. This is a bit confusing
        public static uint WM_SYSKEYDOWN      = 0x0104;    // System key down
        public static uint WM_SYSKEYUP        = 0x0105;    // System key up
        public static uint KEY_DOWN           = 0x0100;    // Key down
        public static uint KEY_UP             = 0x0101;    // Key up
        public static uint VM_CHAR            = 0x0102;    // Send a keyboard character (see below)
        public static uint LBUTTONDOWN        = 0x0201;    // Left mouse button down
        public static uint LBUTTONUP          = 0x0202;    // Left mouse button up

        // This needs to be send to a button child "window" handle
        public static uint BM_CLICK           = 0x00F5;    // Mouse click on a button

        // Values for wParam
        public static uint KEY_A              = 0x0041;    // A
        public static uint KEY_D              = 0x0044;    // D
        public static uint KEY_E              = 0x0045;    // E
        public static uint KEY_S              = 0x0053;    // S
        public static uint KEY_T              = 0x0054;    // T
        public static uint KEY_MENU           = 0x0012;    // ALT Key

        // To be used in conjunction with WM_SYSCOMMAND
        public static uint SC_CLOSE           = 0xF060;    // Close command
        public static uint SC_MINIMIZE        = 0xF020;    // Minimize command
        public static uint SC_RESTORE         = 0xF120;    // Restore window command

        // Values for calculating lParam
        public static uint MAPVK_VK_TO_VSC    = 0x0000;
        public static uint MAPVK_VSC_TO_VK    = 0x0001;
        public static uint MAPVK_VK_TO_CHAR   = 0x0002;
        public static uint MAPVK_VSC_TO_VK_EX = 0x0003;
        public static uint MAPVK_VK_TO_VSC_EX = 0x0004;


        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = false)]
        public static extern uint MapVirtualKey(uint uCode, uint uMapType);

        public static uint GetLParam(Int16 repeatCount, uint key, byte extended, byte contextCode, byte previousState, byte transitionState) {
            var lParam = (uint) repeatCount;
            uint scanCode = MapVirtualKey(key, MAPVK_VK_TO_CHAR);

            lParam += scanCode*0x10000;
            lParam += (uint) ((extended)*0x1000000);
            lParam += (uint) ((contextCode*2)*0x10000000);
            lParam += (uint) ((previousState*4)*0x10000000);
            lParam += (uint) ((transitionState*8)*0x10000000);
            
            return lParam;
        }

        // SendMessage. Seems to return always 0
        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = false)]
        public static extern IntPtr SendMessage(IntPtr hWnd, UInt32 Msg, IntPtr wParam, IntPtr lParam);

        // PostMessage. Seems to return always 1
        [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = false)]
        public static extern IntPtr PostMessage(IntPtr hWnd, UInt32 Msg, IntPtr wParam, IntPtr lParam);
    }
'@


# Make the external code definitions available to PowerShell
Add-Type -ErrorAction Stop -Name PowerUtil -Namespace Windows -MemberDefinition $PowerUtilDefinition
Add-Type -TypeDefinition $GetWindowsDefinition
$SendMessage = Add-Type -TypeDefinition $SendMessageDefinition -PassThru


# Also make VisualBasic available
Add-Type -Assembly Microsoft.VisualBasic


<#
.DESCRIPTION
    Write a message to the screen and to the log file
.PARAMETER text
    [String] The text to output
.OUTPUTS
    void
#>
function Write-Text {
    param(
        [Parameter(Mandatory=$true)]
        $text
    )
    
    Write-Host $text
    Add-Content $logFileFullPath ($text)
}


<#
.DESCRIPTION
    Write an error message to the screen and to the log file
.PARAMETER errorArray
    [Array] An array with the text entries to output
.OUTPUTS
    [Void]
#>
function Write-ErrorText {
    param(
        [Parameter(Mandatory=$true)]
        $errorArray
    )

    foreach ($entry in $errorArray) {
        $lines  = @()
        $lines += $entry.Exception.Message
        $lines += $entry.InvocationInfo.PositionMessage
        $lines += ('    + CategoryInfo          : ' + $entry.CategoryInfo.Category + ': (' + $entry.CategoryInfo.TargetName + ':' + $entry.CategoryInfo.TargetType + ') [' + $entry.CategoryInfo.Activity + '], ' + $entry.CategoryInfo.Reason)
        $lines += ('    + FullyQualifiedErrorId : ' + $entry.FullyQualifiedErrorId)
        $string = $lines | Out-String

        Write-Host $string -ForegroundColor Red
        Add-Content $logFileFullPath ($string)
    }
}


<#
.DESCRIPTION
    Write a message to the screen with a specific color and to the log file
.PARAMETER text
    [String] The text to output
.PARAMETER foregroundColor
    [String] The foreground color
.PARAMETER backgroundColor
    [String] (optional) The background color
.OUTPUTS
    [Void]
#>
function Write-ColorText {
    param(
        [Parameter(Mandatory=$true)]
        $text,

        [Parameter(Mandatory=$true)]
        $foregroundColor,

        [Parameter(Mandatory=$false)]
        $backgroundColor
    )

    # -ForegroundColor <ConsoleColor>
    # -BackgroundColor <ConsoleColor>
    # Black, DarkBlue, DarkGreen, DarkCyan, DarkRed, DarkMagenta, DarkYellow, Gray, DarkGray, Blue, Green, Cyan, Red, Magenta, Yellow, White
    if ($backgroundColor) {
        Write-Host $text -ForegroundColor $foregroundColor -BackgroundColor $backgroundColor
    }
    else {
        Write-Host $text -ForegroundColor $foregroundColor
    }

    Add-Content $logFileFullPath ($text)
}


<#
.DESCRIPTION
    Write a verbose message to the screen and to the log file
    Verbose output
.PARAMETER text
    [String] The text to output
.OUTPUTS
    [Void]
#>
function Write-Verbose {
    param(
        [Parameter(Mandatory=$true)]
        $text
    )
    
    if ($settings.Logging.logLevel -ge 1) {
        if ($settings.Logging.logLevel -ge 3) {
            Write-Host(''.PadLeft(11, ' ') + '      + ' + $text) -ForegroundColor 'DarkGray'
        }

        Add-Content $logFileFullPath (''.PadLeft(11, ' ') + '      + ' + $text)
    }
}


<#
.DESCRIPTION
    Write a debug message to the screen and to the log file
    Debug output
.PARAMETER text
    [String] The text to output
.OUTPUTS
    [Void]
#>
function Write-Debug {
    param(
        [Parameter(Mandatory=$true)]
        $text
    )
    
    if ($settings.Logging.logLevel -ge 2) {
        if ($settings.Logging.logLevel -ge 4) {
            Write-Host(''.PadLeft(11, ' ') + '      + ' + $text) -ForegroundColor 'DarkGray'
        }

        Add-Content $logFileFullPath (''.PadLeft(11, ' ') + '      + ' + $text)
    }
}


<#
.DESCRIPTION
    Exit the script
.PARAMETER text
    [String] (optional) The text to display
.OUTPUTS
    [Void]
#>
function Exit-Script {
    param(
        [Parameter(Mandatory=$false)]
        $text
    )

    $Script:scriptExit = $true

    if ($text) {
        Write-Text($text)
    }

    exit
}


<#
.DESCRIPTION
    Throw a fatal error and exit the script
.PARAMETER text
    [String] (optional) The text to display
.OUTPUTS
    [Void]
#>
function Exit-WithFatalError {
    param(
        [Parameter(Mandatory=$false)]
        $text
    )

    $Script:fatalError = $true


    if ($text) {
        Write-ColorText('FATAL ERROR: ' + $text) Red
    }

    Write-Host
    Write-Host
    Write-Host 'You can find more information in the log file:' -ForegroundColor Yellow
    Write-Host $logFileFullPath -ForegroundColor Cyan
    Write-Host 'When reporting this error, please provide this log file.' -ForegroundColor Yellow

    Read-Host -Prompt 'Press Enter to exit'
    exit
}



<#
.DESCRIPTION
    Final summary when exiting the script
.PARAMETER
    [Void]
.OUTPUTS
    [String]
#>
function Show-FinalSummary {
    # Get the total runtime
    $endDate    = Get-Date
    $difference = New-TimeSpan -Start $startDate -End $endDate
    $runtimeArray = @()

    if ( $difference.Days -gt 0 ) {
        $runtimeArray += ($difference.Days.ToString() + ' days')
    }
    if ( $difference.Hours -gt 0 ) {
        $runtimeArray += ($difference.Hours.ToString().PadLeft(2, '0') + ' hours')
    }
    if ( $difference.Minutes -gt 0 ) {
        $runtimeArray += ($difference.Minutes.ToString().PadLeft(2, '0') + ' minutes')
    }
    if ( $difference.Seconds -gt 0 ) {
        $runtimeArray += ($difference.Seconds.ToString().PadLeft(2, '0') + ' seconds')
    }

    $runTimeString = $runtimeArray -Join ', '


    Write-ColorText('') Green
    Write-ColorText('---------------------') Green
    Write-ColorText('------ Summary ------') Green
    Write-ColorText('---------------------') Green
    Write-ColorText('The script ran for ' + $runTimeString) Cyan
    

    # Display the cores with error
    if ( $coresWithError.Length -gt 0 ) {
        $coresWithErrorString = (($coresWithError | Sort-Object) -Join ', ')
        Write-ColorText('The following cores have thrown an error: ') Cyan
        Write-ColorText(' - ' + $coresWithErrorString) Cyan
    }
    else {
        Write-ColorText('No core has thrown an error') Cyan
    }
}



<#
.DESCRIPTION
    Get the localized counter name
    Yes, they're localized. Way to go Microsoft!
.PARAMETER ID
    [UInt32] The id of the counter name. See the link above on how to get the IDs
.PARAMETER ComputerName
    [String] The name of the computer to query. Defaults to the current computer
.OUTPUTS
    [String] The localized name
.LINK
    https://www.powershellmagazine.com/2013/07/19/querying-performance-counters-from-powershell/
#>
function Get-PerformanceCounterLocalName {
    param (
        [UInt32]
        $ID,
        $ComputerName = $env:COMPUTERNAME
    )

    $code  = '[DllImport("pdh.dll", SetLastError=true, CharSet=CharSet.Unicode)] '
    $code += 'public static extern UInt32 PdhLookupPerfNameByIndex(string szMachineName, uint dwNameIndex, System.Text.StringBuilder szNameBuffer, ref uint pcchNameBufferSize);'
    
    $Buffer = New-Object System.Text.StringBuilder(1024)
    [UInt32] $BufferSize = $Buffer.Capacity

    $type = Add-Type -MemberDefinition $code -PassThru -Name PerfCounter -Namespace Utility
    $queryResult = $type::PdhLookupPerfNameByIndex($ComputerName, $ID, $Buffer, [Ref] $BufferSize)

    # 0 = ERROR_SUCCESS
    if ( $queryResult -eq 0 ) {
        $Buffer.ToString().Substring(0, $BufferSize-1)
    }
    else {
        Throw 'Get-PerformanceCounterLocalName : Unable to retrieve localized name. Check computer name and performance counter ID.'
    }
}


<#
.DESCRIPTION
    This is used to get the Performance Counter IDs, which will be used to get the localized names
.PARAMETER englishCounterNames
    [Array] An array with the english names of the counters
.OUTPUTS
    [HashTable] A hashtable with Name:ID pairs of the counters
#>
function Get-PerformanceCounterIDs {
    param (
        [Parameter(Mandatory=$true)]
        [Array] $englishCounterNames
    )

    $key          = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Perflib\009'
    $allCounters  = (Get-ItemProperty -Path $key -Name Counter).Counter
    $numCounters  = $allCounters.Count
    $countersHash = @{}
    
    # The string contains two-line pairs
    # The first line is the ID
    # The second line is the name
    # TODO: Maybe make it more robust by actually checking the order of the ID and Text
    for ($i = 0; $i -lt $numCounters; $i += 2) {
        $counterId   = [Int] $allCounters[$i]
        $counterName = [String] $allCounters[$i+1]

        if ($englishCounterNames -contains $counterName -and !$countersHash.ContainsKey($counterName)) {
            $countersHash[$counterName] = $counterId
        }
    }

    return $countersHash
}



############################################################################## 
##
## Invoke-WindowsApi.ps1
##
## http://www.leeholmes.com/blog/2007/10/02/managing-ini-files-with-powershell/
##
## From PowerShell Cookbook (O’Reilly)
## by Lee Holmes (http://www.leeholmes.com/guide)
## 
## Invoke a native Windows API call that takes and returns simple data types.
##
## ie:
##
## ## Prepare the parameter types and parameters for the
## CreateHardLink function
## $parameterTypes = [String], [String], [IntPtr]
## $parameters = [String] $filename, [String] $existingFilename, [IntPtr]::Zero
##
## ## Call the CreateHardLink method in the Kernel32 DLL
## $result = Invoke-WindowsApi "kernel32" ([Bool]) "CreateHardLink" `
##     $parameterTypes $parameters
##
############################################################################## 
# Unfortunately this introduces a memory leak when called multiple times in a row
############################################################################## 
function Invoke-WindowsApi {
    param(
        [String] $dllName_tmp, 
        [Type] $returnType_tmp, 
        [String] $methodName_tmp,
        [Type[]] $parameterTypes_tmp,
        [Object[]] $parameters_tmp
    )

    ## Begin to build the dynamic assembly
    $domain_tmp   = [AppDomain]::CurrentDomain
    $name_tmp     = New-Object Reflection.AssemblyName 'PInvokeAssembly'

    # TODO: This is potentially huge memory hog!
    # Only really noticable when using Aida64 though
    # Maybe this? https://stackoverflow.com/questions/2503645/reflect-emit-dynamic-type-memory-blowup
    $assembly_tmp = $domain_tmp.DefineDynamicAssembly($name_tmp, 'Run')
    
    $module_tmp   = $assembly_tmp.DefineDynamicModule('PInvokeModule')
    $type_tmp     = $module_tmp.DefineType('PInvokeType', 'Public,BeforeFieldInit')

    ## Go through all of the parameters passed to us.  As we do this,
    ## we clone the user's inputs into another array that we will use for
    ## the P/Invoke call.  
    $inputParameters_tmp = @()
    $refParameters_tmp = @()

    for ($counter_tmp = 1; $counter_tmp -le $parameterTypes_tmp.Length; $counter_tmp++) {
       ## If an item is a PSReference, then the user 
       ## wants an [Out] parameter.
       if ($parameterTypes_tmp[$counter_tmp - 1] -eq [Ref]) {
          ## Remember which parameters are used for [Out] parameters
          $refParameters_tmp += $counter_tmp

          ## On the cloned array, we replace the PSReference type with the 
          ## .Net reference type that represents the value of the PSReference, 
          ## and the value with the value held by the PSReference.
          $parameterTypes_tmp[$counter_tmp - 1] = $parameters_tmp[$counter_tmp - 1].Value.GetType().MakeByRefType()
          $inputParameters_tmp += $parameters_tmp[$counter_tmp - 1].Value
       }
       else {
          ## Otherwise, just add their actual parameter to the
          ## input array.
          $inputParameters_tmp += $parameters_tmp[$counter_tmp - 1]
       }
    }

    ## Define the actual P/Invoke method, adding the [Out]
    ## attribute for any parameters that were originally [Ref] 
    ## parameters.
    $method_tmp = $type_tmp.DefineMethod($methodName_tmp, 'Public,HideBySig,Static,PinvokeImpl', $returnType_tmp, $parameterTypes_tmp)
    
    foreach ($refParameter_tmp in $refParameters_tmp) {
       $null = $method_tmp.DefineParameter($refParameter_tmp, 'Out', $null)
    }

    ## Apply the P/Invoke constructor
    $ctor_tmp = [Runtime.InteropServices.DllImportAttribute].GetConstructor([String])
    $attr_tmp = New-Object Reflection.Emit.CustomAttributeBuilder $ctor_tmp, $dllName_tmp
    $method_tmp.SetCustomAttribute($attr_tmp)

    ## Create the temporary type, and invoke the method.
    $realType_tmp = $type_tmp.CreateType()
    $realType_tmp.InvokeMember($methodName_tmp, 'Public,Static,InvokeMethod', $null, $null, $inputParameters_tmp)

    ## Finally, go through all of the reference parameters, and update the
    ## values of the PSReference objects that the user passed in.
    foreach ($refParameter_tmp in $refParameters_tmp) {
       $parameters_tmp[$refParameter_tmp - 1].Value = $inputParameters_tmp[$refParameter_tmp - 1]
    }


    # Cleanup
    # But it doesn't help
    # So this might be an issue with .NET / C# itself?
    # For example this? https://stackoverflow.com/questions/2503645/reflect-emit-dynamic-type-memory-blowup
    # Eddga: found this https://www.jhouseconsulting.com/2017/09/25/addressing-the-powershell-garbage-collection-bug-1825 - maybe it helps
    
    Remove-Variable -Force -Name '*_tmp'
    
    $null = [System.GC]::GetTotalMemory('forcefullcollection')
}


<#
.DESCRIPTION
    Suspends a process
    Unfortunately this introduces a memory leak on multiple calls (resp. Invoke-WindowsApi does)
.PARAMETER process
    [System.Diagnostics.Process] The process to suspend
.OUTPUTS
    [Int] The number of suspended threads from this process. -1 if something failed
#>
function Suspend-Process {
    param(
        [Parameter(Mandatory=$true)]
        [System.Diagnostics.Process] $process
    )

    if (!$process) {
        return -2
    }

    Write-Verbose('Suspending process:')
    Write-Verbose($process.Id.ToString() + ' - ' + $process.ProcessName.ToString())

    $numThreads = 0
    $suspendCounts = 0
    $invokedThreadsArray = @()
    $processedThreadsArray = @()
    $previousSuspendCountArray = @()

    $process.Threads | ForEach-Object {
        # See https://docs.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-openthread
        $currentThreadId = Invoke-WindowsApi 'kernel32' ([IntPtr]) 'OpenThread' @([Int], [Bool], [Int]) @(0x0002, $false, $_.Id)
        
        if ($currentThreadId -eq [IntPtr]::Zero) {
            continue
        }

        $numThreads++

        $invokedThreadsArray += $currentThreadId

        #Write-Verbose('  - Suspending thread id: ' + $currentThreadId)

        # See https://docs.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-suspendthread
        # Do we also need Wow64SuspendThread?
        # https://docs.microsoft.com/en-us/windows/win32/api/wow64apiset/nf-wow64apiset-wow64suspendthread
        $previousSuspendCount = Invoke-WindowsApi 'kernel32' ([Int]) 'SuspendThread' @([IntPtr]) @($currentThreadId)

        #Write-Verbose('    Suspended thread ' + $currentThreadId + '. The previous suspend count is now: ' + $previousSuspendCount + ' (it should be 0)')
        
        $processedThreadsArray     += $currentThreadId
        $previousSuspendCountArray += $previousSuspendCount

        if ($previousSuspendCount -gt 0) {
            #Write-Verbose('    The previous suspend count is larger than 0, this means the process was already suspended... (curious but not necessarily an error)')
        }

        # $previousSuspendCount should be 0 if the thread is suspended now
        # If it > 0, then there is more than one suspended "state" on the thread. All of these need to be resumed to fully resume the thread/process
        # If it is -1, the operation has failed
        if ($previousSuspendCount -ge 0) {
            $suspendCounts++
        }
    }


    Write-Verbose('Threads that were invoked:')
    Write-Verbose('    ' + ($invokedThreadsArray -Join ', '))
    Write-Verbose('Threads that were processed:')
    Write-Verbose('    ' + ($processedThreadsArray -Join ', '))
    Write-Verbose('Previous suspend counts (should be 0):')
    Write-Verbose('    ' + ($previousSuspendCountArray -Join ', '))


    if ($suspendCounts -eq $numThreads) {
        return $suspendCounts
    }
    else {
        return -1
    }
}


<#
.DESCRIPTION
    Resumes a suspended process
    Unfortunately this introduces a memory leak on multiple calls (resp. Invoke-WindowsApi does)
.PARAMETER process
    [System.Diagnostics.Process] The process to resume
.OUTPUTS
    [Int] The number of resumed threads from this process. -1 if something failed
#>
function Resume-Process {
    param(
        [Parameter(Mandatory=$true)]
        [System.Diagnostics.Process] $process
    )

    if (!$process) {
        return -2
    }

    Write-Verbose('Resuming process:')
    Write-Verbose($process.Id.ToString() + ' - ' + $process.ProcessName.ToString())

    $numThreads = 0
    $resumeCounts = 0
    $invokedThreadsArray = @()
    $processedThreadsArray = @()
    $previousSuspendCountArray = @()

    $process.Threads | ForEach-Object {
        # See https://docs.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-openthread
        $currentThreadId = Invoke-WindowsApi 'kernel32' ([IntPtr]) 'OpenThread' @([Int], [Bool], [Int]) @(0x0002, $false, $_.Id)
        
        if ($currentThreadId -eq [IntPtr]::Zero) {
            continue
        }

        $numThreads++

        $invokedThreadsArray += $currentThreadId

        #Write-Verbose('  - Resuming thread id: ' + $currentThreadId)

        # $previousSuspendCount should be 1 if the thread is resumed now
        # If it > 1, then there is more than one suspended "state" on the thread. All of these need to be resumed to fully resume the thread/process
        # If it is -1, the operation has failed
        do {
            # See https://docs.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-resumethread
            $previousSuspendCount = Invoke-WindowsApi 'kernel32' ([Int]) 'ResumeThread' @([IntPtr]) @($currentThreadId)
            
            #Write-Verbose('    Resumed thread ' + $currentThreadId + '. The previous suspend count is now: ' + $previousSuspendCount + ' (it should be 1 or 0)')
            
            $processedThreadsArray     += $currentThreadId
            $previousSuspendCountArray += $previousSuspendCount

            if ($previousSuspendCount -gt 1) {
                #Write-Verbose('    The previous suspend count is larger than 1, this means the thread has multiple suspended states... (curious but not necessarily an error)')
            }
        } while ($previousSuspendCount -gt 1)

        if ($previousSuspendCount -eq 1) {
            $resumeCounts++
        }
    }


    Write-Verbose('Threads that were invoked:')
    Write-Verbose('    ' + ($invokedThreadsArray -Join ', '))
    Write-Verbose('Threads that were processed:')
    Write-Verbose('    ' + ($processedThreadsArray -Join ', '))
    Write-Verbose('Previous suspend counts (should be 1 or 0):')
    Write-Verbose('    ' + ($previousSuspendCountArray -Join ', '))


    if ($resumeCounts -eq $numThreads) {
        return $resumeCounts
    }
    else {
        return -1
    }
}


<#
.DESCRIPTION
    Suspends a process via the DebugActiveProcess method
.PARAMETER process
    [System.Diagnostics.Process] The process to suspend
.OUTPUTS
    [Bool]
#>
function Suspend-ProcessWithDebugMethod {
    param(
        [Parameter(Mandatory=$true)]
        [System.Diagnostics.Process] $process
    )

    if (!$process) {
        return $false
    }

    Invoke-WindowsApi 'kernel32' ([Bool]) 'DebugActiveProcess' @([Int]) @($process.Id)
}


<#
.DESCRIPTION
    Resumes a suspended process
.PARAMETER process
    [System.Diagnostics.Process] The process to resume
.OUTPUTS
    [Bool]
#>
function Resume-ProcessWithDebugMethod {
    param(
        [Parameter(Mandatory=$true)]
        [System.Diagnostics.Process] $process
    )

    if (!$process) {
        return $false
    }

    Invoke-WindowsApi 'kernel32' ([Bool]) 'DebugActiveProcessStop' @([Int]) @($process.Id)
}


<#
.DESCRIPTION
    Gets the current CPU frequency of a specific core / CPU
.PARAMETER cpuNumber
    [Int] The CPU to query
.OUTPUTS
    [HashTable] The current frequency and percent
.NOTES
    The calculated value does not 100% match the one from HWInfo64 or Ryzen Master, it's a bit lower
    I'm not sure why or if there's any way to fix this
    It's still higher than the one reported by Windows Task Manager though
#>
function Get-CpuFrequency {
    param(
        [Parameter(Mandatory=$true)]
        [Int]
        $cpuNumber
    )

    # We need two snapshots to be able to calculate an average over the time passed
    # We could also use a Start-Sleep function call to increase the timespan, without one it seems to be around 10ms
    $snapshot1 = Get-CimInstance -Query ('SELECT * from Win32_PerfRawData_Counters_ProcessorInformation WHERE Name LIKE "0,' + $cpuNumber + '"')
    $snapshot2 = Get-CimInstance -Query ('SELECT * from Win32_PerfRawData_Counters_ProcessorInformation WHERE Name LIKE "0,' + $cpuNumber + '"')

    $ProcessorFrequency                   = $snapshot1.ProcessorFrequency

    $PercentProcessorPerformance1         = $snapshot1.PercentProcessorPerformance
    $PercentProcessorPerformance_Base1    = $snapshot1.PercentProcessorPerformance_Base

    $PercentProcessorPerformance2         = $snapshot2.PercentProcessorPerformance
    $PercentProcessorPerformance_Base2    = $snapshot2.PercentProcessorPerformance_Base

    $PercentProcessorPerformanceDiff      = $PercentProcessorPerformance2 - $PercentProcessorPerformance1
    $PercentProcessorPerformance_BaseDiff = $PercentProcessorPerformance_Base2 - $PercentProcessorPerformance_Base1

    # Error check, if the base values are the same, let's do another query
    for ($i = 0; $i -lt 10; $i++) {
        if ($PercentProcessorPerformanceDiff -lt 1000 -or $PercentProcessorPerformance_BaseDiff -lt 1000) {
            Start-Sleep 50
            $snapshot2 = Get-CimInstance -Query ('SELECT * from Win32_PerfRawData_Counters_ProcessorInformation WHERE Name LIKE "0,' + $cpuNumber + '"')

            $PercentProcessorPerformance2         = $snapshot2.PercentProcessorPerformance
            $PercentProcessorPerformance_Base2    = $snapshot2.PercentProcessorPerformance_Base

            $PercentProcessorPerformanceDiff      = $PercentProcessorPerformance2 - $PercentProcessorPerformance1
            $PercentProcessorPerformance_BaseDiff = $PercentProcessorPerformance_Base2 - $PercentProcessorPerformance_Base1
        }
    }

    $PercentProcessorPerformance = $PercentProcessorPerformanceDiff / $PercentProcessorPerformance_BaseDiff
    $Frequency                   = $ProcessorFrequency * ($PercentProcessorPerformance / 100)

    $returnObj = @{
        'CurrentFrequency' = [Math]::Round($Frequency, 0)
        'Percent'          = [Math]::Round($PercentProcessorPerformance, 2)
    }

    return $returnObj
}


<#
.DESCRIPTION
    Import the settings from a .ini file
.PARAMETER filePath
    [String] The path to the file to parse
.OUTPUTS
    [HashTable] A hashtable holding the settings
#>
function Import-Settings {
    param(
        [Parameter(Mandatory=$true)]
        $filePath
    )

    # Certain setting values are strings
    $settingsWithStrings = @('stressTestProgram', 'stressTestProgramPriority', 'name', 'mode', 'FFTSize', 'coreTestOrder', 'tests', 'memory')

    # Lowercase for certain settings
    $settingsToLowercase = @('stressTestProgram', 'coreTestOrder', 'memory')

    # Check if the file exists
    if (!(Test-Path $filePath -PathType leaf)) {
        Exit-WithFatalError('Could not find ' + $filePath + '!')
    }

    
    $ini = @{}
    
    switch -regex -file $filePath {
        # Comments
        '^#' {
            continue
        }

        # Sections
        '^\[(.+)\]$' {
            $section = $Matches[1].ToString().Trim()
            $ini[$section] = @{}
        }

        # Settings
        '^(.+)\s?=\s?(.+)$' {
            $name, $value = $Matches[1..2]
            $name    = $name.ToString().Trim()
            $value   = $value.ToString().Trim()
            $setting = $null


            # Special handling for coresToIgnore, which can be empty
            if ($name -eq 'coresToIgnore') {
                $thisSetting = @()

                if ($null -ne $value -and ![String]::IsNullOrWhiteSpace($value)) {
                    # Split the string by comma and add to the coresToIgnore entry
                    $value -split ',\s*' | ForEach-Object {
                        if ($_.Length -gt 0) {
                            $thisSetting += [Int] $_
                        }
                    }

                    # We cannot use Sort here, as it would transform an array with only one entry into an integer!
                    $thisSetting::sort($thisSetting)
                }

                $setting = $thisSetting
            }


            # Special handling for y-Cruncher tests
            elseif ($section -eq 'yCruncher' -and $name -eq 'tests') {
                $thisSetting = @()

                # Empty value, use the default
                if ($null -eq $value -or [String]::IsNullOrWhiteSpace($value)) {
                    $value = $stressTestPrograms.ycruncher.defaultTests -Join ', '
                }

                # Split the string by comma
                $value -split ',\s*' | ForEach-Object {
                    if ($_.Length -gt 0) {
                        $thisSetting += $_.ToString().Trim().ToUpperInvariant()
                    }
                }

                # The possible y-Cruncher test values
                $possibleTests = $stressTestPrograms.ycruncher.availableTests
                $selectedTests = @()

                # Filter for only the possible test values
                $thisSetting | ForEach-Object {
                    if ($possibleTests.Contains($_.ToUpperInvariant())) {
                        $selectedTests += $_.ToUpperInvariant()
                    }
                }

                $setting = $selectedTests
            }


            # Regular settings cannot be empty
            elseif ($value -and ![String]::IsNullOrWhiteSpace($value)) {
                $thisSetting = $null
                
                # Parse the runtime per core (seconds, minutes, hours)
                if ($name -eq 'runtimePerCore') {
                    $valueLower = $value.ToLowerInvariant()

                    # It can be set to "auto"
                    if ($valueLower -eq 'auto') {
                        $thisSetting = 'auto'
                    }

                    # Parse the hours, minutes, seconds
                    elseif ($valueLower.indexOf('h') -ge 0 -or $valueLower.indexOf('m') -ge 0 -or $valueLower.indexOf('s') -ge 0) {
                        $null = $valueLower -match '(?-i)((?<hours>\d+(\.\d+)*)h)*\s*((?<minutes>\d+(\.\d+)*)m)*\s*((?<seconds>\d+(\.\d+)*)s)*'
                        $seconds = [Double] $Matches.hours * 60 * 60 + [Double] $Matches.minutes * 60 + [Double] $Matches.seconds
                        $thisSetting = [Int] $seconds
                    }

                    # Treat the value as seconds
                    else {
                        $thisSetting = [Int] $value
                    }
                }


                # String values
                elseif ($settingsWithStrings -contains $name) {
                    # Convert some to lower case
                    if ($settingsToLowercase -contains $name) {
                        $thisSetting = ([String] $value).ToLowerInvariant()
                    }
                    else {
                        $thisSetting = [String] $value
                    }
                }


                # Integer values
                elseif ($value -and ![String]::IsNullOrWhiteSpace($value)) {
                    $thisSetting = [Int] $value
                }

                $setting = $thisSetting
            }

            # No [section] found, error
            if (!$section -or [String]::IsNullOrWhiteSpace($section)) {
                Write-ColorText('FATAL ERROR: Invalid config file "' + $filePath + '" detected!') Red
                Write-ColorText('Maybe your config file is still from an older version.') Red
                Write-ColorText('Please delete your config.ini file and try again.') Red
                Exit-WithFatalError
            }

            $ini[$section][$name] = $setting
        }
    }

    return $ini
}


<#
.DESCRIPTION
    Get the settings
.PARAMETER
    [Void]
.OUTPUTS
    [Void]
#>
function Get-Settings {
    Write-Verbose('Parsing the user settings')

    # Get the absolute path of the config files
    $configDefaultPath = $root + '\config.default.ini'
    $configUserPath    = $root + '\config.ini'
    $logFilePrefix     = 'CoreCycler'

    # Set the temporary name and path for the logfile
    # We need it because of the Exit-WithFatalError calls below
    # We don't have all the information yet though, so the name and path will be overwritten after all the user settings have been parsed
    $Script:logFileName     = $logFilePrefix + '_' + $startDateTime + '.log'
    $Script:logFileFullPath = $logFilePathAbsolute + $logFileName


    # Get the default config settings
    $defaultSettings = Import-Settings $configDefaultPath

    $logFilePrefix = $(if (![String]::IsNullOrWhiteSpace($defaultSettings.Logging.name)) { $defaultSettings.Logging.name } else { $logFilePrefix })

    $Script:logFileName     = $logFilePrefix + '_' + $startDateTime + '.log'
    $Script:logFileFullPath = $logFilePathAbsolute + $logFileName


    # If no config file exists, copy the config.default.ini to config.ini
    if (!(Test-Path $configUserPath -PathType leaf)) {
        
        if (!(Test-Path $configDefaultPath -PathType leaf)) {
            Exit-WithFatalError('Neither config.ini nor config.default.ini found!')
        }

        Copy-Item -Path $configDefaultPath -Destination $configUserPath
    }


    # Read the config file and overwrite the default settings
    $userSettings = Import-Settings $configUserPath


    # Check if the config.ini contained valid setting
    # It may be corrupted if the computer immediately crashed due to unstable settings
    try {
        foreach ($entry in $userSettings.GetEnumerator()) {
        }
    }

    # Couldn't get the a valid content from the config.ini, replace it with the default
    catch {
        Write-ColorText('WARNING: config.ini corrupted, replacing with default values!') Yellow

        if (!(Test-Path $configDefaultPath -PathType leaf)) {
            Exit-WithFatalError('Neither config.ini nor config.default.ini found!')
        }

        Copy-Item -Path $configDefaultPath -Destination $configUserPath
        $userSettings = Import-Settings $configUserPath
    }


    # Merge the user settings with the default settings
    $settings = $defaultSettings
    
    foreach ($sectionEntry in $userSettings.GetEnumerator()) {
        foreach ($userSetting in $sectionEntry.Value.GetEnumerator()) {
            # No empty values (except empty arrays)
            if ( `
                    ($null -ne $userSetting.Value -and ![String]::IsNullOrWhiteSpace($userSetting.Value)) `
                -or ($userSetting.Value -is [Array] -or $userSetting.Value -is [Hashtable]) `
            ) {
                $settings[$sectionEntry.Name][$userSetting.Name] = $userSetting.Value
            }
            else {
                # Write-Verbose('Setting is empty!')
                # Write-Verbose('[' + $sectionEntry.Name + '][' + $userSetting.Name + ']: ' + $userSetting.Value)
            }
        }
    }


    # Limit the number of threads to 1 - 2
    $settings.General.numberOfThreads = [Math]::Max(1, [Math]::Min(2, $settings.General.numberOfThreads))
    $settings.General.numberOfThreads = $(if ($isHyperthreadingEnabled) { $settings.General.numberOfThreads } else { 1 })


    # If the selected stress test program is not supported
    if (!$settings.General.stressTestProgram -or !($stressTestPrograms.Contains($settings.General.stressTestProgram))) {
        Exit-WithFatalError('The selected stress test program "' + $settings.General.stressTestProgram + '" could not be found!')
    }


    # Set the correct flag 
    $Script:isPrime95              = $(if ($settings.General.stressTestProgram -eq 'prime95' -or $settings.General.stressTestProgram -eq 'prime95_dev') { $true } else { $false })
    $Script:isAida64               = $(if ($settings.General.stressTestProgram -eq 'aida64') { $true } else { $false })
    $Script:isYCruncher            = $(if ($settings.General.stressTestProgram -eq 'ycruncher') { $true } else { $false })
    $Script:isYCruncherWithLogging = $(if ($settings.General.stressTestProgram -eq 'ycruncher' -and $settings.yCruncher.enableYCruncherLoggingWrapper) { $true } else { $false })


    # Set the general "mode" setting
    if ($isPrime95) {
        $settings.mode = $settings.Prime95.mode.ToUpperInvariant()
    }
    elseif ($isAida64) {
        $settings.mode = $settings.Aida64.mode.ToUpperInvariant()
    }
    elseif ($isYCruncher) {
        $settings.mode = $settings.yCruncher.mode.ToUpperInvariant()
    }


    # The selected mode for y-Cruncher = the binary to execute
    # Override the variables
    $yCruncherBinary = $stressTestPrograms['ycruncher']['testModes'] | Where-Object -FilterScript {$_.ToLowerInvariant() -eq $settings.yCruncher.mode.ToLowerInvariant()}
    $Script:stressTestPrograms['ycruncher']['processName']        = $yCruncherBinary
    $Script:stressTestPrograms['ycruncher']['processNameForLoad'] = $yCruncherBinary
    $Script:stressTestPrograms['ycruncher']['fullPathToExe']      = $stressTestPrograms['ycruncher']['absolutePath'] + $yCruncherBinary
    $Script:stressTestPrograms['ycruncher']['fullPathToLoadExe']  = $stressTestPrograms['ycruncher']['absolutePath'] + $yCruncherBinary

    # Special handling if enableYCruncherLoggingWrapper is enabled
    if ($isYCruncherWithLogging) {
        $Script:stressTestPrograms['ycruncher']['processName']    = 'WriteConsoleToWriteFileWrapper'
        $Script:stressTestPrograms['ycruncher']['windowNames']    = @(
            '^.*WriteConsoleToWriteFileWrapper\.exe$'
            '^.*' + $yCruncherBinary + '\.exe$'
        )
    }
    else {
        $Script:stressTestPrograms['ycruncher']['windowNames']    = @('^.*' + $yCruncherBinary + '\.exe$')
    }


    # Sanity check the selected test mode
    # For Aida64, you can set a comma separated list of multiple stress tests
    $modesArray = $settings.mode -Split ',\s*'
    $modeString = ($modesArray -Join '-').ToUpperInvariant()

    foreach ($mode in $modesArray) {
        if (!($stressTestPrograms[$settings.General.stressTestProgram]['testModes'] -contains $mode)) {
            Exit-WithFatalError('The selected test mode "' + $mode + '" is not available for ' + $stressTestPrograms[$settings.General.stressTestProgram]['displayName'] + '!')
        }
    }


    # Store in the global variable
    $Script:settings = $settings


    # Set the final full path and name of the log file
    $logFilePrefix = $(if (![String]::IsNullOrWhiteSpace($settings.Logging.name)) { $settings.Logging.name } else { $logFilePrefix })
    
    $Script:logFileName     = $logFilePrefix + '_' + $startDateTime + '_' + $settings.General.stressTestProgram.ToUpperInvariant() + '_' + $modeString + '.log'
    $Script:logFileFullPath = $logFilePathAbsolute + $logFileName


    # Debug settings may override default settings
    $Script:disableCpuUtilizationCheck          = $(if (![String]::IsNullOrWhiteSpace($settings.Debug.disableCpuUtilizationCheck))           { $settings.Debug.disableCpuUtilizationCheck }           else { $disableCpuUtilizationCheckDefault })
    $Script:enableCpuFrequencyCheck             = $(if (![String]::IsNullOrWhiteSpace($settings.Debug.enableCpuFrequencyCheck))              { $settings.Debug.enableCpuFrequencyCheck }              else { $enableCpuFrequencyCheckDefault })
    $Script:tickInterval                        = $(if (![String]::IsNullOrWhiteSpace($settings.Debug.tickInterval))                         { $settings.Debug.tickInterval }                         else { $tickIntervalDefault })
    $Script:delayFirstErrorCheck                = $(if (![String]::IsNullOrWhiteSpace($settings.Debug.delayFirstErrorCheck))                 { $settings.Debug.delayFirstErrorCheck }                 else { $delayFirstErrorCheckDefault })
    $Script:stressTestProgramPriority           = $(if (![String]::IsNullOrWhiteSpace($settings.Debug.stressTestProgramPriority))            { $settings.Debug.stressTestProgramPriority }            else { $stressTestProgramPriorityDefault })
    $Script:stressTestProgramWindowToForeground = $(if (![String]::IsNullOrWhiteSpace($settings.Debug.stressTestProgramWindowToForeground))  { $settings.Debug.stressTestProgramWindowToForeground }  else { $stressTestProgramWindowToForegroundDefault })
    $Script:suspensionTime                      = $(if (![String]::IsNullOrWhiteSpace($settings.Debug.suspensionTime))                       { $settings.Debug.suspensionTime }                       else { $suspensionTimeDefault })
}


<#
.DESCRIPTION
    Get the formatted runtime per core string
.PARAMETER seconds
    Mixed. Either [Int] The runtime in seconds or [String] If set to "auto"
.OUTPUTS
    [String] The formatted runtime string
#>
function Get-FormattedRuntimePerCoreString {
    param (
        $seconds
    )

    if ($seconds.ToString().ToLowerInvariant() -eq 'auto') {
        if ($isAida64) {
            $returnString = [Math]::Round($Script:runtimePerCore/60, 2).ToString() + ' minutes (Auto-Mode)'
        }
        elseif ($isYCruncher -and !$isYCruncherWithLogging) {
            $returnString = $Script:runtimePerCore.ToString() + ' seconds (' + [Math]::Round($Script:runtimePerCore/60, 2).ToString() + ' minutes) (Auto-Mode)'
        }
        else {
            $returnString = 'AUTOMATIC'
        }

        return $returnString
    }


    $runtimePerCoreStringArray = @()
    $timeSpan = [TimeSpan]::FromSeconds($seconds)

    if ( $timeSpan.Hours -ge 1 ) {
        $thisString = [String] $timeSpan.Hours + ' hour'

        if ( $timeSpan.Hours -gt 1 ) {
            $thisString += 's'
        }

        $runtimePerCoreStringArray += $thisString
    }

    if ( $timeSpan.Minutes -ge 1 ) {
        $thisString = [String] $timeSpan.Minutes + ' minute'

        if ( $timeSpan.Minutes -gt 1 ) {
            $thisString += 's'
        }

        $runtimePerCoreStringArray += $thisString
    }


    if ( $timeSpan.Seconds -ge 1 ) {
        $thisString = [String] $timeSpan.Seconds + ' second'

        if ( $timeSpan.Seconds -gt 1 ) {
            $thisString += 's'
        }

        $runtimePerCoreStringArray += $thisString
    }

    return ($runtimePerCoreStringArray -Join ', ')
}



<#
.DESCRIPTION
    Get the estimated runtime per core for the y-Cruncher "auto" setting
.PARAMETER
    [Void]
.OUTPUTS
    [Int] The runtime in seconds
#>
function Get-EstimatedYCruncherRuntimePerCore {
    # Selected tests * duration of test + time in suspension + buffer
    $estimatedTime =   ($settings.yCruncher.tests.Count * $settings.yCruncher.testDuration) `
                        + (`
                            $settings.General.suspendPeriodically * `
                            ($settings.yCruncher.tests.Count * $settings.yCruncher.testDuration) / $settings.Debug.tickInterval * (1000 / $settings.Debug.suspensionTime)`
                        )`
                        + ($settings.yCruncher.tests.Count * $settings.yCruncher.testDuration * 0.05) # Some extra buffer (5% of runtime per test)
    $estimatedTime = [Math]::Ceiling($estimatedTime)

    return $estimatedTime
}


<#
.DESCRIPTION
    Get the correct TortureWeak setting for the selected CPU settings
.PARAMETER
    [Void]
.OUTPUTS
    [Int] The calculated TortureWeak value
#>
function Get-TortureWeakValue {
    <#
    Calculation of the TortureWeak ini setting
    ------------------------------------------
    From Prime95\source\gwnum\cpuid.h:
    #define CPU_SSE            0x0100     /*     256   SSE instructions supported */
    #define CPU_SSE2           0x0200     /*     512   SSE2 instructions supported */
    #define CPU_SSE3           0x0400     /*    1024   SSE3 instructions supported */
    #define CPU_SSSE3          0x0800     /*    2048   Supplemental SSE3 instructions supported */
    #define CPU_SSE41          0x1000     /*    4096   SSE4.1 instructions supported */
    #define CPU_SSE42          0x2000     /*    8192   SSE4.2 instructions supported */
    #define CPU_AVX            0x4000     /*   16384   AVX instructions supported */
    #define CPU_FMA3           0x8000     /*   32768   Intel fused multiply-add instructions supported */
    #define CPU_FMA4           0x10000    /*   65536   AMD fused multiply-add instructions supported */
    #define CPU_AVX2           0x20000    /*  131072   AVX2 instructions supported */
    #define CPU_PREFETCHW      0x40000    /*  262144   PREFETCHW (the Intel version) instruction supported */
    #define CPU_PREFETCHWT1    0x80000    /*  524288   PREFETCHWT1 instruction supported */
    #define CPU_AVX512F        0x100000   /* 1048576   AVX512F instructions supported */
    #define CPU_AVX512PF       0x200000   /* 2097152   AVX512PF instructions supported */

    From Prime95\source\prime95\Prime95Doc.cpp:
    m_weak = dlg.m_avx512 * CPU_AVX512F + dlg.m_fma3 * CPU_FMA3 + dlg.m_avx * CPU_AVX + dlg.m_sse2 * CPU_SSE2;
    
    - Only CPU_AVX512F, CPU_FMA3, CPU_AVX & CPU_SSE2 is used for the calculation
    - If one of these is set to disabled, add the number to the total value
    - AVX512 is never available on Ryzen <= 5000
    - AVX512 is available beginning with Ryzen 7000
    - TODO: Need a way to detect if AVX512 is available or not
            There doesn't seem to be a good way to check this from inside PowerShell
            Prime95 will just crash if it is started with AVX-512 support on a not supported CPU
            As does Y-Cruncher

    All enabled:
    0

    AVX512 disabled:
    1048576   --> CPU_AVX512F
    
    AVX2 disabled:
    1081344
    -1048576  --> CPU_AVX512F
    -32768    --> CPU_FMA3

    AVX disabled:
    1097728
    -1048576  --> CPU_AVX512F
    -32768    --> CPU_FMA3
    -16384    --> CPU_AVX
    #>

    # Convert '0' to true to 1 and 1 to false to 0
    $FMA3   = [Int]![Int]$prime95CPUSettings[$settings.mode].CpuSupportsFMA3
    $AVX    = [Int]![Int]$prime95CPUSettings[$settings.mode].CpuSupportsAVX
    $AVX512 = [Int]![Int]$prime95CPUSettings[$settings.mode].CpuSupportsAVX512

    # Add the various flag values if a feature is disabled
    $tortureWeakValue = ($AVX512 * 1048576) + ($FMA3 * 32768) + ($AVX * 16384)

    return $tortureWeakValue
}


<#
.DESCRIPTION
    Send a Start, Stop or Dismiss signal to Aida64
.PARAMETER command
    [String] The command to execute (Start, Stop, Dismiss, Clear)
.OUTPUTS
    [Void]
#>
function Send-CommandToAida64 {
    param(
        [Parameter(Mandatory=$true)]
        [String] $command
    )

    # No windowProcessMainWindowHandler? No good!
    if (!$windowProcessMainWindowHandler -or [String]::IsNullOrWhiteSpace($windowProcessMainWindowHandler)) {
        Write-Verbose('Could not get the windowProcessMainWindowHandler!')
        return
    }


    Write-Verbose('Trying to send the "' + $command + '" command to Aida64')

    if ($command.ToLowerInvariant() -eq 'start') {
        $KEY = $SendMessage::KEY_S
    }
    elseif ($command.ToLowerInvariant() -eq 'stop') {
        $KEY = $SendMessage::KEY_T
    }
    elseif ($command.ToLowerInvariant() -eq 'dismiss') {
        $KEY = $SendMessage::KEY_D
    }
    elseif ($command.ToLowerInvariant() -eq 'clear') {
        $KEY = $SendMessage::KEY_E
    }

    # This sends an ALT + KEY keystroke to the Aida64 main window
    $null = $SendMessage::PostMessage($windowProcessMainWindowHandler, $SendMessage::WM_SYSKEYDOWN, $SendMessage::KEY_MENU, $SendMessage::GetLParam(1, $SendMessage::KEY_MENU, 0, 1, 0, 0))
    $null = $SendMessage::PostMessage($windowProcessMainWindowHandler, $SendMessage::WM_SYSKEYDOWN, $KEY,                   $SendMessage::GetLParam(1, $KEY, 0, 1, 0, 0))
    #$null = $SendMessage::PostMessage($windowProcessMainWindowHandler, $SendMessage::WM_SYSCHAR,    $KEY,                   $SendMessage::GetLParam(1, $KEY, 0, 1, 0, 0))
    $null = $SendMessage::PostMessage($windowProcessMainWindowHandler, $SendMessage::KEY_UP,        $SendMessage::KEY_MENU, $SendMessage::GetLParam(1, $SendMessage::KEY_MENU, 0, 0, 1, 1))
    $null = $SendMessage::PostMessage($windowProcessMainWindowHandler, $SendMessage::KEY_UP,        $KEY,                   $SendMessage::GetLParam(1, $KEY, 0, 0, 1, 1))


    # DEBUG
    # Just to be able to see the entries in Spy++ more easily
    #$null = $SendMessage::PostMessage($windowProcessMainWindowHandler, $SendMessage::KEY_UP, 0, $SendMessage::GetLParam(0, 0, 0, 0, 0, 0))
    #$null = $SendMessage::PostMessage($windowProcessMainWindowHandler, $SendMessage::KEY_UP, 0, $SendMessage::GetLParam(0, 0, 0, 0, 0, 0))
    #$null = $SendMessage::PostMessage($windowProcessMainWindowHandler, $SendMessage::KEY_UP, 0, $SendMessage::GetLParam(0, 0, 0, 0, 0, 0))
    #$null = $SendMessage::PostMessage($windowProcessMainWindowHandler, $SendMessage::KEY_UP, 0, $SendMessage::GetLParam(0, 0, 0, 0, 0, 0))
    #$null = $SendMessage::PostMessage($windowProcessMainWindowHandler, $SendMessage::KEY_UP, 0, $SendMessage::GetLParam(0, 0, 0, 0, 0, 0))
}


<#
.DESCRIPTION
    Get the main window and stress test processes, as well as the main window handler
    Even if minimized to the tray
    This will set global variables
.PARAMETER stopOnStressTestProcessNotFound
    [Bool] If set to false, will not throw an error if the stress test process was not found
.OUTPUTS
    [Void]
#>
function Get-StressTestProcessInformation {
    param(
        [Parameter(Mandatory=$false)]
        [Bool] $stopOnStressTestProcessNotFound = $true
    )

    $windowObj                      = $null
    $filteredWindowObj              = $null
    $ckeckProcess                   = $null
    $stressTestProcess              = $null    # Assigned to global variable
    $stressTestProcessId            = $null    # Assigned to global variable
    $windowProcess                  = $null    # Assigned to global variable
    $windowProcessId                = $null    # Assigned to global variable
    $windowProcessMainWindowHandler = $null    # Assigned to global variable
    
    Write-Verbose('Trying to get the stress test program window handler')
    Write-Verbose('Looking for these window names:')
    Write-Verbose(($stressTestPrograms[$settings.General.stressTestProgram]['windowNames'] -Join ', '))

    # Try to to get the window and the stress test
    for ($i = 1; $i -le 30; $i++) {
        Start-Sleep -Milliseconds 250
        $timestamp = Get-Date -format HH:mm:ss

        # This is the window object for the main window
        $windowObj = [GetWindows.Main]::GetWindows() | Where-Object {
            $_.WinTitle -match ($stressTestPrograms[$settings.General.stressTestProgram]['windowNames'] -Join '|')
        }

        # This is the process object for the stress test. They may be the same, but not necessarily (e.g. Aida64)
        $stressTestProcess = Get-Process $stressTestPrograms[$settings.General.stressTestProgram]['processNameForLoad'] -ErrorAction Ignore

        if ($windowObj.Length -gt 0) {
            Write-Verbose($timestamp + ' - Window found')
            break
        }
        else {
            Write-Verbose($timestamp + ' - ... no window found for these names...')
        }
    }


    # Still no main window found
    if ($windowObj.Length -eq 0) {
        # Check if the process for the main window exists
        $ckeckProcess = Get-Process $stressTestPrograms[$settings.General.stressTestProgram]['processName'] -ErrorAction Ignore

        # We found the main window process, one last check to get the main window object
        if ($ckeckProcess.Length -gt 0) {
            $windowObj = [GetWindows.Main]::GetWindows() | Where-Object {
                $_.WinTitle -match ($stressTestPrograms[$settings.General.stressTestProgram]['windowNames'] -Join '|')
            }
        }
    }


    # Yeah, we can't find anything, throw that error
    if ($windowObj.Length -eq 0) {
        Write-ColorText('FATAL ERROR: Could not find a window instance for the stress test program!') Red
        Write-ColorText('Was looking for these window names:') Red
        Write-ColorText(($stressTestPrograms[$settings.General.stressTestProgram]['windowNames'] -Join ', ')) Yellow

        if ($ckeckProcess) {
            Write-ColorText('However, found a process with the process name "' + $stressTestPrograms[$settings.General.stressTestProgram]['processName'] + '":') Red

            $ckeckProcess | ForEach-Object {
                Write-ColorText(' - ProcessName:  ' + $_.ProcessName) Yellow
                Write-ColorText('   Process Path: ' + $_.Path) Yellow
                Write-ColorText('   Process Id:   ' + $_.Id) Yellow
            }
        }

        # I could dump all of the window names here, but I'd rather not due to privacy reasons
        Exit-WithFatalError
    }


    Write-Verbose('Found the following window(s) with these names:')

    $windowObj | ForEach-Object {
        $path = (Get-Process -Id $_.ProcessId -ErrorAction Ignore).Path
        Write-Verbose(' - WinTitle:         ' + $_.WinTitle)
        Write-Verbose('   MainWindowHandle: ' + $_.MainWindowHandle)
        Write-Verbose('   ProcessId:        ' + $_.ProcessId)
        Write-Verbose('   Process Path:     ' + $_.ProcessPath)
        Write-Verbose('   Process Path (PS):' + $path)
    }

    # There might be another window open with the same name as the stress test program (e.g. an Explorer window)
    # Select the correct one
    $searchForProcess = ('.*' + $stressTestPrograms[$settings.General.stressTestProgram]['processName'] + '\.' + $stressTestPrograms[$settings.General.stressTestProgram]['processNameExt'] + '$')
    
    Write-Verbose('Filtering the windows for "' + $searchForProcess + '":')

    # If we're running the wrapper for y-Cruncher to capture the output, we need to check the commandline
    if ($isYCruncherWithLogging) {
        Write-Verbose('enableYCruncherLoggingWrapper has been set, special handling')
        $searchForProcess = '*"' + $stressTestPrograms['ycruncher']['fullPathToLoadExe'] + '.' + $stressTestPrograms['ycruncher']['processNameExt'] + '"*'
        $filteredWindowObj = $windowObj | Where-Object {
            $commandLine = (Get-CimInstance Win32_Process -Filter "ProcessId = $($_.ProcessId)" | Select-Object CommandLine).CommandLine
            $hasMatch = $commandLine -like $searchForProcess

            Write-Verbose(' - ProcessId:        ' + $_.ProcessId)
            Write-Verbose('   searchForProcess: ' + $searchForProcess)
            Write-Verbose('   CommandLine:      ' + $commandLine)
            Write-Verbose('   hasMatch:         ' + $hasMatch)
            
            $hasMatch
        }
    }

    # Regular y-Cruncher or other stress test programs
    else {
        $filteredWindowObj = $windowObj | Where-Object {
            #(Get-Process -Id $_.ProcessId -ErrorAction Ignore).Path -match $searchForProcess
            $_.ProcessPath -match $searchForProcess
        }
    }

    $filteredWindowObj | ForEach-Object {
        $path = (Get-Process -Id $_.ProcessId -ErrorAction Ignore).Path
        Write-Verbose(' - WinTitle:         ' + $_.WinTitle)
        Write-Verbose('   MainWindowHandle: ' + $_.MainWindowHandle)
        Write-Verbose('   ProcessId:        ' + $_.ProcessId)
        Write-Verbose('   Process Path:     ' + $_.ProcessPath)
        Write-Verbose('   Process Path (PS):' + $path)
    }


    # No window found!
    if (!$filteredWindowObj) {
        Write-ColorText('FATAL ERROR: Could not find the correct stress test window!') Red
        Write-ColorText('No window found that matches "' + $searchForProcess + '"') Red
        Exit-WithFatalError
    }


    # Multiple processes found with the same name AND process name
    # Abort and let the user close these programs
    if ($filteredWindowObj -is [Array]) {
        Write-ColorText('FATAL ERROR: Could not find the correct stress test window!') Red
        Write-ColorText('There exist multiple windows with the same name as the stress test program:') Red
        
        $filteredWindowObj | ForEach-Object {
            #$path = (Get-Process -Id $_.ProcessId -ErrorAction Ignore).Path
            Write-ColorText(' - Windows Title: ' + $_.WinTitle) Yellow
            #Write-ColorText('   Process Path:  ' + $path) Yellow
            Write-ColorText('   Process Path:  ' + $_.ProcessPath) Yellow
            Write-ColorText('   Process Id:    ' + $_.ProcessId) Yellow
        }

        Write-ColorText('Please close these windows and try again.') Red
        Exit-WithFatalError
    }


    # We've now found our main window object, get the corresponding PowerShell process object for it
    $windowProcess = Get-Process -Id $filteredWindowObj.ProcessId -ErrorAction Ignore


    # Also, the process performing the stress test can actually be different to the main window of the stress test program
    # If so, search for it as well
    if ($stressTestPrograms[$settings.General.stressTestProgram]['processName'] -ne $stressTestPrograms[$settings.General.stressTestProgram]['processNameForLoad']) {
        Write-Verbose('The process performing the stress test is NOT the same as the main window!')
        Write-Verbose('Searching for the stress test process id...')
        
        try {
            Write-Verbose('Searching for "' + $stressTestPrograms[$settings.General.stressTestProgram]['processNameForLoad'] + '"...')
            $stressTestProcess   = Get-Process $stressTestPrograms[$settings.General.stressTestProgram]['processNameForLoad'] -ErrorAction Stop
            $stressTestProcessId = $stressTestProcess.Id

            Write-Verbose('Found with ID: ' + $stressTestProcessId)
        }
        catch {
            $message = 'Could not determine the stress test program process ID! (looking for ' + $stressTestPrograms[$settings.General.stressTestProgram]['processNameForLoad'] + ')'

            # Only throw an error if the flag to do so was set
            # It may be possible that e.g. the main window of Aida64 was started, but no stress test is currently running
            if ($stopOnStressTestProcessNotFound) {
                Exit-WithFatalError($message)
            }
            else {
                Write-Verbose($message)
            }
        }
    }

    # The stress test and the main window are the same process
    else {
        $stressTestProcess   = $windowProcess
        $stressTestProcessId = $windowProcess.Id
    }


    # Override the global script variables
    $Script:windowProcess                  = $windowProcess
    $Script:windowProcessId                = $filteredWindowObj.ProcessId
    $Script:windowProcessMainWindowHandler = $filteredWindowObj.MainWindowHandle
    $Script:stressTestProcess              = $stressTestProcess
    $Script:stressTestProcessId            = $stressTestProcessId

    Write-Verbose('Main window handler:      ' + $Script:windowProcessMainWindowHandler)
    Write-Verbose('Main window process name: ' + $Script:windowProcess.ProcessName)
    Write-Verbose('Main window process ID:   ' + $Script:windowProcessId)
    Write-Verbose('Stress test process name: ' + $Script:stressTestProcess.ProcessName)
    Write-Verbose('Stress test process ID:   ' + $Script:stressTestProcessId)
}


<#
.DESCRIPTION
    Check if Prime95 exists
.PARAMETER 
    [Void]
.OUTPUTS
    [Void]
#>
function Test-Prime95 {
    # This may be prime95 or prime95_dev
    $p95Type = $settings.General.stressTestProgram

    # Check if the prime95.exe exists
    Write-Verbose('Checking if prime95.exe exists at:')
    Write-Verbose($stressTestPrograms[$p95Type]['fullPathToExe'] + '.' + $stressTestPrograms[$p95Type]['processNameExt'])

    if (!(Test-Path ($stressTestPrograms[$p95Type]['fullPathToExe'] + '.' + $stressTestPrograms[$p95Type]['processNameExt']) -PathType leaf)) {
        Write-ColorText('FATAL ERROR: Could not find Prime95!') Red
        Write-ColorText('Make sure to download and extract Prime95 into the following directory:') Red
        Write-ColorText($stressTestPrograms[$p95Type]['absoluteInstallPath']) Yellow
        Write-Text ''
        Write-ColorText('You can download Prime95 from:') Red
        Write-ColorText('https://www.mersenne.org/download/') Cyan
        Exit-WithFatalError
    }
}


<#
.DESCRIPTION
    Create the Prime95 config files (local.txt & prime.txt)
    This depends on the $settings.mode variable
    And also on the Prime95 version
.PARAMETER
    [Void]
.OUTPUTS
    [Void]
#>
function Initialize-Prime95 {
    # This may be prime95 or prime95_dev
    $p95Type = $settings.General.stressTestProgram

    # Set various global variables we need for Prime95
    $Script:prime95CPUSettings = @{
        SSE = @{
            CpuSupportsSSE    = 1
            CpuSupportsSSE2   = 1
            CpuSupportsAVX    = 0
            CpuSupportsAVX2   = 0
            CpuSupportsFMA3   = 0
            CpuSupportsAVX512 = 0
        }

        AVX = @{
            CpuSupportsSSE    = 1
            CpuSupportsSSE2   = 1
            CpuSupportsAVX    = 1
            CpuSupportsAVX2   = 0
            CpuSupportsFMA3   = 0
            CpuSupportsAVX512 = 0
        }

        AVX2 = @{
            CpuSupportsSSE    = 1
            CpuSupportsSSE2   = 1
            CpuSupportsAVX    = 1
            CpuSupportsAVX2   = 1
            CpuSupportsFMA3   = 1
            CpuSupportsAVX512 = 0
        }

        AVX512 = @{
            CpuSupportsSSE    = 1
            CpuSupportsSSE2   = 1
            CpuSupportsAVX    = 1
            CpuSupportsAVX2   = 1
            CpuSupportsFMA3   = 1
            CpuSupportsAVX512 = 1
        }

        CUSTOM = @{
            CpuSupportsSSE    = 1
            CpuSupportsSSE2   = 1
            CpuSupportsAVX    = $settings.Custom.CpuSupportsAVX
            CpuSupportsAVX2   = $settings.Custom.CpuSupportsAVX2
            CpuSupportsFMA3   = $settings.Custom.CpuSupportsFMA3
            CpuSupportsAVX512 = $settings.Custom.CpuSupportsAVX512
        }
    }


    # The various FFT sizes for Prime95
    # Used to determine where an error likely happened
    # Note: These are different depending on the selected mode (SSE, AVX, AVX2)!
    # Note: These are Int/Int32 numbers, you will not find a number cast to Int64 in this array (with e.g. [Array]::indexOf)!
    # SSE:    4, 5, 6, 8, 10, 12, 14, 16,     20,     24,     28,     32,         40, 48, 56,     64, 72, 80, 84, 96,      112,      128,      144, 160,      192,      224, 240, 256,      288, 320, 336, 384, 400, 448, 480, 512, 560, 576, 640, 672, 720, 768, 800,      896, 960, 1024, 1120, 1152, 1200, 1280, 1344, 1440, 1536, 1600, 1680, 1728, 1792, 1920, 2048, 2240, 2304, 2400, 2560, 2688, 2800, 2880, 3072, 3200, 3360, 3456, 3584, 3840,       4096, 4480, 4608, 4800, 5120, 5376, 5600, 5760, 6144, 6400, 6720, 6912, 7168, 7680, 8000,       8192, 8960, 9216, 9600, 10240, 10752, 11200, 11520, 12288, 12800, 13440, 13824, 14336, 15360, 16000,        16384, 17920, 18432, 19200, 20480, 21504, 22400, 23040, 24576, 25600, 26880, 27648, 28672, 30720, 32000, 32768
    # AVX:    4, 5, 6, 8, 10, 12, 15, 16, 18, 20, 21, 24, 25, 28,     32, 35, 36, 40, 48, 50, 60, 64, 72, 80, 84, 96, 100, 112, 120, 128, 140, 144, 160, 168, 192, 200, 224, 240, 256,      288, 320, 336, 384, 400, 448, 480, 512, 560, 576, 640, 672, 720, 768, 800, 864, 896, 960, 1024,       1152,       1280, 1344, 1440, 1536, 1600, 1680, 1728, 1792, 1920, 2048,       2304, 2400, 2560, 2688,       2880, 3072, 3200, 3360, 3456, 3584, 3840, 4032, 4096, 4480, 4608, 4800, 5120, 5376,       5760, 6144, 6400, 6720, 6912, 7168, 7680, 8000,       8192, 8960, 9216, 9600, 10240, 10752,        11520, 12288, 12800, 13440, 13824, 14336, 15360, 16000, 16128, 16384, 17920, 18432, 19200, 20480, 21504, 22400, 23040, 24576, 25600, 26880,        28672, 30720, 32000, 32768
    # AVX2:   4, 5, 6, 8, 10, 12, 15, 16, 18, 20, 21, 24, 25, 28, 30, 32, 35, 36, 40, 48, 50, 60, 64, 72, 80, 84, 96, 100, 112, 120, 128,      144, 160, 168, 192, 200, 224, 240, 256, 280, 288, 320, 336, 384, 400, 448, 480, 512, 560,      640, 672,      768, 800,      896, 960, 1024, 1120, 1152,       1280, 1344, 1440, 1536, 1600, 1680,       1792, 1920, 2048, 2240, 2304, 2400, 2560, 2688, 2800, 2880, 3072, 3200, 3360,       3584, 3840,       4096, 4480, 4608, 4800, 5120, 5376, 5600, 5760, 6144, 6400, 6720,       7168, 7680, 8000, 8064, 8192, 8960, 9216, 9600, 10240, 10752, 11200, 11520, 12288, 12800, 13440, 13824, 14336, 15360, 16000, 16128, 16384, 17920, 18432, 19200, 20480, 21504, 22400, 23040, 24576, 25600, 26880,        28672, 30720, 32000, 32768, 35840, 38400, 40960, 44800, 51200
    # AVX512: 4608, 5K, 6K, 7K, 7680, 8K, 9K, 10K, 10752, 12K, 12800, 16K, 18K, 20K, 24K, 25K, 32K, 40K, 48K, 56K, 60K, 64K, 72K, 80K, 84K, 96K, 120K, 128K, 144K, 192K, 200K, 240K, 280K, 288K, 300K, 320K, 336K, 360K, 384K, 392K, 400K, 420K, 432K, 448K, 480K, 504K, 512K, 560K, 576K, 588K, 600K, 640K, 672K, 720K, 768K, 800K, 840K, 864K, 896K, 960K, 1000K, 1008K, 1024K, 1152K, 1200K, 1280K, 1344K, 1400K, 1440K, 1500K, 1536K, 1600K, 1680K, 1728K, 1800K, 1920K, 1960K, 2048K, 2100K, 2160K, 2240K, 2304K, 2400K, 2520K, 2560K, 2592K, 2688K, 2880K, 2940K, 3000K, 3072K, 3136K, 3200K, 3360K, 3456K, 3600K, 3840K, 3920K, 4032K, 4200K, 4320K, 4480K, 4608K, 4704K, 4800K, 5040K, 5120K, 5184K, 5376K, 5760K, 6048K, 6144K, 6272K, 6400K, 6720K, 7056K, 7168K, 7200K, 7680K, 8064K, 8400K, 8640K, 8960K, 9600K, 10240K, 10368K, 11200K, 11520K, 12288K, 12800K, 13440K, 14400K, 15360K, 15680K, 16128K, 16384K, 16800K, 17280K, 17920K, 18432K, 18816K, 19200K, 20160K, 20480K, 20736K, 21504K, 21952K, 22400K, 23520K, 24192K, 24576K, 25088K, 25600K, 26880K, 27648K, 28224K, 28800K, 30720K, 31360K, 32256K, 32928K, 34560K, 36864K, 37632K, 38400K, 40320K, 40960K, 41472K, 43008K, 46080K, 47040K, 48384K, 49152K, 50176K, 53760K, 55296K, 56448K, 57344K, 61440K, 65536K

    # Note: We're using "expanded" values here, e.g. instead of the "K" values, we multiply the FFT size by 1024 to get the full value
    # Prime95 normally lists "K" values in its log files, however if the FFT size is not divisible by 1024, it will instead print the full value as well without an appended "K"
    # Examples: 4608, 7680, 10752, 12800
    # This only happens when AVX-512 is selected, but we need to have a uniform way to detect the FFT sizes, so all of the modes are set up this way
    #
    # Also note that the Smalles, Small, Large Presets seem to have changed in Prime 30.8, but for the time being we're keeping the old values
    # This is maybe a TODO
    $Script:FFTSizes = @{
        SSE = @(
            # Smallest FFT
            4096, 5120, 6144, 8192, 10240, 12288, 14336, 16384, 20480,

            # Not used in Prime95 presets
            24576, 28672, 32768,

            # Small FFT
            40960, 49152, 57344, 65536, 73728, 81920, 86016, 98304, 114688, 131072, 147456, 163840, 196608, 229376, 245760,

            # Not used in Prime95 presets
            262144, 294912, 327680, 344064, 393216, 409600,

            # Large FFT
            458752, 491520, 524288, 573440, 589824, 655360, 688128, 737280, 786432, 819200, 917504, 983040, 1048576, 1146880, 1179648, 1228800, 1310720,
            1376256, 1474560, 1572864, 1638400, 1720320, 1769472, 1835008, 1966080, 2097152, 2293760, 2359296, 2457600, 2621440, 2752512, 2867200, 2949120,
            3145728, 3276800, 3440640, 3538944, 3670016, 3932160, 4194304, 4587520, 4718592, 4915200, 5242880, 5505024, 5734400, 5898240, 6291456, 6553600,
            6881280, 7077888, 7340032, 7864320, 8192000, 8388608,

            # Not used in Prime95 presets
            # Now custom labeled "Huge"
            # 32768K = 33554432 seems to be the maximum FFT size possible for SSE
            9175040, 9437184, 9830400, 10485760, 11010048, 11468800, 11796480, 12582912, 13107200, 13762560, 14155776, 14680064, 15728640, 16384000, 16777216,
            18350080, 18874368, 19660800, 20971520, 22020096, 22937600, 23592960, 25165824, 26214400, 27525120, 28311552, 29360128, 31457280, 32768000, 33554432
        )

        AVX = @(
            # Smallest FFT
            4096, 5120, 6144, 8192, 10240, 12288, 15360, 16384, 18432, 20480, 21504,

            # Not used in Prime95 presets
            24576, 25600, 28672, 32768, 35840,

            # Small FFT
            36864, 40960, 49152, 51200, 61440, 65536, 73728, 81920, 86016, 98304, 102400, 114688, 122880, 131072, 143360, 147456, 163840, 172032, 196608, 204800, 229376, 245760,

            # Not used in Prime95 presets
            262144, 294912, 327680, 344064, 393216, 409600,

            # Large FFT
            458752, 491520, 524288, 573440, 589824, 655360, 688128, 737280, 786432, 819200, 884736, 917504, 983040, 1048576, 1179648, 1310720, 1376256, 1474560, 1572864, 1638400,
            1720320, 1769472, 1835008, 1966080, 2097152, 2359296, 2457600, 2621440, 2752512, 2949120, 3145728, 3276800, 3440640, 3538944, 3670016, 3932160, 4128768, 4194304,
            4587520, 4718592, 4915200, 5242880, 5505024, 5898240, 6291456, 6553600, 6881280, 7077888, 7340032, 7864320, 8192000, 8388608,

            # Not used in Prime95 presets
            # Now custom labeled "Huge"
            # 32768K = 33554432 seems to be the maximum FFT size possible for SSE
            9175040, 9437184, 9830400, 10485760, 11010048, 11796480, 12582912, 13107200, 13762560, 14155776, 14680064, 15728640, 16384000, 16515072, 16777216, 18350080,
            18874368, 19660800, 20971520, 22020096, 22937600, 23592960, 25165824, 26214400, 27525120, 29360128, 31457280, 32768000, 33554432
        )

        AVX2 = @(
            # Smallest FFT
            4096, 5120, 6144, 8192, 10240, 12288, 15360, 16384, 18432, 20480, 21504,

            # Not used in Prime95 presets
            24576, 25600, 28672, 30720, 32768, 35840,

            # Small FFT
            36864, 40960, 49152, 51200, 61440, 65536, 73728, 81920, 86016, 98304, 102400, 114688, 122880, 131072, 147456, 163840, 172032, 196608, 204800, 229376, 245760,

            # Not used in Prime95 presets
            262144, 286720, 294912, 327680, 344064, 393216, 409600,

            # Large FFT
            458752, 491520, 524288, 573440, 655360, 688128, 786432, 819200, 917504, 983040, 1048576, 1146880, 1179648, 1310720, 1376256, 1474560, 1572864, 1638400,
            1720320, 1835008, 1966080, 2097152, 2293760, 2359296, 2457600, 2621440, 2752512, 2867200, 2949120, 3145728, 3276800, 3440640, 3670016, 3932160, 4194304,
            4587520, 4718592, 4915200, 5242880, 5505024, 5734400, 5898240, 6291456, 6553600, 6881280, 7340032, 7864320, 8192000, 8257536, 8388608,

            # Not used in Prime95 presets
            # Now custom labeled "Huge"
            # 51200K = 52428800 seems to be the maximum FFT size possible for AVX2
            9175040, 9437184, 9830400, 10485760, 11010048, 11468800, 11796480, 12582912, 13107200, 13762560, 14155776, 14680064, 15728640, 16384000, 16515072, 16777216,
            18350080, 18874368, 19660800, 20971520, 22020096, 22937600, 23592960, 25165824, 26214400, 27525120, 29360128, 31457280, 32768000, 33554432, 36700160, 39321600,
            41943040, 45875200, 52428800
        )

        AVX512 = @(
            # Smallest FFT
            4608, 5120, 6144, 7168, 7680, 8192, 9216, 10240, 10752, 12288, 12800, 16384, 18432, 20480,

            # Not used in Prime95 presets
            24576, 25600, 32768,

            # Small FFT
            40960, 49152, 57344, 61440, 65536, 73728, 81920, 86016, 98304, 122880, 131072, 147456, 196608, 204800, 245760,

            # Not used in Prime95 presets
            286720, 294912, 307200, 327680, 344064, 368640, 393216, 401408, 409600,

            # Large FFT
            430080, 442368, 458752, 491520, 516096, 524288, 573440, 589824, 602112, 614400, 655360, 688128, 737280, 786432, 819200, 860160, 884736,
            917504, 983040, 1024000, 1032192, 1048576, 1179648, 1228800, 1310720, 1376256, 1433600, 1474560, 1536000, 1572864, 1638400, 1720320,
            1769472, 1843200, 1966080, 2007040, 2097152, 2150400, 2211840, 2293760, 2359296, 2457600, 2580480, 2621440, 2654208, 2752512, 2949120,
            3010560, 3072000, 3145728, 3211264, 3276800, 3440640, 3538944, 3686400, 3932160, 4014080, 4128768, 4300800, 4423680, 4587520, 4718592,
            4816896, 4915200, 5160960, 5242880, 5308416, 5505024, 5898240, 6193152, 6291456, 6422528, 6553600, 6881280, 7225344, 7340032, 7372800,
            7864320, 8257536,

            # Not used in Prime95 presets
            # Now custom labeled "Huge"
            # 65536K = 67108864 seems to be the maximum FFT size possible for AVX512
            8601600, 8847360, 9175040, 9830400, 10485760, 10616832, 11468800, 11796480, 12582912, 13107200, 13762560, 14745600, 15728640, 16056320,
            16515072, 16777216, 17203200, 17694720, 18350080, 18874368, 19267584, 19660800, 20643840, 20971520, 21233664, 22020096, 22478848, 22937600,
            24084480, 24772608, 25165824, 25690112, 26214400, 27525120, 28311552, 28901376, 29491200, 31457280, 32112640, 33030144, 33718272, 35389440,
            37748736, 38535168, 39321600, 41287680, 41943040, 42467328, 44040192, 47185920, 48168960, 49545216, 50331648, 51380224, 55050240, 56623104,
            57802752, 58720256, 62914560, 67108864
        )
    }


    # The min and max values for the various presets
    # Note that the actually tested sizes differ from the originally provided min and max values
    # depending on the selected test mode (SSE, AVX, AVX2, AVX512)
    $Script:FFTMinMaxValues = @{
        SSE = @{
            SMALLEST   = @{ Min =    4096; Max =    20480; }  # Originally   4 ...   21
            SMALL      = @{ Min =   40960; Max =   245760; }  # Originally  36 ...  248
            LARGE      = @{ Min =  458752; Max =  8388608; }  # Originally 426 ... 8192
            HUGE       = @{ Min = 9175040; Max = 33554432; }  # New addition
            ALL        = @{ Min =    4096; Max = 33554432; }
            MODERATE   = @{ Min = 1376256; Max =  4194304; }
            HEAVY      = @{ Min =    4096; Max =  1376256; }
            HEAVYSHORT = @{ Min =    4096; Max =   163840; }
        }

        AVX = @{
            SMALLEST   = @{ Min =    4096; Max =    21504; }  # Originally   4 ...   21
            SMALL      = @{ Min =   36864; Max =   245760; }  # Originally  36 ...  248
            LARGE      = @{ Min =  458752; Max =  8388608; }  # Originally 426 ... 8192
            HUGE       = @{ Min = 9175040; Max = 33554432; }  # New addition
            ALL        = @{ Min =    4096; Max = 33554432; }
            MODERATE   = @{ Min = 1376256; Max =  4194304; }
            HEAVY      = @{ Min =    4096; Max =  1376256; }
            HEAVYSHORT = @{ Min =    4096; Max =   163840; }
        }

        AVX2 = @{
            SMALLEST   = @{ Min =    4096; Max =    21504; }  # Originally   4 ...   21
            SMALL      = @{ Min =   36864; Max =   245760; }  # Originally  36 ...  248
            LARGE      = @{ Min =  458752; Max =  8388608; }  # Originally 426 ... 8192
            HUGE       = @{ Min = 9175040; Max = 52428800; }  # New addition
            ALL        = @{ Min =    4096; Max = 52428800; }
            MODERATE   = @{ Min = 1376256; Max =  4194304; }
            HEAVY      = @{ Min =    4096; Max =  1376256; }
            HEAVYSHORT = @{ Min =    4096; Max =   163840; }
        }

        AVX512 = @{
            SMALLEST   = @{ Min =    4608; Max =    21504; }  # Originally   4 ...   21
            SMALL      = @{ Min =   40960; Max =   245760; }  # Originally  36 ...  248
            LARGE      = @{ Min =  430080; Max =  8388608; }  # Originally 426 ... 8192
            HUGE       = @{ Min = 8601600; Max = 67108864; }  # New addition
            ALL        = @{ Min =    4608; Max = 67108864; }
            MODERATE   = @{ Min = 1376256; Max =  4194304; }
            HEAVY      = @{ Min =    4608; Max =  1376256; }
            HEAVYSHORT = @{ Min =    4608; Max =   163840; }
        }

        # The limits have changed for Prime95 30.8
        <#
        AVX512 = @{
            SMALLEST   = @{ Min =    4; Max =    42; }  # Originally   4 ...   42
            SMALL      = @{ Min =   73; Max =   455; }  # Originally  73 ...  455
            LARGE      = @{ Min =  780; Max =  8192; }  # Originally 780 ... 8192
            HUGE       = @{ Min = 8400; Max = 65536; }  # New addition
            ALL        = @{ Min =    4; Max = 65536; }
            MODERATE   = @{ Min = 1344; Max =  4096; }
            HEAVY      = @{ Min =    4; Max =  1344; }
            HEAVYSHORT = @{ Min =    4; Max =   160; }
        }
        #>
    }


    # Get the correct min and max values for the selected FFT settings
    if ($settings.mode -eq 'CUSTOM') {
        $Script:minFFTSize = [Int] $settings.Custom.MinTortureFFT * 1024
        $Script:maxFFTSize = [Int] $settings.Custom.MaxTortureFFT * 1024
    }

    # Custom preset (xxx-yyy)
    elseif ($settings.Prime95.FFTSize -match '(\d+)\s*\-\s*(\d+)') {
        $Script:minFFTSize = [Int] [Math]::Min($Matches[1], $Matches[2]) * 1024
        $Script:maxFFTSize = [Int] [Math]::Max($Matches[1], $Matches[2]) * 1024
    }

    # Regular preset
    elseif ($FFTMinMaxValues[$settings.mode].Contains($settings.Prime95.FFTSize.ToUpperInvariant())) {   # This needs to be .Contains()
        $Script:minFFTSize = [Int] $FFTMinMaxValues[$settings.mode.ToUpperInvariant()][$settings.Prime95.FFTSize.ToUpperInvariant()].Min
        $Script:maxFFTSize = [Int] $FFTMinMaxValues[$settings.mode.ToUpperInvariant()][$settings.Prime95.FFTSize.ToUpperInvariant()].Max
    }

    # Something failed
    else {
        Exit-WithFatalError('Could not find the min and max FFT sizes for the provided FFTSize setting "' + $settings.Prime95.FFTSize + '"!')
    }


    # Get the test mode, even if $settings.mode is set to CUSTOM
    $Script:cpuTestMode = $settings.mode

    # If we're in CUSTOM mode, try to determine which setting preset it is
    if ($settings.mode -eq 'CUSTOM') {
        $Script:cpuTestMode = 'SSE'

        if ($settings.Custom.CpuSupportsAVX -eq 1) {
            if ($settings.Custom.CpuSupportsAVX2 -eq 1 -and $settings.Custom.CpuSupportsFMA3 -eq 1) {
                $Script:cpuTestMode = 'AVX2'
            }
            else {
                $Script:cpuTestMode = 'AVX'
            }
        }
    }


    # The provided FFT sizes may not exist in the FFT test array, so we look for the next (min) or previous (max) FFT size
    if (!($FFTSizes[$cpuTestMode] -contains $minFFTSize)) {
        Write-ColorText('WARNING: The selected minimum FFT size (' + $minFFTSize/1024 + 'K) does not exist for the selected mode!') Yellow
        Write-Verbose('The FFTSizes array does not include the current min FFT size, searching for the next size')

        $Script:minFFTSize = ($FFTSizes[$cpuTestMode] | ForEach-Object {
            if ($_ -gt $minFFTSize) {
                $_
            }
        }) | Select-Object -First 1

        # The value can return empty if no next value could be found, i.e. the entered value was higher than the highest available value
        if (!$Script:minFFTSize) {
            $Script:minFFTSize = ($FFTSizes[$cpuTestMode] | Select-Object -Last 1)
        }


        Write-Verbose('Found the new min FFT size: ' + $Script:minFFTSize)
        Write-ColorText('Trying to find the next possible value... set to ' + $Script:minFFTSize/1024 + 'K') Yellow
        Write-ColorText('') Yellow
    }

    if (!($FFTSizes[$cpuTestMode] -contains $maxFFTSize)) {
        Write-ColorText('WARNING: The selected maximum FFT size (' + $maxFFTSize/1024 + 'K) does not exist for the selected mode!') Yellow
        Write-Verbose('The FFTSizes array does not include the current max FFT size, searching for the previous size')

        $Script:maxFFTSize = (($FFTSizes[$cpuTestMode] | Sort-Object -Descending) | ForEach-Object {
            if ($maxFFTSize -gt $_) {
                $_
            }
        }) | Select-Object -First 1


        # The max size cannot be smaller then the min size
        if ( $Script:maxFFTSize -lt $Script:minFFTSize ) {
            Write-Verbose('The maximum FFT size cannot be smaller than the mimimum size, setting it to the same value')
            Write-Verbose('-> ' + $Script:maxFFTSize/1024 + 'K to ' + $Script:minFFTSize/1024 + 'K')
            $Script:maxFFTSize = $Script:minFFTSize
        }

        Write-Verbose('Found the new max FFT size: ' + $Script:maxFFTSize)
        Write-ColorText('Trying to find the previous possible value... set to ' + $Script:maxFFTSize/1024 + 'K') Yellow
        Write-ColorText('') Yellow
    }


    # Get the sub array for the selected FFT preset
    $startKey = [Array]::indexOf($FFTSizes[$cpuTestMode], $minFFTSize)
    $endKey   = [Array]::indexOf($FFTSizes[$cpuTestMode], $maxFFTSize)
    $Script:fftSubarray = $FFTSizes[$cpuTestMode][$startKey..$endKey]

    $modeString  = $settings.mode
    $configFile1 = $stressTestPrograms[$p95Type]['absolutePath'] + 'local.txt'
    $configFile2 = $stressTestPrograms[$p95Type]['absolutePath'] + 'prime.txt'

    $FFTSizeString = $settings.Prime95.FFTSize.ToUpperInvariant() -Replace '\s',''

    Write-Debug('')
    Write-Debug('Checking the FFT Sizes to test:')
    Write-Debug('FFTSizeString: ' + $FFTSizeString)
    Write-Debug('cpuTestMode:   ' + $cpuTestMode)
    Write-Debug('minFFTSize:    ' + $minFFTSize)
    Write-Debug('maxFFTSize:    ' + $maxFFTSize)
    Write-Debug('startKey:      ' + $startKey)
    Write-Debug('endKey:        ' + $endKey)
    Write-Debug('The selected fftSubarray to test:')
    Write-Debug($Script:fftSubarray)



    # The Prime95 results.txt file name and path for this run
    $Script:stressTestLogFileName = 'Prime95_' + $startDateTime + '_' + $modeString + '_' + $FFTSizeString + '_FFT_' + [Math]::Floor($minFFTSize/1024) + 'K-' + [Math]::Ceiling($maxFFTSize/1024) + 'K.txt'
    $Script:stressTestLogFilePath = $logFilePathAbsolute + $stressTestLogFileName

    # Create the local.txt and overwrite if necessary
    $null = New-Item $configFile1 -ItemType File -Force

    # Check if the file exists
    if (!(Test-Path $configFile1 -PathType leaf)) {
        Exit-WithFatalError('Could not create the config file at ' + $configFile1 + '!')
    }


    $content1 = @(
        'RollingAverageIsFromV27=1',
        # Limit the load to the selected number of threads
        'NumCores=1',     # If this is not set, Prime95 will create 1 worker thread for each Core/Thread, seriously slowing down the computer!
        'CoresPerTest=1',
        "CpuSupportsSSE=$(      $prime95CPUSettings[$modeString].CpuSupportsSSE     )",
        "CpuSupportsSSE2=$(     $prime95CPUSettings[$modeString].CpuSupportsSSE2    )",
        "CpuSupportsAVX=$(      $prime95CPUSettings[$modeString].CpuSupportsAVX     )",
        "CpuSupportsAVX2=$(     $prime95CPUSettings[$modeString].CpuSupportsAVX2    )",
        "CpuSupportsFMA3=$(     $prime95CPUSettings[$modeString].CpuSupportsFMA3    )",
        "CpuSupportsAVX512F=$(  $prime95CPUSettings[$modeString].CpuSupportsAVX512  )",
        "NumThreads=$(          $settings.General.numberOfThreads                   )", # This has been renamed from CpuNumHyperthreads
        "WorkerThreads=$(       $settings.General.numberOfThreads                   )"
    ) -join "`r`n"

    Set-Content -Path $configFile1 -Value $content1

    
    # Create the prime.txt and overwrite if necessary
    $null = New-Item $configFile2 -ItemType File -Force

    # Check if the file exists
    if (!(Test-Path $configFile2 -PathType leaf)) {
        Exit-WithFatalError('Could not create the config file at ' + $configFile2 + '!')
    }


    # In 30.4 there's an 80 character limit for the ini settings, so we're using an ugly workaround to put the log file into the /logs/ directory:
    # - set the working directory to the directory where the CoreCycler script is located
    # - then set the paths to the prime.txt and local.txt relative to that working directory
    # This should keep us below 80 characters
    $content2 = @(
        "WorkingDir=$root",

        # Set the custom results.txt file name
        "prime.ini=$(   Join-Path $stressTestPrograms[$p95Type]['processPath'] 'prime.txt' )",
        "local.ini=$(   Join-Path $stressTestPrograms[$p95Type]['processPath'] 'local.txt' )",
        "results.txt=$( Join-Path $logFilePath $stressTestLogFileName                      )",

        # New in Prime95 30.7
        # TortureHyperthreading=0/1
        # Goes into the prime.txt ($configFile2)
        # If we set this here, we need to use NumThreads=1 in local.txt
        # However, TortureHyperthreading introduces inconsistencies with the log format for two threads, so we won't use it
        # Instead, we're using the "old" mechanic of running two worker threads (as in 30.6 and before)
        'TortureHyperthreading=0',
        "TortureMem=$(  if ( $modeString -eq 'CUSTOM' ) { $settings.Custom.TortureMem } else {0}  )",       # 0 = No memory testing ("In-Place")
        "TortureTime=$( if ( $modeString -eq 'CUSTOM' ) { $settings.Custom.TortureTime } else {1} )",       # 1 minute per FFT size
        
        # Set the FFT sizes        
        "MinTortureFFT=$( [Math]::Floor($minFFTSize/1024)   )",     # The minimum FFT size to test
        "MaxTortureFFT=$( [Math]::Ceiling($maxFFTSize/1024) )",     # The maximum FFT size to test

        # Get the correct TortureWeak setting
        "TortureWeak=$( Get-TortureWeakValue )",
        'V24OptionsConverted=1',                    # Flag that the options were already converted from an older version (v24)
        'V30OptionsConverted=1',                    # Flag that the options were already converted from an older version (v29)
        'ExitOnX=1',                                # No minimizing to the tray on close (x)
        'ResultsFileTimestampInterval=60',          # Write to the results.txt every 60 seconds
        'EnableSetAffinity=0',                      # Don't let Prime automatically assign the CPU affinity, we're doing this on our own
        'EnableSetPriority=0',                      # Don't let Prime automatically assign the CPU priority, we're setting it to "High"
        
        # No PrimeNet functionality, just stress testing
        'StressTester=1',
        'UsePrimenet=0'
    ) -join "`r`n"

    Set-Content -Path $configFile2 -Value $content2

    Remove-Variable -Force -Name 'content*'
}


<#
.DESCRIPTION
    Open Prime95 and set global script variables
.PARAMETER
    [Void]
.OUTPUTS
    [Void]
#>
function Start-Prime95 {
    Write-Verbose('Starting Prime95')

    # Minimized to the tray
    #$processId = Start-Process -filepath $stressTestPrograms['prime95']['fullPathToExe'] -ArgumentList '-t' -PassThru -WindowStyle Hidden
    
    # Minimized to the task bar
    # This steals the focus
    #$processId = Start-Process -filepath $stressTestPrograms['prime95']['fullPathToExe'] -ArgumentList '-t' -PassThru -WindowStyle Minimized

    # This doesn't steal the focus
    $command         = $stressTestPrograms[$settings.General.stressTestProgram]['command']
    $windowBehaviour = $stressTestPrograms[$settings.General.stressTestProgram]['windowBehaviour']
    $windowBehaviour = $(if ($stressTestProgramWindowToForeground) {1} else {$windowBehaviour})
    $processId       = [Microsoft.VisualBasic.Interaction]::Shell($command, $windowBehaviour)

    # This might be necessary to correctly read the process. Or not
    Start-Sleep -Milliseconds 500

    # Get the main window and stress test processes, as well as the main window handler
    # This also works for windows minimized to the tray
    Get-StressTestProcessInformation
    
    # This is to find the exact counter path, as you might have multiple processes with the same name
    try {
        # Start a background job to get around the cached Get-Counter value
        $Script:processCounterPathId = Start-Job -ScriptBlock { 
            $counterPathName = $args[0].'FullName'
            $processId = $args[1]
            ((Get-Counter $counterPathName -ErrorAction Ignore).CounterSamples | Where-Object {$_.RawValue -eq $processId}).Path
        } -ArgumentList $counterNames, $stressTestProcessId | Wait-Job | Receive-Job

        if (!$processCounterPathId) {
            Exit-WithFatalError('Could not find the counter path for the Prime95 instance!')
        }

        $Script:processCounterPathTime = $processCounterPathId -replace $counterNames['SearchString'], $counterNames['ReplaceString']

        Write-Verbose('The Performance Process Counter Path for the ID:')
        Write-Verbose($processCounterPathId)
        Write-Verbose('The Performance Process Counter Path for the Time:')
        Write-Verbose($processCounterPathTime)
    }
    catch {
        #'Could not get the process path'
    }
}


<#
.DESCRIPTION
    Close Prime95
.PARAMETER
    [Void]
.OUTPUTS
    [Void]
#>
function Close-Prime95 {
    Write-Verbose('Trying to close Prime95')

    # If there is no windowProcessMainWindowHandler id
    # Try to get it
    if (!$windowProcessMainWindowHandler) {
        Get-StressTestProcessInformation
    }
    
    # If we now have a windowProcessMainWindowHandler, try to close the window
    if ($windowProcessMainWindowHandler) {
        $windowProcess = Get-Process -Id $windowProcessId -ErrorAction Ignore

        # The process may be suspended
        if ($windowProcess) {
            $null = Resume-ProcessWithDebugMethod $windowProcess
        }

        Write-Verbose('Trying to gracefully close Prime95')
        
        # This returns false if no window is found with this handle
        if (!$SendMessage::SendMessage($windowProcessMainWindowHandler, $SendMessage::WM_CLOSE, 0, 0) | Out-Null) {
            #'Process Window not found!'
        }

        # We've send the close request, let's wait up to 2 seconds
        elseif ($windowProcess -and !$windowProcess.HasExited) {
            #'Waiting for the exit'
            $null = $windowProcess.WaitForExit(3000)
        }
    }
    
    
    # If the window is still here at this point, just kill the process
    $windowProcess = Get-Process $processName -ErrorAction Ignore

    if ($windowProcess) {
        Write-Verbose('Could not gracefully close Prime95, killing the process')
        
        #'The process is still there, killing it'
        # Unfortunately this will leave any tray icons behind
        Stop-Process $windowProcess.Id -Force -ErrorAction Ignore
    }
    else {
        Write-Verbose('Prime95 closed')
    }
}


<#
.DESCRIPTION
    Initialize Aida64
.PARAMETER
    [Void]
.OUTPUTS
    [Void]
#>
function Initialize-Aida64 {
    # Check if the aida64.exe exists
    Write-Verbose('Checking if aida64.exe exists at:')
    Write-Verbose($stressTestPrograms['aida64']['fullPathToExe'] + '.' + $stressTestPrograms['aida64']['processNameExt'])

    if (!(Test-Path ($stressTestPrograms['aida64']['fullPathToExe'] + '.' + $stressTestPrograms['aida64']['processNameExt']) -PathType leaf)) {
        Write-ColorText('FATAL ERROR: Could not find Aida64!') Red
        Write-ColorText('Make sure to download and extract the PORTABLE ENGINEER(!) version of Aida64 into the following directory:') Red
        Write-ColorText($stressTestPrograms['aida64']['absoluteInstallPath']) Yellow
        Write-Text ''
        Write-ColorText('You can download the PORTABLE ENGINEER(!) version of Aida64 from:') Red
        Write-ColorText('https://www.aida64.com/downloads') Cyan
        Exit-WithFatalError
    }


    $modesArray = $settings.mode -Split ',\s*'
    $modeString = ($modesArray -Join '-').ToUpperInvariant()

    # TODO: Do we want to offer a way to start Aida64 with admin rights?
    $hasAdminRights = $false


    # Rename the aida64.exe.manifest to aida64.exe.manifest.bak so that we can start as a regular user
    # By default AIDA64 requires admin rights for additional sensory information, which we don't need here
    # TODO: Do we still need this with the /SAFEST command line flag?
    $pathManifest = $stressTestPrograms['aida64']['processPath'] + '\aida64.exe.manifest'
    $pathBackup   = $stressTestPrograms['aida64']['processPath'] + '\aida64.exe.manifest.bak'
    
    if ((Test-Path $pathManifest -PathType leaf)) {
        Write-Verbose('Trying to rename the aida64.exe.manifest file so that we can start AIDA64 as a regular user')
        
        if (!(Move-Item -Path $pathManifest -Destination $pathBackup -PassThru)) {
            Exit-WithFatalError('Could not rename the aida64.exe.manifest file!')
        }

        Write-Verbose('Successfully renamed to aida64.exe.manifest.bak')
    }

    # The Aida64 log file name and path for this run
    $Script:stressTestLogFileName = 'Aida64_' + $startDateTime + '_' + $modeString + '.csv'
    $Script:stressTestLogFilePath = $logFilePathAbsolute + $stressTestLogFileName

    # The aida64.ini and aida64.sst.ini
    $configFile1 = $stressTestPrograms['aida64']['absolutePath'] + 'aida64.ini'
    $configFile2 = $stressTestPrograms['aida64']['absolutePath'] + 'aida64.sst.ini'


    # Create the aida64.ini and overwrite if necessary
    $null = New-Item $configFile1 -ItemType File -Force

    # Check if the file exists
    if (!(Test-Path $configFile1 -PathType leaf)) {
        Exit-WithFatalError('Could not create the config file at ' + $configFile1 + '!')
    }

    $content1 = @(
        '[Generic]',
        'NoGUI=0',
        'LoadWithWindows=0',
        'SplashScreen=0',
        'MinimizeToTray=0',
        'Language=en',
        'ReportHeader=0',
        'ReportFooter=0',
        'ReportMenu=0',
        'ReportDebugInfo=0',
        'ReportDebugInfoCSV=0',
        'ReportHostInFPC=0',
        'HWMonLogToHTM=0',
        'HWMonLogToCSV=1',
        'HWMonLogProcesses=0',
        'HWMonPersistentLog=1',
        'HWMonLogFileOpenFreq=24',
        'HWMonHTMLogFile=',
    
        # $stressTestLogFilePath = 'H:\_Overclock\CoreCycler\logs\Aida64_DATE_TIME_ETC.csv'
        "HWMonCSVLogFile=$stressTestLogFilePath"
    )

    # Which items to include in the log file
    # Unfortunately most of these require admin privileges
    $csvEntriesArr = @()
    
    # Date & Time
    # Works without admin rights
    $csvEntriesArr += 'SDATE STIME'
                        
    # The general CPU core clock
    # Requires admin rights to display the true core clock. If no admin rights, will display the default base clock
    $csvEntriesArr += 'SCPUCLK'

    # The CPU clock for each physical core
    # Requires admin rights
    if ($hasAdminRights) {
        $csvEntriesArr += $(for ($i = 1; $i -le $numLogicalCores; $i++) { 'SCC-1-' + $i })
    }

    # The overall CPU utilization
    # Works without admin rights
    $csvEntriesArr += 'SCPUUTI'

    # The CPU utilization for each logical core
    # Works without admin rights
    $csvEntriesArr += $(for ($i = 1; $i -le $numPhysCores; $i++) { 'SCPU' + $i + 'UTI' })

    # Temperature sensors
    # Here we might have a problem with different sensors on different motherboards
    # TMOBO TCPU TCPUDIO TCHIP TPCHDIO TMOS TTEMP1 TTEMP2

    # Motherboard, CPU, CPU Diode
    # Requires admin rights
    if ($hasAdminRights) {
        $csvEntriesArr += 'TMOBO TCPU TCPUDIO'
    }

    # Voltage sensors
    # Here we might have a problem with different sensors on different motherboards
    # VCPU VCPUVID VCPUNB VCPUVDD VCPUVDDNB
    # Vcore, VID, VDD
    # Requires admin rights
    if ($hasAdminRights) {
        $csvEntriesArr += 'VCPU VCPUVID VCPUVDD'
    }

    # Watt measurements
    # PCPUPKG PCPUVDD PCPUVDDNB
    # CPU Package, CPU VDD
    # Requires admin rights
    if ($hasAdminRights) {
        $csvEntriesArr += 'PCPUPKG PCPUVDD'
    }

    <#
    HWMonLogItems=
    SDATE STIME
    SCPUCLK
    SCC-1-1 SCC-1-2 SCC-1-3 SCC-1-4 SCC-1-5 SCC-1-6 SCC-1-7 SCC-1-8 SCC-1-9 SCC-1-10 SCC-1-11 SCC-1-12
    SCPUUTI
    SCPU1UTI SCPU2UTI SCPU3UTI SCPU4UTI SCPU5UTI SCPU6UTI SCPU7UTI SCPU8UTI SCPU9UTI SCPU10UTI SCPU11UTI SCPU12UTI SCPU13UTI SCPU14UTI SCPU15UTI SCPU16UTI SCPU17UTI SCPU18UTI SCPU19UTI SCPU20UTI SCPU21UTI SCPU22UTI SCPU23UTI SCPU24UTI
    TMOBO TCPU TCPUDIO TCHIP TPCHDIO TMOS TTEMP1 TTEMP2
    VCPU VCPUVID VCPUNB VCPUVDD VCPUVDDNB
    CCPUVDD CCPUVDDNB
    PCPUPKG PCPUVDD PCPUVDDNB
    #>

    $content1 = ($content1 + 'HWMonLogItems=' + ($csvEntriesArr -Join ' ')) -join "`r`n"

    Set-Content -Path $configFile1 -Value $content1


    # Create the aida64.sst.ini and overwrite if necessary
    $null = New-Item $configFile2 -ItemType File -Force

    # Check if the file exists
    if (!(Test-Path $configFile2 -PathType leaf)) {
        Exit-WithFatalError('Could not create the config file at ' + $configFile2 + '!')
    }


    $content2 = @(
        # Start the stress test on max 2 threads, not on all
        'CPUMaskAuto=0',

        # Use AVX?
        "UseAVX=$(    $settings.Aida64.useAVX )",
        "UseAVX512=$( $settings.Aida64.useAVX )",

        # On CPU 2 & 3 if 2 threads | On CPU 2 if 1 thread
        "CPUMask=$( if ( $settings.General.numberOfThreads -gt 1 ) { '0x00000012' } else { '0x00000004' } )",
    
        # Set the maximum amount of memory during the RAM stress test
        "MemAlloc=$( $settings.Aida64.maxMemory )"
    ) -join "`r`n"

    Set-Content -Path $configFile2 -Value $content2

    Remove-Variable -Force -Name 'content*'
}


<#
.DESCRIPTION
    Open Aida64
.PARAMETER startOnlyStressTest
    [Bool] If this is set, it will only start the stress test process and not the whole program
.OUTPUTS
    [Void]
#>
function Start-Aida64 {
    param(
        [Parameter(Mandatory=$false)]
        [Bool] $startOnlyStressTest = $false
    )

    Write-Verbose('Starting Aida64')
    Write-Verbose('The flag to only start the stress test process is: ' + $startOnlyStressTest)

    # Cache or RAM
    #deletevar? $thisMode = $settings.Aida64.mode

    # Check if the main window process exists
    $checkWindowProcess = Get-Process $stressTestPrograms[$settings.General.stressTestProgram]['processName'] -ErrorAction Ignore

    # Sart the main window process if $startOnlyStressTest is not set, or if the main window process wasn't found
    if (!$startOnlyStressTest -or !$checkWindowProcess) {
        if ($startOnlyStressTest -and !$checkWindowProcess) {
            Write-Verbose('The flag to only start the stress test process was set, but couldn''t find the main window!')
            Write-Verbose('Starting the main window process')
        }

        # This doesn't steal the focus
        $command         = $stressTestPrograms[$settings.General.stressTestProgram]['command']
        $windowBehaviour = $stressTestPrograms[$settings.General.stressTestProgram]['windowBehaviour']
        $windowBehaviour = $(if ($stressTestProgramWindowToForeground) {1} else {$windowBehaviour})
        $processId       = [Microsoft.VisualBasic.Interaction]::Shell($command, $windowBehaviour)
        
        $checkWindowProcess = Get-Process -Id $processId -ErrorAction Ignore

        # /SST          = Directly starts the System Stability Test (available tests: Cache, RAM, CPU, FPU, Disk, GPU)
        # /SILENT       = No tray icon, which can stay behind if the main window process is killed
        # /HIDETRAYMENU = Disables the right click menu on the tray icon. Doesn't seem to work though
        # /SAFE         = No low-level PCI, SMBus and sensor scanning
        # /SAFEST       = No kernel drivers are loaded

        #aida64.exe /SAFEST /SILENT /SST CACHE
        #aida64.exe /SAFEST /HIDETRAYMENU /SST CACHE

        # Don't start only the stress test further below
        $startOnlyStressTest = $false
    }


    # Aida64 takes some additional time to load
    # Check for the stress test process, if it's loaded, we're ready to go
    $timestamp = Get-Date -format HH:mm:ss
    Write-Text($timestamp + ' - Waiting for Aida64 to load the stress test...')

    # Repeat the whole process up to 6 times, i.e. 6x10x0,5 = 30 seconds total runtime before it errors out
    :LoopStartProcess for ($i = 1; $i -le 6; $i++) {
        if ($startOnlyStressTest) {
            # Send a keyboard command to the Aida64 window to start the stress test process
            Send-CommandToAida64 'start'
        }

        # Repeat the check every 500ms
        for ($j = 0; $j -lt 10; $j++) {
            $stressTestProcess = Get-Process $stressTestPrograms[$settings.General.stressTestProgram]['processNameForLoad'] -ErrorAction Ignore

            $timestamp = Get-Date -format HH:mm:ss

            if ($stressTestProcess) {
                Write-Text($timestamp + ' - Aida64 started')
                break LoopStartProcess
            }
            else {
                Write-Verbose($timestamp + ' - ... stress test process not found yet')
            }

            Start-Sleep -Milliseconds 500
        }
    }
    
    # Either the main window or the stress test process wasn't found
    if (!$checkWindowProcess -or !$stressTestProcess) {
        # If $startOnlyStressTest was set, try again without the flag
        if ($startOnlyStressTest) {
            Write-Verbose('Couldn''t start the main window or stress test process')
            Write-Verbose('Close all processes and try again from scratch')
            Close-Aida64
            Start-Aida64
            return
        }

        Exit-WithFatalError('Could not start the process "' + $stressTestPrograms['aida64']['processName'] + '"!')
    }

    # Get the main window and stress test processes, as well as the main window handler
    # This also works for windows minimized to the tray
    Get-StressTestProcessInformation

    # This is to find the exact counter path, as you might have multiple processes with the same name
    try {
        # Start a background job to get around the cached Get-Counter value
        $Script:processCounterPathId = Start-Job -ScriptBlock { 
            $counterPathName = $args[0].'FullName'
            $processId = $args[1]
            ((Get-Counter $counterPathName -ErrorAction Ignore).CounterSamples | Where-Object {$_.RawValue -eq $processId}).Path
        } -ArgumentList $counterNames, $stressTestProcessId | Wait-Job | Receive-Job

        if (!$processCounterPathId) {
            Exit-WithFatalError('Could not find the counter path for the Aida64 stress test instance!')
        }

        $Script:processCounterPathTime = $processCounterPathId -replace $counterNames['SearchString'], $counterNames['ReplaceString']

        Write-Verbose('The Performance Process Counter Path for the ID:')
        Write-Verbose($processCounterPathId)
        Write-Verbose('The Performance Process Counter Path for the Time:')
        Write-Verbose($processCounterPathTime)
    }
    catch {
        #'Could not get the process path'
    }
}


<#
.DESCRIPTION
    Close Aida64
.PARAMETER closeOnlyStressTest
    [Bool] If set to true, will try to only stop the stress test process and not the whole program
.OUTPUTS
    [Void]
#>
function Close-Aida64 {
    param(
        [Parameter(Mandatory=$false)]
        [Bool] $closeOnlyStressTest = $false
    )


    if ($settings.General.restartTestProgramForEachCore) {
        Write-Text('           Trying to close Aida64')
    }
    else {
        Write-Verbose('Trying to close Aida64')
    }

    Write-Verbose('The flag to only close the stress test process is: ' + $closeOnlyStressTest)


    $thisStressTestProcess = $null
    $success = $false

    # If there is no windowProcessMainWindowHandler id
    # Try to get it
    if (!$windowProcessMainWindowHandler) {
        # Set the flag to not stop if the stress test process wasn't found
        # It may not be running
        Get-StressTestProcessInformation $false
    }

    # The stress test window cannot be closed gracefully, as it has no main window
    # We could just kill it, but this leaves behind a tray icon and an error message the next time Aida is opened
    # Instead, we send a keystroke command to the Aida64 window. Funky!
    if ($stressTestProcessId) {
        Write-Verbose('The stress test process id is set, assuming the process exists as well')

        $thisStressTestProcess = Get-Process -Id $stressTestProcessId -ErrorAction Ignore

        # The process may be suspended
        if ($thisStressTestProcess) {
            $null = Resume-ProcessWithDebugMethod $thisStressTestProcess
        }
        else {
            Write-Verbose('The stress test process id is set, but no stress test process was found!')
        }

        # We can only send a keyboard command if the main window also still exists
        if ($thisStressTestProcess -and $windowProcessMainWindowHandler) {
            Write-Verbose('The stress test and the main window process exist')

            # Repeat the whole process up to 3 times, i.e. 3x10x0,5 = 15 seconds total runtime before it errors out
            :LoopStopProcess for ($i = 1; $i -le 3; $i++) {
                # Send a keyboard command to the Aida64 window to stop the stress test process
                Send-CommandToAida64 'stop'

                # Repeat the check every 500ms
                for ($j = 0; $j -lt 10; $j++) {
                    $thisStressTestProcess = Get-Process $stressTestPrograms[$settings.General.stressTestProgram]['processNameForLoad'] -ErrorAction Ignore

                    $timestamp = Get-Date -format HH:mm:ss

                    if ($thisStressTestProcess) {
                        Write-Verbose($timestamp + ' - ... the stress test process still exists')
                    }
                    else {
                        Write-Verbose($timestamp + ' - The stress test process has successfully closed')
                        $success = $true
                        break LoopStopProcess
                    }

                    Start-Sleep -Milliseconds 500
                }
            }
        }
    }


    # No windowProcessMainWindowHandler was found
    if ($thisStressTestProcess -and !$windowProcessMainWindowHandler) {
        Write-Verbose('Apparently there''s no main window, but the stress test is still running!')
    }

    # If the stress test process couldn't be closed gracefully
    # We need to kill the whole program including the main window, or we may not be able to start the stress test again
    if ($closeOnlyStressTest -and $thisStressTestProcess) {
        Write-Verbose('The stress test process couldn''t be stopped, we need to kill both the stress test and the main window process')

        # Set the flag to also close the main window at this point
        $closeOnlyStressTest = $false
    }


    # Fallback to killing the process, with all its side effects
    if ($thisStressTestProcess -and !$success) {
        Write-Verbose('Killing the stress test program process')
        Stop-Process $thisStressTestProcess.Id -Force -ErrorAction Ignore
    }


    # If we now have a windowProcessMainWindowHandler, first try to close the main window gracefully
    # But only if $closeOnlyStressTest is false
    if (!$closeOnlyStressTest) {
        if ($windowProcessMainWindowHandler) {
            Write-Verbose('Trying to gracefully close Aida64')
            Write-Verbose('windowProcessId: ' + $windowProcessId)
            
            $windowProcess = Get-Process -Id $windowProcessId -ErrorAction Ignore

            # The process may be suspended
            if ($windowProcess) {
                Write-Verbose('The process may be suspended, resuming')
                $null = Resume-ProcessWithDebugMethod $windowProcess
            }

            Write-Verbose('Sending the close message to the main window')

            # Send the message to close the main window
            # The window may still be blocked from the stress test process being closed, so repeat if necessary
            for ($i = 0; $i -lt 5; $i++) {
                $null = $SendMessage::SendMessage($windowProcessMainWindowHandler, $SendMessage::WM_CLOSE, 0, 0)

                # We've send the close request, let's wait a second for it to actually exit
                if ($windowProcess -and !$windowProcess.HasExited) {
                    $timestamp = Get-Date -format HH:mm:ss
                    Write-Verbose($timestamp + ' - Sent the close message, waiting for the program to exit')
                    $null = $windowProcess.WaitForExit(1500)
                }

                $hasExited = $windowProcess.HasExited
                Write-Verbose('         - ... has exited: ' + $hasExited)

                if ($windowProcess.HasExited) {
                    Write-Verbose('The main window has exited')
                    break
                }
            }
        }
        
        $timestamp = Get-Date -format HH:mm:ss
        Write-Verbose($timestamp + ' - Checking if the main window process still exists:')
        
        # If the window is still here at this point, just kill the process
        $windowProcess = Get-Process $stressTestPrograms['aida64']['processName'] -ErrorAction Ignore

        if ($windowProcess) {
            Write-Verbose('Still there, could not gracefully close Aida64, forcefully killing the process')
            
            # Unfortunately this will leave any tray icons behind
            Stop-Process $windowProcess.Id -Force -ErrorAction Ignore
        }

        # Check if both processes are gone
        $checkWindowProcess     = Get-Process $stressTestPrograms['aida64']['processName'] -ErrorAction Ignore
        $checkStressTestProcess = Get-Process $stressTestPrograms['aida64']['processNameForLoad'] -ErrorAction Ignore

        if (!$checkWindowProcess -and !$checkStressTestProcess) {
            Write-Verbose('Aida64 closed')
        }
        else {
            if ($checkWindowProcess) {
                Write-Verbose('The main window process still exists')
            }

            if ($checkStressTestProcess) {
                Write-Verbose('The stress test process still exists')
            }

            Write-Verbose('Could not close Aida64 successfully. Actually this is weird and should not happen.')
        }
    }

    # Aida64 seems to create a "sst-is-running.txt" file in the %TEMP% directory
    # Is this something we can utilize?
}


<#
.DESCRIPTION
    Create the y-Cruncher config file
    This depends on the $settings.mode variable
.PARAMETER
    [Void]
.OUTPUTS
    [Void]
#>
function Initialize-yCruncher {

    $fullPathToExe = $stressTestPrograms['ycruncher']['fullPathToExe']

    if ($isYCruncherWithLogging) {
        $fullPathToExe = $stressTestPrograms['ycruncher']['fullPathToLoadExe']
    }

    # Check if the selected binary exists
    Write-Verbose('Checking if ' + $stressTestPrograms['ycruncher']['processNameForLoad'] + '.' + $stressTestPrograms['ycruncher']['processNameExt'] + ' exists at:')
    Write-Verbose($fullPathToExe + '.' + $stressTestPrograms['ycruncher']['processNameExt'])

    if (!(Test-Path ($fullPathToExe + '.' + $stressTestPrograms['ycruncher']['processNameExt']) -PathType leaf)) {
        Write-ColorText('FATAL ERROR: Could not find y-Cruncher!') Red
        Write-ColorText('Make sure to download and extract y-Cruncher into the following directory:') Red
        Write-ColorText($stressTestPrograms['ycruncher']['absoluteInstallPath']) Yellow
        Write-Text ''
        Write-ColorText('You can download y-Cruncher from:') Red
        Write-ColorText('http://www.numberworld.org/y-cruncher/#Download') Cyan
        Exit-WithFatalError
    }

    $modeString    = $settings.mode
    $configFile    = $stressTestPrograms['ycruncher']['configFilePath']
    $selectedTests = $settings.yCruncher.tests


    # The "C17" test only works with "13-HSW ~ Airi" and above
    # Let's use the first two digits to determine this (so 00 to 22)
    if ($selectedTests.Contains('C17')) {
        $modeNum = [Int] $modeString.Substring(0, 2)

        if ($modeNum -lt 13) {
            Exit-WithFatalError('Test "C17" is present in the "tests" setting, but the selected y-Cruncher mode "' + $modeString + '" does not support it! Aborting!')
        }
    }

    # Create the config file and overwrite if necessary
    $null = New-Item $configFile -ItemType File -Force

    # Check if the file exists
    if (!(Test-Path $configFile -PathType leaf)) {
        Exit-WithFatalError('Could not create the config file at ' + $configFile + '!')
    }


    # The tests to run
    $testsToRun = $selectedTests | ForEach-Object { -Join('            "', $_, '"') }

    $configEntries = (@(
        '',
        '{',
        '    Action : "StressTest"',
        '    StressTest : {',
        '        AllocateLocally : "true"',
        # Cores line
        "        LogicalCores : [$( if ( $settings.General.numberOfThreads -gt 1 ) { '2 3' } else { '2' })]",
        # Memory Line
        "        TotalMemory : $( if ( $settings.yCruncher.memory -ne 'Default' ) { $settings.yCruncher.memory } elseif ( $settings.General.numberOfThreads -gt 1 ) { '2 3' } else { '13418572' })",
        "        SecondsPerTest : $(if ( $settings.yCruncher.testDuration -gt 0 ) { $settings.yCruncher.testDuration } else { '60' })",   # The duration per test
        '        SecondsTotal : 0',
        "        StopOnError : $( if ( $settings.yCruncher.enableYCruncherLoggingWrapper -eq 1 -and $settings.General.stopOnError -eq 0 ) { '`"false`"' } else { '`"true`"' })",
        '        Tests : [',
        $testsToRun
        '        ]',
        '    }',
        '}'
    ) | ForEach-Object { $_ }) -join "`r`n"


    Set-Content -Path $configFile -Value $configEntries -Force

}


<#
.DESCRIPTION
    Open y-Cruncher and set global script variables
.PARAMETER
    [Void]
.OUTPUTS
    [Void]
#>
function Start-yCruncher {
    Write-Verbose('Starting y-Cruncher')

    #deletevar? $thisMode = $settings.yCruncher.mode

    # Minimized to the tray
    #$processId = Start-Process -filepath $stressTestPrograms['ycruncher']['fullPathToExe'] -ArgumentList ('config "' + $stressTestConfigFilePath + '"') -PassThru -WindowStyle Hidden
    
    # Minimized to the task bar
    # This steals the focus
    #$processId = Start-Process -filepath $stressTestPrograms['ycruncher']['fullPathToExe'] -ArgumentList ('config "' + $stressTestConfigFilePath + '"') -PassThru -WindowStyle Minimized
    #$processId = Start-Process -filepath $stressTestPrograms['ycruncher']['fullPathToExe'] -ArgumentList ('config "' + $stressTestConfigFilePath + '"') -PassThru

    # This doesn't steal the focus
    # We need to use conhost, otherwise the output would be inside the current console window
    # Caution, calling conhost here will also return the process id of the conhost.exe file, not the one for the y-Cruncher binary!
    # The escape character in Visual Basic for double quotes seems to be... a double quote!
    # So a triple double quote is actually interpreted as a single double quote here
    #$processId = [Microsoft.VisualBasic.Interaction]::Shell(("conhost.exe """ + $stressTestPrograms['ycruncher']['fullPathToExe'] + """ config """ + $stressTestConfigFilePath + """"), 6) # 6 = MinimizedNoFocus

    # 0 = Hide
    # Apparently on some computers (not mine) the windows title is not set to the binary path, so the Get-StressTestProcessInformation function doesn't work
    # Therefore we're now using "cmd /C start" to be able to set a window title...
    
    $command         = $stressTestPrograms[$settings.General.stressTestProgram]['command']
    $command         = $(if ($stressTestProgramWindowToForeground) {$command.replace('/MIN ', '')} else {$command})   # Remove the /MIN so that the window isn't placed in the background
    $windowBehaviour = $stressTestPrograms[$settings.General.stressTestProgram]['windowBehaviour']
    $windowBehaviour = $(if ($stressTestProgramWindowToForeground) {1} else {$windowBehaviour})
    $processId       = [Microsoft.VisualBasic.Interaction]::Shell($command, $windowBehaviour)

    Write-Verbose('The executed command:')
    Write-Verbose($command)


    # This might be necessary to correctly read the process. Or not
    Start-Sleep -Milliseconds 500

    # Get the main window and stress test processes, as well as the main window handler
    # This also works for windows minimized to the tray
    Get-StressTestProcessInformation
    
    # This is to find the exact counter path, as you might have multiple processes with the same name
    try {
        # Start a background job to get around the cached Get-Counter value
        $Script:processCounterPathId = Start-Job -ScriptBlock { 
            $counterPathName = $args[0].'FullName'
            $processId = $args[1]
            ((Get-Counter $counterPathName -ErrorAction Ignore).CounterSamples | Where-Object {$_.RawValue -eq $processId}).Path
        } -ArgumentList $counterNames, $stressTestProcessId | Wait-Job | Receive-Job

        if (!$processCounterPathId) {
            Exit-WithFatalError('Could not find the counter path for the y-Cruncher instance!')
        }

        $Script:processCounterPathTime = $processCounterPathId -replace $counterNames['SearchString'], $counterNames['ReplaceString']

        Write-Verbose('The Performance Process Counter Path for the ID:')
        Write-Verbose($processCounterPathId)
        Write-Verbose('The Performance Process Counter Path for the Time:')
        Write-Verbose($processCounterPathTime)
    }
    catch {
        #'Could not get the process path'
    }
}


<#
.DESCRIPTION
    Close y-Cruncher
.PARAMETER
    [Void]
.OUTPUTS
    [Void]
#>
function Close-yCruncher {
    Write-Verbose('Trying to close y-Cruncher')

    # If there is no windowProcessMainWindowHandler id
    # Try to get it
    if (!$windowProcessMainWindowHandler) {
        Get-StressTestProcessInformation
    }
    
    # If we now have a windowProcessMainWindowHandler, try to close the window
    if ($windowProcessMainWindowHandler) {
        $windowProcess = Get-Process -Id $windowProcessId -ErrorAction Ignore

        # The process may be suspended
        if ($windowProcess) {
            $null = Resume-ProcessWithDebugMethod $windowProcess
        }

        Write-Verbose('Trying to gracefully close y-Cruncher')
        
        # This returns false if no window is found with this handle
        if (!$SendMessage::SendMessage($windowProcessMainWindowHandler, $SendMessage::WM_CLOSE, 0, 0) | Out-Null) {
            #'Process Window not found!'
        }

        # We've send the close request, let's wait up to 2 seconds
        elseif ($windowProcess -and !$windowProcess.HasExited) {
            #'Waiting for the exit'
            $null = $windowProcess.WaitForExit(3000)
        }
    }
    
    
    # If the window is still here at this point, just kill the process
    $windowProcess = Get-Process $processName -ErrorAction Ignore

    if ($windowProcess) {
        Write-Verbose('Could not gracefully close y-Cruncher, killing the process')
        
        #'The process is still there, killing it'
        # Unfortunately this will leave any tray icons behind
        Stop-Process $windowProcess.Id -Force -ErrorAction Ignore
    }
    else {
        Write-Verbose('y-Cruncher closed')
    }
}


<#
.DESCRIPTION
    Initialize the selected stress test program
.PARAMETER
    [Void]
.OUTPUTS
    [Void]
#>
function Initialize-StressTestProgram {
    Write-Verbose('Initializing the stress test program')

    if ($isPrime95) {
        Test-Prime95
        Initialize-Prime95
    }
    elseif ($isAida64) {
        Initialize-Aida64
    }
    elseif ($isYCruncher) {
        Initialize-yCruncher
    }
    else {
        Exit-WithFatalError('No stress test program selected!')
    }
}


<#
.DESCRIPTION
    Start the selected stress test program
.PARAMETER startOnlyStressTest
    [Bool] If this is set, it will only start the stress test process and not the whole program
.OUTPUTS
    [Void]
#>
function Start-StressTestProgram {
    param(
        [Parameter(Mandatory=$false)]
        [Bool] $startOnlyStressTest = $false
    )

    Write-Verbose('Starting the stress test program')

    if ($isPrime95) {
        Start-Prime95 $startOnlyStressTest
    }
    elseif ($isAida64) {
        Start-Aida64 $startOnlyStressTest
    }
    elseif ($isYCruncher) {
        Start-yCruncher $startOnlyStressTest
    }
    else {
        Exit-WithFatalError('No stress test program selected!')
    }
}


<#
.DESCRIPTION
    Close the selected stress test program
.PARAMETER closeOnlyStressTest
    [Bool] If this is set, it will only close the stress test process and not the whole program
.OUTPUTS
    [Void]
#>
function Close-StressTestProgram {
    param(
        [Parameter(Mandatory=$false)]
        [Bool] $closeOnlyStressTest = $false
    )

    Write-Verbose('Trying to close the stress test program')

    if ($isPrime95) {
        Close-Prime95 $closeOnlyStressTest
    }
    elseif ($isAida64) {
        Close-Aida64 $closeOnlyStressTest
    }
    elseif ($isYCruncher) {
        Close-yCruncher $closeOnlyStressTest
    }
    else {
        Exit-WithFatalError('No stress test program selected!')
    }
}


<#
.DESCRIPTION
    Check if there has been an error while running the stress test program and restart it if necessary
    Checks the existance of the process, the log file (if available), and the CPU utilization (if the setting is enabled)
    Throws an error if something is wrong (PROCESSMISSING, CALCULATIONERROR, CPULOAD)
.PARAMETER coreNumber
    [Int] The current core being tested
.OUTPUTS
    [Void] But throws a string if there was an error with the CPU usage (PROCESSMISSING, CALCULATIONERROR, CPULOAD)
#>
function Test-StressTestProgrammIsRunning {
    param (
        $coreNumber
    )

    # Clear any previous errors
    $Error.Clear()

    $timestamp = Get-Date -format HH:mm:ss
    
    # Set to a string if there was an error
    $stressTestError = $false

    # Does the stress test process still exist?
    $checkProcess = Get-Process -Id $stressTestProcessId -ErrorAction Ignore

    # What type of error occurred (PROCESSMISSING, CALCULATIONERROR, CPULOAD)
    $errorType = $null
    

    # 1. The process doesn't exist anymore, immediate error
    if (!$checkProcess) {
        $stressTestError = 'The ' + $selectedStressTestProgram + ' process doesn''t exist anymore.'
        $errorType = 'PROCESSMISSING'
    }

    
    # 2. If using Prime95, parse the results.txt file and look for an error message
    # y-Cruncher produces no log file
    if (!$stressTestError -and $isPrime95) {

        # Look for a line with an "error" string in the new log entries
        $errorResults = $newLogEntries | Where-Object {$_.Line -match '.*error.*'} | Select-Object -Last 1
        
        # Found the "error" string
        if ($errorResults.Length -gt 0) {
            # We don't need to check for a false alarm anymore, as we're already checking only new log entries
            $stressTestError = $errorResults.Line
            $errorType = 'CALCULATIONERROR'

            Write-Verbose($timestamp)
            Write-Verbose('Found an error in the new entries of the results.txt!')
        }
    }


    # 2a. But we can use a wrapper to capture the output for yCruncher!
    if (!$stressTestError -and $isYCruncherWithLogging) {

        # The messages y-Cruncher displays:
        # Exception Encountered: XYZ
        # 
        # <ERROR MESSAGE>
        # <May have multiple lines>
        # 
        # 
        # Error(s) encountered on logical core X
        # 
        # Failed  Test Speed <...>
        # Errors encountered. Stopping test...

        # Look for a line with an "error" string in the new log entries
        $errorResults = $newLogEntries | Where-Object {$_.Line -match '.*error\(s\).*'} | Select-Object -Last 1
        
        # Found the "error" string
        if ($errorResults.Length -gt 0) {
            # We don't need to check for a false alarm anymore, as we're already checking only new log entries
            $stressTestError = $errorResults.Line
            $errorType = 'CALCULATIONERROR'

            Write-Verbose($timestamp)
            Write-Verbose('Found an error in the new entries of the y-Cruncher output!')

            # For y-Cruncher, remove the core number, since it doesn't represent the actual core being tested
            $stressTestError = $stressTestError -replace '\s*\d+\.', ''
        }
    }


    # 3. Check if the process is still using enough CPU process power
    if (!$stressTestError) {
        # If the CPU utilization check is disabled in the settings
        if ($disableCpuUtilizationCheck -gt 0) {
            Write-Verbose('Checking CPU usage is disabled, skipping the check')
        }

        else {
            # Get the CPU percentage
            $processCPUPercentage = [Math]::Round(((Get-Counter $processCounterPathTime -ErrorAction Ignore).CounterSamples.CookedValue) / $numLogicalCores, 2)
            
            Write-Verbose($timestamp + ' - Checking CPU usage: ' + $processCPUPercentage + '%')

            # It doesn't use enough CPU power
            if ($processCPUPercentage -le $minProcessUsage) {

                # For Prime95
                if ($isPrime95) {
                    # Look for a line with an "error" string in the new log entries
                    $errorResults = $newLogEntries | Where-Object {$_.Line -match '.*error.*'} | Select-Object -Last 1
                    
                    # Found the "error" string
                    if ($errorResults.Length -gt 0) {
                        # We don't need to check for a false alarm anymore, as we're already checking only new log entries
                        $stressTestError = $errorResults.Line
                        $errorType = 'CALCULATIONERROR'
                    }
                }


                # For y-Cruncher with logging enabled
                if ($isYCruncherWithLogging) {
                    # Look for a line with an "error" string in the new log entries
                    $errorResults = $newLogEntries | Where-Object {$_.Line -match '.*error\(s\).*'} | Select-Object -Last 1
                    
                    # Found the "error" string
                    if ($errorResults.Length -gt 0) {
                        # We don't need to check for a false alarm anymore, as we're already checking only new log entries
                        $stressTestError = $errorResults.Line
                        $errorType = 'CALCULATIONERROR'
                    }
                }



                # Error string still not found
                # This might have been a false alarm, wait a bit and try again
                if (!$stressTestError) {
                    $waitTime  = 2000
                    $maxChecks = 3

                    # Repeat the CPU usage check $maxChecks times and only throw an error if the process hasn't recovered by then
                    for ($curCheck = 1; $curCheck -le $maxChecks; $curCheck++) {
                        $timestamp = Get-Date -format HH:mm:ss
                        Write-Verbose($timestamp + ' - ...the CPU usage was too low, waiting ' + $waitTime + 'ms for another check...')

                        Start-Sleep -Milliseconds $waitTime

                        # The additional check
                        # Do the whole process path procedure again
                        $thisProcessId = $checkProcess.Id[0]

                        Write-Verbose('Process Id: ' + $thisProcessId)

                        # Start a background job to get around the cached Get-Counter value
                        $thisProcessCounterPathId = Start-Job -ScriptBlock { 
                            $counterPathName = $args[0].'FullName'
                            $processId = $args[1]
                            ((Get-Counter $counterPathName -ErrorAction Ignore).CounterSamples | Where-Object {$_.RawValue -eq $processId}).Path
                        } -ArgumentList $counterNames, $thisProcessId | Wait-Job | Receive-Job

                        $thisProcessCounterPathTime = $thisProcessCounterPathId -replace $counterNames['SearchString'], $counterNames['ReplaceString']
                        $thisProcessCPUPercentage   = [Math]::Round(((Get-Counter $thisProcessCounterPathTime -ErrorAction Ignore).CounterSamples.CookedValue) / $numLogicalCores, 2)

                        $timestamp = Get-Date -format HH:mm:ss
                        Write-Verbose($timestamp + ' - Checking CPU usage again (#' + $curCheck + '): ' + $thisProcessCPUPercentage + '%')

                        # If we have recovered, break and continue with stresss testing
                        if ($thisProcessCPUPercentage -ge $minProcessUsage) {
                            Write-Verbose('           The process seems to have recovered, continuing with stress testing')
                            break
                        }

                        else {
                            if ($curCheck -lt $maxChecks) {
                                Write-Verbose('           Still not enough usage (#' + $curCheck + ')')
                            }
                            
                            # Reached the maximum amount of checks for the CPU usage
                            else {
                                Write-Verbose('           Still not enough usage, throw an error')

                                # We don't care about an error string here anymore
                                $stressTestError = 'The ' + $selectedStressTestProgram + ' process doesn''t use enough CPU power anymore (only ' + $thisProcessCPUPercentage + '% instead of the expected ' + $expectedUsageTotal + '%)'
                                $errorType = 'CPULOAD'
                            }

                        }
                    }
                }
            }
        }
    }

    # We now have an error message, process
    if ($stressTestError) {
        Write-Verbose('There has been an error while running the stress test program!')
        Write-Verbose('Error type: ' + $errorType)

        # Store the core number in the array
        $Script:coresWithError += $coreNumber

        # Count the number of errors per core
        $Script:coresWithErrorsCounter[$coreNumber]++ 

        $cpuNumbersArray = @()

        # If the number of threads is more than 1
        if ($settings.General.numberOfThreads -gt 1) {
            for ($currentThread = 0; $currentThread -lt $settings.General.numberOfThreads; $currentThread++) {
                # We don't care about Hyperthreading / SMT here, it needs to be enabled for 2 threads
                $cpuNumber        = ($actualCoreNumber * 2) + $currentThread
                $cpuNumbersArray += $cpuNumber
            }
        }

        # Only one thread
        else {
            # assignBothVirtualCoresForSingleThread is enabled, we want to use both virtual cores, but with only one thread
            # The load should bounce back and forth between the two cores this way
            # Hyperthreading needs to be enabled for this
            if ($settings.General.assignBothVirtualCoresForSingleThread -and $isHyperthreadingEnabled) {
                for ($currentThread = 0; $currentThread -lt 2; $currentThread++) {
                    $cpuNumber        = ($actualCoreNumber * 2) + $currentThread
                    $cpuNumbersArray += $cpuNumber
                }
            }

            # Setting not active, only one core for the load thread
            else {
                # If Hyperthreading / SMT is enabled, the tested CPU number is 0, 2, 4, etc
                # Otherwise, it's the same value
                $cpuNumber        = $actualCoreNumber * (1 + [Int] $isHyperthreadingEnabled)
                $cpuNumbersArray += $cpuNumber
            }
        }

        $cpuNumberString = (($cpuNumbersArray | Sort-Object) -Join ' or ')


        # If running Prime95 or y-Cruncher with logging wrapper, make one additional check if the log file now has an error entry
        if (($isPrime95 -or $isYCruncherWithLogging) -and $errorType -ne 'CALCULATIONERROR') {
            $timestamp = Get-Date -format HH:mm:ss

            Write-Verbose($timestamp + ' - The stress test program has a log file, trying to look for an error message in the log')
            
            Get-NewLogfileEntries

            # Prime95: Look for a line with an "error" string in the new log entries
            if ($isPrime95) {
                $errorResults = $newLogEntries | Where-Object {$_.Line -match '.*error.*'} | Select-Object -Last 1
            }

            # y-Cruncher: Look for error(s)
            elseif ($isYCruncherWithLogging) {
                $errorResults = $newLogEntries | Where-Object {$_.Line -match '.*error\(s\).*'} | Select-Object -Last 1
            }
            
            # Found the "error" string
            if ($errorResults.Length -gt 0) {
                # We don't need to check for a false alarm anymore, as we're already checking only new log entries
                $stressTestError = $errorResults.Line

                # For y-Cruncher, remove the core number, since it doesn't represent the actual core being tested
                if ($isYCruncherWithLogging) {
                    $stressTestError = $stressTestError -replace '\s*\d+\.', ''
                }

                Write-Verbose($timestamp)
                Write-Verbose('           Now found an error in the new entries of the log file!')
            }
        }

        # Put out an error message
        $timestamp = Get-Date -format HH:mm:ss
        Write-ColorText('ERROR: ' + $timestamp) Magenta
        Write-ColorText('ERROR: There has been an error while running ' + $selectedStressTestProgram + '!') Magenta
        Write-ColorText('ERROR: At Core ' + $coreNumber + ' (CPU ' + $cpuNumberString + ')') Magenta
        Write-ColorText('ERROR MESSAGE: ' + $stressTestError) Magenta


        # Try to get more detailed error information
        # Prime95
        if ($isPrime95) {
            # Try to determine the last run FFT size

            # In newer Prime95 versions, the FFT size is provided in the results.txt
            # In older versions, we have to make an eduacted guess

            # Check in the error message
            # "Hardware failure detected running 10752K FFT size, consult stress.txt file."
            $lastFFTErrorEntry = $newLogEntries | Where-Object {$_.Line -match 'Hardware failure detected running \d+K FFT size*'} | Select-Object -Last 1

            if ($lastFFTErrorEntry) {
                Write-Verbose('There was an FFT size provided in the error message, use it.')

                $hasMatched = $lastFFTErrorEntry -match 'Hardware failure detected running (\d+)K FFT size'
                $lastRunFFT = if ($hasMatched) { [Int] $Matches[1] }   # $Matches is a fixed(?) variable name for -match

                Write-ColorText('ERROR: The error happened at FFT size ' + $lastRunFFT + 'K') Magenta
            }



            # If nothing was found, try to guess
            else {
                # If the results.txt doesn't exist, assume that it was on the very first iteration
                # Note: Unfortunately Prime95 randomizes the FFT sizes for anything above Large FFT sizes
                #       So we cannot make an educated guess for these settings
                #if ($maxFFTSize -le $FFTMinMaxValues[$settings.mode]['LARGE'].Max) {
                
                # This check is taken from the Prime95 source code:
                # if (fftlen > max_small_fftlen * 2) num_large_lengths++;
                # The max smallest FFT size is 240, so starting with 480 the order should get randomized
                # Large FFTs are not randomized, Huge FFTs and All FFTs are

                Write-Verbose('No FFT size provided in the error message, make an educated guess.')


                # Temporary(?) solution
                if ($maxFFTSize -le $FFTMinMaxValues['SSE']['LARGE']['Max']) {
                    Write-Verbose('The maximum FFT size is within the range where we can still make an educated guess about the failed FFT size')

                    # There were no log entries yet
                    if (!$allLogEntries -or $allLogEntries.Count -eq 0) { 
                        Write-Verbose('No results.txt exists yet, assuming the error happened on the first FFT size')
                        $lastRunFFT = $minFFTSize
                    }
                    
                    # Get the last couple of rows and find the last passed FFT size
                    else {
                        Write-Verbose('Trying to find the last passed FFT sizes')

                        $lastFiveRows     = $allLogEntries | Select-Object -Last 5
                        $lastPassedFFTArr = @($lastFiveRows | Where-Object {$_ -like '*passed*'})  # This needs to be an array
                        $hasMatched       = $lastPassedFFTArr[$lastPassedFFTArr.Length-1] -match 'Self\-test (\d+)(K?) passed'
                        
                        if ($hasMatched) {
                            if ($Matches[2] -eq 'K') {
                                $lastPassedFFT = [Int] $Matches[1] * 1024
                            }
                            else {
                                $lastPassedFFT = [Int] $Matches[1]
                            }
                        }

                        # No passed FFT was found, assume it's the first FFT size
                        if (!$lastPassedFFT) {
                            $lastRunFFT = $minFFTSize
                            Write-Verbose('No passed FFT was found, assume it was the first FFT size: ' + ($lastRunFFT/1024))
                        }

                        # If the last passed FFT size is the max selected FFT size, start at the beginning
                        elseif ($lastPassedFFT -eq $maxFFTSize) {
                            $lastRunFFT = $minFFTSize
                            Write-Verbose('Last passed FFT size found: ' + ($lastPassedFFT/1024))
                            Write-Verbose('The last passed FFT size is the max selected FFT size, use the min FFT size: ' + ($lastRunFFT/1024))
                        }

                        # If the last passed FFT size is not the max size, check if the value doesn't show up at all in the FFT array
                        # In this case, we also assume that it successfully completed the max value and errored at the min FFT size
                        # Example: Smallest FFT max = 21, but the actual last size tested is 20K
                        elseif (!$FFTSizes[$cpuTestMode].Contains($lastPassedFFT)) {
                            $lastRunFFT = $minFFTSize
                            Write-Verbose('Last passed FFT size found: ' + ($lastPassedFFT/1024))
                            Write-Verbose('The last passed FFT size does not show up in the FFTSizes array, assume it''s the first FFT size: ' + ($lastRunFFT/1024))
                        }

                        # If it's not the max value and it does show up in the FFT array, select the next value
                        else {
                            $lastRunFFT = $FFTSizes[$cpuTestMode][$FFTSizes[$cpuTestMode].indexOf($lastPassedFFT)+1]
                            Write-Verbose('Last passed FFT size found: ' + ($lastPassedFFT/1024))
                            Write-Verbose('Last run FFT size assumed:  ' + ($lastRunFFT/1024))
                        }
                    }

                    # Educated guess
                    if ($lastRunFFT) {
                        Write-ColorText('ERROR: The error likely happened at FFT size ' + ($lastRunFFT/1024) + 'K') Magenta
                    }
                    else {
                        Write-ColorText('ERROR: No additional FFT size information found in the results.txt') Magenta
                    }

                    Write-Verbose('The last 5 entries in the results.txt:')
                    $index = $allLogEntries.Count - 5
                    $lastFiveRows | ForEach-Object {
                        Write-Verbose('- [Line ' + $index + '] ' + $_)
                        $index++
                    }

                    Write-Text('')
                }

                # Only Smallest, Small and Large FFT presets follow the order, so no real FFT size fail detection is possible due to randomization of the order by Prime95
                else {
                    $lastFiveRows     = $allLogEntries | Select-Object -Last 5
                    $lastPassedFFTArr = @($lastFiveRows | Where-Object {$_ -like '*passed*'})
                    $hasMatched       = $lastPassedFFTArr[$lastPassedFFTArr.Length-1] -match 'Self\-test (\d+)(K?) passed'

                    if ($hasMatched) {
                        if ($Matches[2] -eq 'K') {
                            $lastPassedFFT = [Int] $Matches[1] * 1024
                        }
                        else {
                            $lastPassedFFT = [Int] $Matches[1]
                        }
                    }
                    
                    if ($lastPassedFFT) {
                        Write-ColorText('ERROR: The last *passed* FFT size before the error was: ' + ($lastPassedFFT/1024) + 'K') Magenta 
                        Write-ColorText('ERROR: Unfortunately FFT size fail detection only works for Smallest, Small or Large FFT sizes.') Magenta 
                    }
                    else {
                        Write-ColorText('ERROR: No additional FFT size information found in the results.txt') Magenta
                    }

                    Write-Verbose('The max FFT size was outside of the range where it still follows a numerical order')
                    Write-Verbose('The selected max FFT size:         ' + ($maxFFTSize/1024))
                    Write-Verbose('The limit for the numerical order: ' + ($FFTMinMaxValues['SSE']['LARGE']['Max']/1024))


                    Write-Verbose('The last 5 entries in the results.txt:')
                    $index = $allLogEntries.Count - 5                    
                    $lastFiveRows | ForEach-Object {
                        Write-Verbose('- [Line ' + $index + '] ' + $_)
                        $index++
                    }

                    Write-Text('')
                }
            }
        }


        # Aida64
        elseif ($isAida64) {
            Write-Verbose('The stress test program is Aida64, no detailed error detection available')
        }


        # y-Cruncher with logging wrapper
        elseif ($isYCruncherWithLogging) {
            Write-Verbose('y-Cruncher with logging wrapper enabled')

            # The messages y-Cruncher displays:
            # Exception Encountered: XYZ
            # 
            # <ERROR MESSAGE>
            # <May have multiple lines>
            # 
            # 
            # Error(s) encountered on logical core X
            # 
            # Failed  Test Speed <...>
            # Errors encountered. Stopping test...


            # Get the last 20 rows
            $lastTwentyRows = $allLogEntries | Select-Object -Last 20


            # Get the last test that was being run
            # We want the test that was started before the error message was thrown
            # The last entry may already be the next test that was started after the error happened

            # Look for the line the error message appears in
            $errorResults = $newLogEntries | Where-Object {$_.Line -match '.*error\(s\).*'} | Select-Object -Last 1
            
            if ($errorResults.Length -gt 0) {
                $lastLineEntry  = $lastTwentyRows | Select-String -Pattern $errorResults.Line -SimpleMatch | Select-Object -Property Line,LineNumber -First 1
                $lastLineNumber = $lastLineEntry.LineNumber
            }
            else {
                $lastLineNumber = 20
            }


            # Reduce the Last Twenty Rows up to this line
            $lastRowsUpToError = $lastTwentyRows | Select-Object -First $lastLineNumber

            # Now get the last started test
            $allLatestTestArr = @($lastRowsUpToError | Where-Object {$_ -like '*Running *'})
            $hasMatched       = $allLatestTestArr[$allLatestTestArr.Length-1] -match 'Running ([a-z0-9]+):'

            if ($hasMatched) {
                $lastRunTest = $Matches[1]
            }

            if ($lastRunTest) {
                Write-ColorText('ERROR: The last test being started was: ' + $lastRunTest) Magenta 
            }
            else {
                Write-ColorText('ERROR: No last test being started was found') Magenta
            }
            

            $exceptionEntry = $lastTwentyRows | Where-Object {$_ -match 'Exception Encountered'} | Select-Object -Last 1
            $hasMatched = $($lastTwentyRows | Out-String) | Where-Object {$_ -match "(?s)Exception Encountered.+`r`n`r`n(.+)`r`n`r`nError\(s\) encountered on logical core"}
            # Note: this needs double quotes to recognize the line breaks

            if ($hasMatched) {
                $lastErrorMessage = $Matches[1]
            }

            
            if ($exceptionEntry -or $lastErrorMessage) {
                Write-ColorText('ERROR: The error message:') Magenta

                if ($exceptionEntry) {
                    Write-ColorText($exceptionEntry) Yellow
                }
                    if ($lastErrorMessage) {
                    Write-ColorText($lastErrorMessage) Yellow
                }
            }
            else {
                Write-ColorText('ERROR: No error message was found') Magenta
            }


            Write-Verbose('The last 20 entries of the output:')
            $index = $allLogEntries.Count - 20
            $lastTwentyRows | ForEach-Object {
                Write-Verbose('- [Line ' + $index + '] ' + $_)
                $index++
            }

            Write-Text('')
        }

        # y-Cruncher
        elseif ($isYCruncher) {
            Write-Verbose('The stress test program is y-Cruncher, no detailed error detection available')
        }


        # Throw an error to let the caller know to close and possibily restart the stress test program
        # PROCESSMISSING
        # CALCULATIONERROR
        # CPULOAD
        if (!$errorType) {
            $errorType = 'UNKNOWN_STRESS_TEST_ERROR'
        }

        $exception = New-Object System.ApplicationException -ArgumentList ('StressTestError', $errorType)
        throw $exception
    }
}


<#
.DESCRIPTION
    Get the (new) entries from a log file and store them in a global variable
.PARAMETER
    [Void]
.OUTPUTS
    [Void]
    Sets global variables:
    - $previousFileSize
    - $lastFilePosition
    - $lineCounter
    - $allLogEntries
    - $newLogEntries
#>
function Get-NewLogfileEntries {
    $timestamp = Get-Date -format HH:mm:ss
    Write-Debug($timestamp + ' - Getting new log file entries')

    # Reset the newLogEntries array
    $Script:newLogEntries = [System.Collections.ArrayList]::new()

    # Try to get the results.txt log file
    $resultFileHandle = Get-Item -Path $stressTestLogFilePath -ErrorAction Ignore

    # No file, no check
    if (!$resultFileHandle) {
        Write-Debug('           The stress test log file doesn''t exist yet')
        return
    }

    # Only perform the check if the file size has increased
    # The size has increased, so something must have changed
    # It's either a new passed FFT entry, a [Timestamp], or an error
    if ($resultFileHandle.Length -le $previousFileSize) {
        Write-Debug('           No file size change for the log file')
        return
    }

    # Store the file size of the log file
    $Script:previousFileSize = $resultFileHandle.Length

    Write-Debug('           Getting new log entries starting at position ' + $lastFilePosition + ' / Line ' + $lineCounter)

    # Initialize the file stream
    $fileStream = [System.IO.FileStream]::new(`
        $stressTestLogFilePath,`
        [System.IO.FileMode]::Open,`                                        # Open the file
        [System.IO.FileAccess]::Read,`                                      # Open the file only for reading
        [System.IO.FileShare]::ReadWrite + [System.IO.FileShare]::Delete`   # Allow other processes to read, write and delete the file
    )

    # Initialize the stream reader that accesses the file stream
    $streamReader = [System.IO.StreamReader]::new($fileStream)

    # We may need to reset the buffer due to a bug:
    # http://geekninja.blogspot.com/2007/07/streamreader-annoying-design-decisions.html
    $streamReader.DiscardBufferedData()

    # Set the pointer to the last file position (offset, beginning)
    $null = $streamReader.BaseStream.Seek($lastFilePosition, [System.IO.SeekOrigin]::Begin)

    # Get all the new lines since the last check
    while ($streamReader.Peek() -gt -1) {
        $lineCounter++
        $line = $streamReader.ReadLine()

        $null = $Script:allLogEntries.Add($line)

        $null = $Script:newLogEntries.Add(@{
            LineNumber = $lineCounter
            Line       = $line
        })
    }

    # Store the current position as the new last position for the next iteration
    $Script:lastFilePosition = $streamReader.BaseStream.Position
    $Script:lineCounter      = $lineCounter

    # Close the file
    $streamReader.Close()

    Write-Debug('           The new log file entries:')
    $newLogEntries | ForEach-Object {
        Write-Debug('           - [Line ' + $_.LineNumber + '] ' + $_.Line)
    }

    Write-Debug('           New file position: ' + $lastFilePosition + ' / Line ' + $lineCounter)
}




<#
.DESCRIPTION
    The main functionality
#>
Write-Host('Starting the CoreCycler...')
Write-Host('Press CTRL+C to abort') -ForegroundColor Yellow


# We need the logs directory to exist
if ( !(Test-Path -Path $logFilePathAbsolute) ) {
    $null = New-Item $logFilePathAbsolute -Itemtype Directory
}



# Get the default and the user settings
# This is early because we want to be able to get the log level
Get-Settings


# Error Checks

# PowerShell version too low
# This is a neat flag
#requires -version 5.0

# The script doesn't work for Powershell version 6 and 7
# There are some missing cmdlets
if ($PSVersionTable.PSVersion.Major -gt 5) {
    Write-Host
    Write-Host 'FATAL ERROR: The PowerShell version is too _new_!' -ForegroundColor Red
    Write-Host 'PowerShell version 6 and above do not support the required functions inside this script!' -ForegroundColor Red
    Write-Host
    Write-Host 'Please run this script with PowerShell 5.1, which is included with Windows' -ForegroundColor Yellow
    
    Exit-WithFatalError
}


# Non-ANSI characters in the directory path may pose problems
Write-Debug('PSScriptRoot: ' + $root)

if ($root -match '[^\x00-\x7F]') {
    Write-Host
    Write-Host 'FATAL ERROR: The directory path contains non-ANSI characters!' -ForegroundColor Red
    Write-Host
    Write-Host 'Please run this script from a directory that only contains ANSI characters.' -ForegroundColor Yellow
    Write-Host '(for example D:\Overclock\CoreCycler\)' -ForegroundColor Yellow
    Write-Host
    Write-Host 'The current directory is:' -ForegroundColor Yellow
    Write-Host $root -ForegroundColor Yellow
    
    Exit-WithFatalError
}


# Check if .NET is installed
$hasDotNet3_5 = [Int](Get-ItemProperty 'HKLM:\Software\Microsoft\NET Framework Setup\NDP\v3.5' -ErrorAction Ignore).Install
$hasDotNet4_0 = [Int](Get-ItemProperty 'HKLM:\Software\Microsoft\NET Framework Setup\NDP\v4.0\Client' -ErrorAction Ignore).Install
$hasDotNet4_x = [Int](Get-ItemProperty 'HKLM:\Software\Microsoft\NET Framework Setup\NDP\v4\Full' -ErrorAction Ignore).Install

if (!$hasDotNet3_5 -and !$hasDotNet4_0 -and !$hasDotNet4_x) {
    Write-Host
    Write-Host 'FATAL ERROR: .NET could not be found or the version is too old!' -ForegroundColor Red
    Write-Host 'At least version 3.5 of .NET is required!' -ForegroundColor Red
    Write-Host
    Write-Host 'You can download the .NET Framework here:' -ForegroundColor Yellow
    Write-Host 'https://dotnet.microsoft.com/download/dotnet-framework' -ForegroundColor Cyan
    
    Exit-WithFatalError
}

# Clear the error variable, it may have been populated by the above calls
$Error.clear()


# Try top get the localized counter names
try {
    Write-Verbose('Trying to get the localized performance counter names')

    $counterNameIds = Get-PerformanceCounterIDs $englishCounterNames
    
    $englishCounterNames.GetEnumerator().ForEach({
        Write-Verbose(('ID of "' + $_ + '":').PadRight(43, ' ') + $( if ( $counterNameIds[$_] ) { $counterNameIds[$_] } else { 'NOT FOUND!' } ))
    })

    foreach ( $performanceCounterName in $englishCounterNames ) {
        if ( !$counterNameIds[$performanceCounterName] -or $counterNameIds[$performanceCounterName] -eq 0 ) {
            Throw 'Could not get the ID for the Performance Counter Name "' + $performanceCounterName + '" from the registry!'
        }

        Write-Debug('Getting the localized name for "' + $performanceCounterName + '" with ID "' + $counterNameIds[$performanceCounterName] + '"')
        $counterNames[$performanceCounterName] = Get-PerformanceCounterLocalName $counterNameIds[$performanceCounterName]
        Write-Verbose('The localized name for "' + $performanceCounterName + '":          ' + $counterNames[$performanceCounterName])
    }


    $counterNames['FullName']      = '\'  + $counterNames['Process'] + '(*)\' + $counterNames['ID Process']
    $counterNames['SearchString']  = '\\' + $counterNames['ID Process'] + '$'
    $counterNames['ReplaceString'] = '\'  + $counterNames['% Processor Time']

    Write-Verbose('FullName:                                  ' + $counterNames['FullName'])
    Write-Verbose('SearchString:                              ' + $counterNames['SearchString'])
    Write-Verbose('ReplaceString:                             ' + $counterNames['ReplaceString'])

    # Examples
    # English             German               Spanish                      French
    # -------             ------               -------                      ------
    # Process             Prozess              Proseco                      Processus
    # ID Process          Prozesskennung       Id. de proseco               ID de processus
    # % Processor Time    Prozessorzeit (%)    % de tiempo de procesador    % temps processeur
    
    
    # These are additional counters that may or may not be used in the future   
    #$counterNames['Processor Information' ]  = Get-PerformanceCounterLocalName $counterNameIds['Processor Information']
    #$counterNames['% Processor Performance'] = Get-PerformanceCounterLocalName $counterNameIds['% Processor Performance']
    #$counterNames['% Processor Utility']     = Get-PerformanceCounterLocalName $counterNameIds['% Processor Utility']
}
catch {
    Write-Host 'FATAL ERROR: Could not get the localized Performance Process Counter name!' -ForegroundColor Red
    Write-Host
    Write-Host 'You may need to re-enable the Performance Process Counter (PerfProc).' -ForegroundColor Red
    Write-Host 'Please see the "Troubleshooting / FAQ" section in the readme.txt.' -ForegroundColor Red
    Write-Host
    Write-Host 'The full thrown error message:' -ForegroundColor Yellow
    
    $Error


    # Get the content of the registry entry for the performance counters, both the English and the localized one
    $keyEnglish         = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Perflib\009'
    $allCountersEnglish = (Get-ItemProperty -Path $keyEnglish -Name Counter).Counter
    $numCountersEnglish = $allCountersEnglish.Count

    # The localized performance counters
    $keyCurrent         = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Perflib\CurrentLanguage'
    $allCountersCurrent = (Get-ItemProperty -Path $keyCurrent -Name Counter).Counter
    $numCountersCurrent = $allCountersCurrent.Count

    Write-Debug('The number of counters for English:         ' + $numCountersEnglish)
    Write-Debug('The number of counters for CurrentLanguage: ' + $numCountersCurrent)

    Write-Debug('')
    Write-Debug('English Counters:')
    Write-Debug('-------------------------------------------------------------------------')
    Write-Debug($allCountersEnglish)

    Write-Debug('')
    Write-Debug('CurrentLanguage Counters:')
    Write-Debug('-------------------------------------------------------------------------')
    Write-Debug($allCountersCurrent)

    Exit-WithFatalError
}


# Try to access the localized Performance Process Counters
# It may be disabled

# This is the original english call:
# Get-Counter "\Process(*)\ID Process" -ErrorAction Stop
# We're starting a background job so that the Get-Counter call is not cached, which causes problems later on
$counter = Start-Job -ScriptBlock { 
    $data = @($input)
    (Get-Counter $data.'FullName' -ErrorAction Ignore).CounterSamples
} -InputObject $counterNames | Wait-Job | Receive-Job


if (!$counter) {
    Write-Host
    Write-Host 'FATAL ERROR: Could not access the Windows Performance Process Counter!' -ForegroundColor Red
    Write-Host
    Write-Host 'You may need to re-enable the Performance Process Counter (PerfProc).' -ForegroundColor Red
    Write-Host 'Please see the "Troubleshooting / FAQ" section in the readme.txt.' -ForegroundColor Red
    Write-Host
    Write-Host 'The localized counter name that was tried to access was:' -ForegroundColor Yellow
    Write-Host ('"' + $counterNames['FullName'] + '"') -ForegroundColor Yellow

    Exit-WithFatalError
}


# Check if we can access Visual Basic
try {
    $null = [Microsoft.VisualBasic.Interaction] | Get-Member -static
}
catch {
    Write-ColorText('FATAL ERROR: Could not access [Microsoft.VisualBasic.Interaction]!') Red
    Write-ErrorText $Error
    Exit-WithFatalError
}




# Get the final stress test program file paths and command lines
foreach ($testProgram in $stressTestPrograms.GetEnumerator()) {
    $stressTestPrograms[$testProgram.Name]['absolutePath']        = $root + '\' + $testProgram.Value['processPath'] + '\'
    $stressTestPrograms[$testProgram.Name]['absoluteInstallPath'] = $root + '\' + $testProgram.Value['installPath'] + '\'
    $stressTestPrograms[$testProgram.Name]['fullPathToExe']       = $testProgram.Value['absolutePath'] + $testProgram.Value['processName']
    $stressTestPrograms[$testProgram.Name]['configFilePath']      = $testProgram.Value['absolutePath'] + $testProgram.Value['configName']

    # If we have a comma separated list, remove all spaces and transform to upper case
    $commandMode = (($settings[$testProgram.Name].mode -Split ',\s*') -Join ',').ToUpperInvariant()

    # Generate the command line
    $data = @{
        '%fileName%'       = $testProgram.Value['processName'] + '.' + $testProgram.Value['processNameExt']
        '%fullPathToExe%'  = $testProgram.Value['fullPathToExe'] + '.' + $testProgram.Value['processNameExt']
        '%mode%'           = $commandMode
        '%configFilePath%' = $testProgram.Value['configFilePath']
    }

    $command = $stressTestPrograms[$testProgram.Name]['command']

    # Special behaviour if the custom logging wrapper for y-Cruncher is activated
    if ($testProgram.Name -eq 'ycruncher' -and $isYCruncherWithLogging) {
        $stressTestPrograms['ycruncher']['fullPathToLoadExe'] = $testProgram.Value['absolutePath'] + $testProgram.Value['processNameForLoad']
        
        $command = $stressTestPrograms[$testProgram.Name]['commandWithLogging']

        $Script:stressTestLogFileName = 'yCruncher_' + $startDateTime + '_mode_' + $settings.mode + '.txt'
        $Script:stressTestLogFilePath = $logFilePathAbsolute + $stressTestLogFileName

        $data['%fileName%'] = ($testProgram.Value['processNameForLoad'] + '.' + $testProgram.Value['processNameExt'])
        $data.add('%fullPathToLoadExe%', $testProgram.Value['fullPathToLoadExe'] + '.' + $testProgram.Value['processNameExt'])
        $data.add('%helpersPath%', $helpersPathAbsolute)
        $data.add('%logFilePath%', $stressTestLogFilePath)
    }

    foreach ($key in $data.Keys) {
        $command = $command.replace($key, $data.$key)
    }

    $stressTestPrograms[$testProgram.Name]['command'] = $command
}


# The name of the selected stress test program
$selectedStressTestProgram = $stressTestPrograms[$settings.General.stressTestProgram]['displayName']

# Set the correct process name
$processName = $stressTestPrograms[$settings.General.stressTestProgram]['processNameForLoad']


# The expected CPU usage for the running stress test process
# The selected number of threads should be at 100%, so e.g. for 1 thread out of 24 threads this is 100/24*1= 4.17%
# Used to determine if the stress test is still running or has thrown an error
# For one thread
$expectedUsagePerCore = (100 / $numLogicalCores)

# For the selected number of threads
$expectedUsageTotal = [Math]::Round($expectedUsagePerCore * $settings.General.numberOfThreads, 2)


# The minimum CPU usage for the stress test program, below which it should be treated as an error
# We need to account for the number of threads
# 100/32=   3,125% for 1 thread out of 32 threads
# 100/32*2= 6,250% for 2 threads out of 32 threads
# 100/24=   4,167% for 1 thread out of 24 threads
# 100/24*2= 8,334% for 2 threads out of 24 threads
# 100/12=   8,334% for 1 thread out of 12 threads
# 100/12*2= 16,67% for 2 threads out of 12 threads
# Use either 1.0% as the lower limit or the total expected usage - the expected usage per core if one thread failed
$minProcessUsage = [Math]::Max(1.0, [Math]::Round($expectedUsageTotal - $expectedUsagePerCore, 2))


# Store all the cores that have thrown an error in the stress test
# These cores will be skipped on the next iteration
[Int[]] $coresWithError = @()


# Count the number of errors for each cores if the skipCoreOnError setting is 0
$coresWithErrorsCounter = @{}

for ($i = 0; $i -lt $numPhysCores; $i++) {
    $coresWithErrorsCounter[$i] = 0
}


# The runtime per core
$runtimePerCore = $settings.General.runtimePerCore

# It may be set to "auto"
if ($settings.General.runtimePerCore.ToString().ToLowerInvariant() -eq 'auto') {
    # For Prime95, we're setting the runtimePerCore to 24 hours as a temporary value
    # For Aida64 and y-Cruncher, we're using 10 minutes
    if ($isPrime95) {
        $runtimePerCore = 24 * 60 * 60  # 24 hours as a temporary value
        $useAutomaticRuntimePerCore = $true
    }
    elseif ($isAida64) {
        $runtimePerCore = 10 * 60
    }
    elseif ($isYCruncherWithLogging) {
        $runtimePerCore = 24 * 60 * 60  # 24 hours as a temporary value
        $useAutomaticRuntimePerCore = $true
    }
    # For y-Cruncher without logging, try to estimate the duration
    elseif ($isYCruncher) {
        # Selected tests * duration of test + time in suspension + buffer
        $runtimePerCore = Get-EstimatedYCruncherRuntimePerCore
    }
}


# Calculate the amount of interval checks for the CPU power check
# Note: we cannot calculate this when the runtimePerCore is set to "auto"
if ($tickInterval -ge 1) {

    # We need a special treatment for a custom delayFirstErrorCheck value
    if ($delayFirstErrorCheck) {
        $cpuCheckIterations = [Math]::Floor(($runtimePerCore - $delayFirstErrorCheck) / $tickInterval)
    }
    else {
        $cpuCheckIterations = [Math]::Floor($runtimePerCore / $tickInterval)
    }
}


if ($delayFirstErrorCheck) {
    $runtimeRemaining = $runtimePerCore - $delayFirstErrorCheck - ($cpuCheckIterations * $tickInterval)
}
else {
    $runtimeRemaining = $runtimePerCore - ($cpuCheckIterations * $tickInterval)
}


# Get the actual core test mode
$coreTestOrderMode = $settings.General.coreTestOrder

# If set to default, switch between alternate for more than 8 cores and random for up to 8 cores
if ($settings.General.coreTestOrder -eq 'default') {
    if ($numPhysCores -gt 8) {
        $coreTestOrderMode = 'alternate'
    }
    else {
        $coreTestOrderMode = 'random'
    }
}

# If we find only numbers (and a comma), transform it into an array
elseif ($settings.General.coreTestOrder -match '\d+') {
    $coreTestOrderMode = 'custom'

    $settings.General.coreTestOrder -split ',\s*' | ForEach-Object {
        if ($_ -match '^\d+$') {
            $coreTestOrderCustom += [Int] $_
        }
    }
}


# Wrap the main functionality in a try {} block, so that the finally {} block is executed even if CTRL+C is pressed
try {
    # Prevent sleep while the script is running (but allow the monitor to turn off)
    [Windows.PowerUtil]::StayAwake($true, $false, 'CoreCycler is currently running.')


    # Check if the stress test process is already running
    $stressTestProcess = Get-Process $processName -ErrorAction Ignore

    # Some programs share the same process for stress testing and for displaying the main window, and some not
    if ($stressTestProgramsWithSameProcess -contains $settings.General.stressTestProgram) {
        $windowProcess = $stressTestProcess
    }
    else {
        $windowProcess = Get-Process $stressTestPrograms[$settings.General.stressTestProgram]['processName'] -ErrorAction Ignore
    }


    # Close all existing instances of the stress test program and start a new one with our config
    if ($stressTestProcess -or $windowProcess) {
        Write-Verbose('There already exists an instance of ' + $selectedStressTestProgram + ', trying to close it')

        if ($windowProcess) {
            Write-Verbose('Window Process ID: ' + $windowProcess.Id + ' - ProcessName: ' + $windowProcess.ProcessName)
        }
        if ($stressTestProcess) {
            Write-Verbose('Stress Test ID: ' + $stressTestProcess.Id + ' - ProcessName: ' + $stressTestProcess.ProcessName)
        }

        Close-StressTestProgram
    }


    # Create the required config files for the stress test program
    Initialize-StressTestProgram


    # Get the current datetime
    $timestamp = Get-Date -format 'yyyy-MM-dd HH:mm:ss'


    # Start messages
    $headline     = ' CoreCycler v' + $version + ' started at ' + $timestamp + ' '
    $padding      = 80 - $headline.Length
    $paddingLeft  = [Math]::Ceiling($padding / 2)
    $paddingRight = [Math]::Floor($padding / 2)

    # Start messages
    Write-ColorText('--------------------------------------------------------------------------------') Green
    Write-ColorText(''.PadLeft($paddingLeft, '-') + $headline + ''.PadRight($paddingRight, '-')) Green
    Write-ColorText('--------------------------------------------------------------------------------') Green

    # Log Level
    $logLevelText = @(
        'No additional output'
        'Writing verbose messages to log file'
        'Writing debug messages to log file'
        'Displaying verbose messages in terminal'
        'Displaying debug messages in terminal'
    )

    $logLevel = [Math]::Min([Math]::Max(0, $settings.Logging.logLevel), 4)

    Write-ColorText('Log Level set to: ..................... ' + $logLevel + ' [' + $logLevelText[$logLevel] + ']') Cyan

    # Display some initial information
    Write-ColorText('Stress test program: .................. ' + $selectedStressTestProgram.ToUpperInvariant()) Cyan
    Write-ColorText('Selected test mode: ................... ' + $settings.mode.ToUpperInvariant()) Cyan
    Write-ColorText('Logical/Physical cores: ............... ' + $numLogicalCores + ' logical / ' + $numPhysCores + ' physical cores') Cyan
    Write-ColorText('Hyperthreading / SMT is: .............. ' + ($(if ($isHyperthreadingEnabled) { 'ON' } else { 'OFF' }))) Cyan
    Write-ColorText('Selected number of threads: ........... ' + $settings.General.numberOfThreads) Cyan
    
    if ($settings.General.numberOfThreads -eq 1) {
        Write-ColorText('Assign both cores to stress thread: ... ' + ($(if ($settings.General.assignBothVirtualCoresForSingleThread) { 'ON' } else { 'OFF' }))) Cyan
    }

    Write-ColorText('Runtime per core: ..................... ' + (Get-FormattedRuntimePerCoreString $settings.General.runtimePerCore).ToUpperInvariant()) Cyan
    Write-ColorText('Suspend periodically: ................. ' + ($(if ($settings.General.suspendPeriodically) { 'ENABLED' } else { 'DISABLED' }))) Cyan
    Write-ColorText('Restart for each core: ................ ' + ($(if ($settings.General.restartTestProgramForEachCore) { 'ON' } else { 'OFF' }))) Cyan
    Write-ColorText('Test order of cores: .................. ' + $settings.General.coreTestOrder.ToUpperInvariant() + $(if ($settings.General.coreTestOrder.ToLowerInvariant() -eq 'default') {' (' + $coreTestOrderMode.ToUpperInvariant() + ')'})) Cyan
    Write-ColorText('Number of iterations: ................. ' + $settings.General.maxIterations) Cyan

    # Print a message if we're ignoring certain cores
    if ($settings.General.coresToIgnore.Length -gt 0) {
        $coresToIgnoreString = (($settings.General.coresToIgnore | Sort-Object) -Join ', ')
        Write-ColorText('Ignored cores: ........................ ' + $coresToIgnoreString) Cyan
        Write-ColorText('--------------------------------------------------------------------------------') Cyan
    }

    if ($settings.mode -eq 'CUSTOM') {
        Write-ColorText('') Cyan
        Write-ColorText('Custom settings:') Cyan
        Write-ColorText('--------------------------------------------------------------------------------') Cyan
        Write-ColorText('CpuSupportsAVX    = ' + $settings.Custom.CpuSupportsAVX) Cyan
        Write-ColorText('CpuSupportsAVX2   = ' + $settings.Custom.CpuSupportsAVX2) Cyan
        Write-ColorText('CpuSupportsFMA3   = ' + $settings.Custom.CpuSupportsFMA3) Cyan
        Write-ColorText('CpuSupportsAVX512 = ' + $settings.Custom.CpuSupportsAVX512) Cyan
        Write-ColorText('MinTortureFFT     = ' + $settings.Custom.MinTortureFFT) Cyan
        Write-ColorText('MaxTortureFFT     = ' + $settings.Custom.MaxTortureFFT) Cyan
        Write-ColorText('TortureMem        = ' + $settings.Custom.TortureMem) Cyan
        Write-ColorText('TortureTime       = ' + $settings.Custom.TortureTime) Cyan
    }
    else {
        if ($isPrime95) {
            Write-ColorText('Selected FFT size: .................... ' + $settings.Prime95.FFTSize.ToUpperInvariant() + ' (' + [Math]::Floor($minFFTSize/1024) + 'K - ' + [Math]::Ceiling($maxFFTSize/1024) + 'K)') Cyan
        }
        if ($isYCruncher) {
            Write-ColorText('Selected y-Cruncher tests: ............ ' + ($settings.yCruncher.tests -Join ', ')) Cyan
            Write-ColorText('Duration per test: .................... ' + ($settings.yCruncher.testDuration)) Cyan
        }
    }


    Write-ColorText('') Cyan
    Write-ColorText('--------------------------------------------------------------------------------') Cyan


    # Display the log file location(s)
    Write-ColorText('The log files for this run are stored in:') Cyan
    Write-ColorText($logFilePathAbsolute) Cyan
    Write-ColorText((' - CoreCycler:').PadRight(17, ' ') + $logFileName) Cyan

    if ($stressTestLogFileName) {
        Write-ColorText((' - ' + $stressTestPrograms[$settings.General.stressTestProgram]['displayName'] + ':').PadRight(17, ' ') + $stressTestLogFileName) Cyan
    }

    Write-ColorText('--------------------------------------------------------------------------------') Cyan
    Write-Text('')


    # Print a message if we have set some debug settings
    if (
            ($stressTestProgramPriority.ToLowerInvariant() -ne $stressTestProgramPriorityDefault.ToLowerInvariant()) `
        -or ($stressTestProgramWindowToForeground -ne $stressTestProgramWindowToForegroundDefault) `
        -or ($disableCpuUtilizationCheck -ne $disableCpuUtilizationCheckDefault) `
        -or ($enableCpuFrequencyCheck -ne $enableCpuFrequencyCheckDefault) `
        -or ($tickInterval -ne $tickIntervalDefault) `
        -or ($delayFirstErrorCheck -ne $delayFirstErrorCheckDefault) `
        -or ($suspensionTime -ne $suspensionTimeDefault) `
    ) {
        $debugSettingsActive = $true
        Write-ColorText('--------------------------------------------------------------------------------') Magenta
        Write-ColorText('Enabled debug settings:') Magenta
    }

    if ($stressTestProgramPriority.ToLowerInvariant() -ne $stressTestProgramPriorityDefault.ToLowerInvariant()) {
        Write-ColorText('Stress test program priority: ......... ' + $stressTestProgramPriority) Magenta
    }
    if ($stressTestProgramWindowToForeground -ne $stressTestProgramWindowToForegroundDefault) {
        Write-ColorText('Stress test program to foreground: .... ' + ($(if ($stressTestProgramWindowToForeground) { 'TRUE' } else { 'FALSE' }))) Magenta
    }
    if ($disableCpuUtilizationCheck -ne $disableCpuUtilizationCheckDefault) {
        Write-ColorText('Disabled CPU utilization check: ....... ' + ($(if ($disableCpuUtilizationCheck) { 'TRUE' } else { 'FALSE' }))) Magenta
    }
    if ($enableCpuFrequencyCheck -ne $enableCpuFrequencyCheckDefault) {
        Write-ColorText('Enabled CPU frequency check: .......... ' + ($(if ($enableCpuFrequencyCheck) { 'TRUE' } else { 'FALSE' }))) Magenta
    }
    if ($tickInterval -ne $tickIntervalDefault) {
        Write-ColorText('Tick interval: ........................ ' + $tickInterval) Magenta
    }
    if ($delayFirstErrorCheck -ne $delayFirstErrorCheckDefault) {
        Write-ColorText('Delay first error check: .............. ' + $delayFirstErrorCheck) Magenta
    }
    if ($suspensionTime -ne $suspensionTimeDefault) {
        Write-ColorText('Suspension time: ...................... ' + $suspensionTime) Magenta
    }

    if ($debugSettingsActive) {
        Write-ColorText('--------------------------------------------------------------------------------') Magenta
        Write-Text('')
    }



    # Start the stress test program
    Start-StressTestProgram


    # Try to get the affinity of the stress test program process. If not found, abort
    try {
        $null = $stressTestProcess.ProcessorAffinity

        Write-Verbose('The current affinity of the process: ' + $stressTestProcess.ProcessorAffinity)
    }
    catch {
        Exit-WithFatalError('Process ' + $processName + ' not found!')
    }


    # If Aida64 was started, try to clear any error messages from previous runs
    if ($isAida64) {
        Write-Verbose('Trying to clear Aida64 error messages from previous runs')

        $initFunctions = [scriptblock]::Create(@"
            function Send-CommandToAida64 { ${function:Send-CommandToAida64} }
            function Write-Verbose { ${function:Write-Verbose} }
"@)

        $null = Start-Job -ScriptBlock {
            param(
                $SendMessageDefinition,
                $windowProcessMainWindowHandler,
                $settings,
                $logFileFullPath
            )

            Start-Sleep 3

            # Send the command a couple of times
            # Unfortunately we cannot get any Write-Verbose without adding a Wait-Job
            for ($i = 0; $i -lt 3; $i++) {
                Send-CommandToAida64 'dismiss'
                Start-Sleep 500
            }
        } -InitializationScript $initFunctions -ArgumentList $SendMessageDefinition, $windowProcessMainWindowHandler, $settings, $logFileFullPath
    }


    # All the cores in the system
    $allCores = @(0..($numPhysCores-1))
    $coresToTest = $allCores

    # If a custom test order was provided, override the available cores
    if ($coreTestOrderMode -eq 'custom') {
        $coresToTest = $coreTestOrderCustom
    }

    # Remove ignored cores
    $coresToTest = $coresToTest | Where-Object {$_ -notin $settings.General.coresToIgnore}

    Write-Verbose('All cores that could be tested: ' + ($allCores -Join ', '))
    Write-Verbose('The preliminary test order:     ' + ($coresToTest -Join ', '))


    # Start with the CPU test
    # Repeat the whole check $settings.General.maxIterations times
    for ($iteration = 1; $iteration -le $settings.General.maxIterations; $iteration++) {
        $timestamp = Get-Date -format HH:mm:ss


        # Define the available cores
        $coreTestOrderArray = $coresToTest
        $halfCores          = $numPhysCores / 2
        $numAvailableCores  = $coreTestOrderArray.Length
        $previousCoreNumber = $null


        # Check if all of the cores have thrown an error, and if so, abort
        # Only if the skipCoreOnError setting is set
        if ($settings.General.skipCoreOnError -and $coresWithError.Length -eq ($coreTestOrderArray | Sort-Object | Get-Unique).Length) {
            # Also close the stress test program process to not let it run unnecessarily
            Close-StressTestProgram
            
            Write-ColorText($timestamp + ' - All Cores have thrown an error, aborting!') Yellow
            Exit-Script
        }


        Write-ColorText('') Yellow
        Write-ColorText($timestamp + ' - Iteration ' + $iteration) Yellow
        Write-ColorText('----------------------------------') Yellow


        # Build the available cores array for the various core test orders
        # We're leaving it in this loop because for random we want a different order on each iteration
        # and I like to have it all in one place instead of scattered around different places
        if ($coreTestOrderMode -eq 'alternate') {
            Write-Verbose('Alternating test order selected, building the test array...')

            # Start fresh
            $coreTestOrderArray = @()

            # 0, $halfCores, 0+1, $halfCores+1, ...
            # TODO: Maybe find a better way to handle ignored cores
            for ($i = 0; $i -lt $numPhysCores; $i++) {
                $currentCoreNumber = 0

                if ($null -ne $previousCoreNumber) {
                    if ($previousCoreNumber -lt $halfCores) {
                        $currentCoreNumber = [Int] ($previousCoreNumber + $halfCores)
                    }
                    else {
                        $currentCoreNumber = [Int] ($previousCoreNumber - $halfCores + 1)
                    }
                }

                $previousCoreNumber = $currentCoreNumber

                
                if (!$settings.General.coresToIgnore.Contains($currentCoreNumber)) {
                    $coreTestOrderArray += $currentCoreNumber
                }
            }
        }

        # Randomized
        elseif ($coreTestOrderMode -eq 'random') {
            Write-Verbose('Random test order selected, building the test array...')
            $coreTestOrderArray = $coreTestOrderArray | Sort-Object { Get-Random }
        }

        # Custom
        elseif ($coreTestOrderMode -eq 'custom') {
            Write-Verbose('Custom test order selected, keeping the test array...')
            # This was set above already, no need to change it
            # It also already doesn't include the ignored cores
        }

        # Sequential, do nothing
        else {
            Write-Verbose('Sequential test order selected, keeping the test array...')
            # This was set above already, no need to change it
            # It also already doesn't include the ignored cores
        }

        Write-Verbose('The final test order:  ' + ($coreTestOrderArray -Join ', '))


        # Iterate over each core
        # Named for loop
        :LoopCoreRunner for ($coreIndex = 0; $coreIndex -lt $numAvailableCores; $coreIndex++) {
            $startDateThisCore  = (Get-Date)
            $endDateThisCore    = $startDateThisCore + (New-TimeSpan -Seconds $runtimePerCore)
            $timestamp          = $startDateThisCore.ToString('HH:mm:ss')
            $affinity           = [Int64] 0
            $actualCoreNumber   = [Int] $coreTestOrderArray[0]
            $cpuNumbersArray    = @()
            $allPassedFFTs      = [System.Collections.ArrayList]::new()
            $uniquePassedFFTs   = [System.Collections.ArrayList]::new()
            $allPassedTests     = [System.Collections.ArrayList]::new()
            $uniquePassedTests  = [System.Collections.ArrayList]::new()
            $proceedToNextCore  = $false
            $fftSizeOverflow    = $false

            Write-Verbose('Still available cores: ' + ($coreTestOrderArray -Join ', '))


            # If the number of threads is more than 1
            if ($settings.General.numberOfThreads -gt 1) {
                for ($currentThread = 0; $currentThread -lt $settings.General.numberOfThreads; $currentThread++) {
                    # We don't care about Hyperthreading / SMT here, it needs to be enabled for 2 threads
                    $cpuNumber        = ($actualCoreNumber * 2) + $currentThread
                    $cpuNumbersArray += $cpuNumber
                    $affinity        += [Int64] [Math]::Pow(2, $cpuNumber)
                }
            }

            # Only one thread
            else {
                # assignBothVirtualCoresForSingleThread is enabled, we want to use both virtual cores, but with only one thread
                # The load should bounce back and forth between the two cores this way
                # Hyperthreading needs to be enabled for this
                if ($settings.General.assignBothVirtualCoresForSingleThread -and $isHyperthreadingEnabled) {
                    Write-Verbose('assignBothVirtualCoresForSingleThread is enabled, choosing both virtual cores for the affinity')
                    for ($currentThread = 0; $currentThread -lt 2; $currentThread++) {
                        $cpuNumber        = ($actualCoreNumber * 2) + $currentThread
                        $cpuNumbersArray += $cpuNumber
                        $affinity        += [Int64] [Math]::Pow(2, $cpuNumber)
                    }
                }

                # Setting not active, only one core for the load thread
                else {
                    # If Hyperthreading / SMT is enabled, the tested CPU number is 0, 2, 4, etc
                    # Otherwise, it's the same value
                    $cpuNumber        = $actualCoreNumber * (1 + [Int] $isHyperthreadingEnabled)
                    $cpuNumbersArray += $cpuNumber
                    $affinity         = [Int64] [Math]::Pow(2, $cpuNumber)
                }
            }

            Write-Verbose('The selected core to test: ' + $actualCoreNumber)

            $cpuNumberString = (($cpuNumbersArray | Sort-Object) -Join ' and ')


            # Skip if this core is in the ignored cores array
            # Note: This shouldn't happen anymore, as we have removed the cores from the availableCores array
            if ($settings.General.coresToIgnore -contains $actualCoreNumber) {
                # Ignore it silently
                Write-Verbose('Core ' + $actualCoreNumber + ' (CPU ' + $cpuNumberString + ') is being ignored, skipping')

                # Remove this core from the array of still available cores
                $coreTestOrderArray = $coreTestOrderArray[1..$coreTestOrderArray.Length]
                continue
            }

            # Skip if this core is stored in the error core array and the flag is set
            if ($settings.General.skipCoreOnError -and $coresWithError -contains $actualCoreNumber) {
                Write-Text($timestamp + ' - Core ' + $actualCoreNumber + ' (CPU ' + $cpuNumberString + ') has previously thrown an error, skipping')

                # Remove this core from the array of still available cores
                $coreTestOrderArray = $coreTestOrderArray[1..$coreTestOrderArray.Length]
                continue
            }


            # Apparently Aida64 doesn't like having the affinity set to 1
            # Possible workaround: Set it to 2 instead
            # This also poses a problem when testing two threads on core 0, so we're skipping this core for the time being
            if ($isAida64 -and $affinity -eq 1) {
                Write-ColorText('           Notice!') Black Yellow

                # If Hyperthreading / SMT is enabled
                if ($isHyperthreadingEnabled) {
                    Write-ColorText('           Apparently Aida64 doesn''t like running the stress test on the first thread of Core 0.') Black Yellow
                    Write-ColorText('           Setting it to thread 2 of Core 0 instead (Core 0 CPU 1).') Black Yellow
                    
                    $affinity        = [Int64] 2
                    $cpuNumber       = 1
                    $cpuNumberString = 1
                }

                # For disabled Hyperthreading / SMT, there's not much we can do. So skipping it
                else {
                    Write-ColorText('           Apparently Aida64 doesn''t like running the stress test on Core 0 only.') Black Yellow
                    Write-ColorText('           Normally we''d fall back to thread 2 on Core 0, but since Hyperthreading / SMT is disabled, we cannot do this.') Black Yellow
                    Write-ColorText('           Therefore we''re skipping this core.') Black Yellow

                    Write-Verbose('Skipping this core due to Aida64 not running correctly on Core 0 CPU 0 and Hyperthreading / SMT is disabled')

                    # Remove this core from the array of still available cores
                    $coreTestOrderArray = $coreTestOrderArray[1..$coreTestOrderArray.Length]
                    continue
                }
            }

            # Aida64 running on CPU 0 and CPU 1 (2 threads)
            elseif ($isAida64 -and $affinity -eq 3) {
                Write-ColorText('           Notice!') Black Yellow
                Write-ColorText('           Apparently Aida64 doesn''t like running the stress test on the first thread of Core 0.') Black Yellow
                Write-ColorText('           So you might see an error due to decreased CPU usage.') Black Yellow

                # TODO?
                #$affinity = 
            }
            

            # If $settings.General.restartTestProgramForEachCore is set, restart the stress test program for each core
            if ($settings.General.restartTestProgramForEachCore -and ($iteration -gt 1 -or $coreTestOrderArray.Length -lt $coresToTest.Length)) {
                Write-Verbose('restartTestProgramForEachCore is set, restarting the test program...')

                # Set the flag to only stop the stress test program if possible
                Close-StressTestProgram $true

                # If the delayBetweenCores setting is set, wait for the defined amount
                if ($settings.General.delayBetweenCores -gt 0) {
                    Write-Text('           Idling for ' + $settings.General.delayBetweenCores + ' seconds before proceeding to the next core...')

                    # Also adjust the expected end time for this delay
                    $endDateThisCore += New-TimeSpan -Seconds $settings.General.delayBetweenCores

                    Start-Sleep -Seconds $settings.General.delayBetweenCores
                }

                # Set the flag to only start the stress test program if possible
                Start-StressTestProgram $true
            }


            # Remove this core from the array of still available cores
            $coreTestOrderArray = $coreTestOrderArray[1..$coreTestOrderArray.Length]
            
           
            # This core has not thrown an error yet, run the test
            $timestamp = (Get-Date).ToString('HH:mm:ss')
            Write-Text($timestamp + ' - Set to Core ' + $actualCoreNumber + ' (CPU ' + $cpuNumberString + ')')
            
            # Set the affinity to a specific core
            try {
                Write-Verbose('Setting the affinity to ' + $affinity)

                $stressTestProcess.ProcessorAffinity = $affinity
            }
            catch {
                # Apparently setting the affinity can fail on the first try, so make another attempt
                Write-Verbose('Setting the affinity has failed, trying again...')
                Start-Sleep -Milliseconds 300

                try {
                    $stressTestProcess.ProcessorAffinity = $affinity
                }
                catch {
                    Close-StressTestProgram
                    Exit-WithFatalError('Could not set the affinity to Core ' + $actualCoreNumber + ' (CPU ' + $cpuNumberString + ')!')                
                }
            }

            # Check if the affinity is correct
            $checkingAffinity = $stressTestProcess.ProcessorAffinity

            if ($checkingAffinity -ne $affinity) {
                Write-Verbose('The affinity could NOT be set correctly!')
                Write-Verbose(' - affinity trying to set: ' + $affinity)
                Write-Verbose(' - actual affinity:        ' + $checkingAffinity)

                Exit-WithFatalError('The affinity could not be set correctly!')
            }


            Write-Verbose('Successfully set the affinity to ' + $affinity)

            # Change the title
            $host.ui.RawUI.WindowTitle = 'CoreCycler: Core ' + $actualCoreNumber


            # Set the process priority
            try {
                # PriorityClass values:
                # Idle
                # BelowNormal
                # Normal
                # AboveNormal
                # High
                # RealTime
                # $stressTestProcess.PriorityClass = 'High'
                # $stressTestProcess.PriorityClass = 'Idle'
                $stressTestProcess.PriorityClass = $stressTestProgramPriority

                # There's also a "SetPriority" property, which seems to be a WMI only property
                # Possible values:
                #    64 - Low
                # 16384 - Below normal
                #    32 - Normal
                # 32768 - Above normal
                #   128 - High
                #   256 - Realtime
                #
                # Return codes:
                #  0  - Successful completion 
                #  2  - Access denied 
                #  3  - Insufficient privilege 
                #  8  - Unknown failure 
                #  9  - Path not found 
                # 21  - Invalid parameter 
                # 22+ - Other

                # Get-CimInstance -ClassName win32_process -Filter 'Name="prime95.exe"'
                # $wmiStressTestProcess = Get-CimInstance -ClassName win32_process -Filter ('Handle="' + $stressTestProcess.Id + '"')
                # $setPriority = $wmiStressTestProcess.SetPriority(128)
                # $setPriority.ReturnValue
            }
            catch {
                Close-StressTestProgram
                Exit-WithFatalError('Could not set the priority of the stress test process!')
            }

            # If this core is stored in the error core array and the skipCoreOnError setting is not set, display the amount of errors
            if (!$settings.General.skipCoreOnError -and $coresWithError -contains $actualCoreNumber) {
                $text  = '           Note: This core has previously thrown ' + $coresWithErrorsCounter[$actualCoreNumber] + ' error'
                $text += $(if ($coresWithErrorsCounter[$actualCoreNumber] -gt 1) {'s'})
                
                Write-Text($text)
            }

            if ($useAutomaticRuntimePerCore) {
                if ($isPrime95) {
                    Write-Text('           Running until all FFT sizes have been tested...')
                }
                elseif ($isYCruncherWithLogging) {
                    $estimatedRuntime = Get-EstimatedYCruncherRuntimePerCore
                    $formattedEstimatedTime = Get-FormattedRuntimePerCoreString $estimatedRuntime
                    Write-Text('           Running until all selected tests have been completed (around ' + $formattedEstimatedTime + ')...')
                }
            }
            else {
                Write-Text('           Running for ' + (Get-FormattedRuntimePerCoreString $settings.General.runtimePerCore) + '...')
            }


            # Make a check each x seconds
            # - to check the CPU power usage
            # - to check if all FFT sizes have passed
            # - to suspend and resume the stress test process
            for ($checkNumber = 1; $checkNumber -le $cpuCheckIterations; $checkNumber++) {
                $timestamp = Get-Date -format HH:mm:ss
                Write-Debug('')
                Write-Debug($timestamp + ' - Tick ' + $checkNumber + ' of max ' + $cpuCheckIterations)

                $nowDateTime = (Get-Date)
                $difference  = New-TimeSpan -Start $nowDateTime -End $endDateThisCore

                Write-Debug('           Remaining max runtime: ' + [Math]::Round($difference.TotalSeconds) + 's')

                # Make this the last iteration if the remaining time is close enough
                # Also reduce the sleep time here by 1 second, we add this back after suspending the stress test program
                if ($difference.TotalSeconds -le $tickInterval) {
                    $checkNumber = $cpuCheckIterations
                    $waitTime    = [Math]::Max(0, $difference.TotalSeconds - 2) # -2 instead of -1 due to the additional wait time after the suspension
                    Write-Debug('           The remaining run time (' + $waitTime + ') is less than the tick interval (' + $tickInterval + '), this will be the last interval')
                    Start-Sleep -Seconds $waitTime
                }
                else {
                    Start-Sleep -Seconds ($tickInterval - 1)
                }


                # Get the current CPU frequency if the setting to do so is enabled
                # According to some reports, this may interfere with Test-StressTestProgrammIsRunning, so it's disabled by default now
                if ($enableCpuFrequencyCheck) {
                    $currentCpuInfo = Get-CpuFrequency $cpuNumber
                    Write-Verbose('           ...current CPU frequency: ~' + $currentCpuInfo.CurrentFrequency + ' MHz (' + $currentCpuInfo.Percent + '%)')
                }


                # Suspend and resume the stress test
                if ($settings.General.suspendPeriodically) {
                    $timestamp = Get-Date -format HH:mm:ss
                    Write-Verbose($timestamp + ' - Suspending the stress test process for ' + $suspensionTime + ' milliseconds')
                    $suspended = Suspend-ProcessWithDebugMethod $stressTestProcess
                    Write-Debug('           Suspended: ' + $suspended)

                    Start-Sleep -Milliseconds $suspensionTime

                    Write-Verbose('           Resuming the stress test process')
                    $resumed = Resume-ProcessWithDebugMethod $stressTestProcess
                    Write-Debug('           Resumed: ' + $resumed)
                }

                # This is the additional sleep time after having suspended/resumed the stress test program
                # It's a failsafe for the CPU utilization check
                # We don't care if we're actually suspending or not
                Start-Sleep -Seconds 1


                if ($delayFirstErrorCheck -and $checkNumber -eq 1) {
                    $timestamp = Get-Date -format HH:mm:ss
                    Write-Debug('')
                    Write-Debug($timestamp + ' - delayFirstErrorCheck has been set to ' + $delayFirstErrorCheck + ', delaying...')
                    Start-Sleep -Seconds $delayFirstErrorCheck
                }


                # For Prime95, try to get the new log file entries
                # Also for y-Cruncher with the logging wrapper
                if ($isPrime95 -or $isYCruncherWithLogging) {
                    Get-NewLogfileEntries
                }
                
                # If the runtime per core is set to auto and we're running Prime95
                # We need to check if all the FFT sizes have been tested
                if ($useAutomaticRuntimePerCore -and $isPrime95) {
                    :LoopCheckForAutomaticRuntime while ($true) {
                        $timestamp = Get-Date -format HH:mm:ss
                        # deletevar? $proceed = $false
                        $foundFFTSizeLines = @()

                        Write-Debug($timestamp + ' - Automatic runtime per core selected')
                        
                        # Only perform the check if the file size has increased
                        # The size has increased, so something must have changed
                        # It's either a new passed FFT entry, a [Timestamp], or an error
                        if ($newLogEntries.Length -le 0) {
                            Write-Debug('           No new log file entries found')
                            break LoopCheckForAutomaticRuntime
                        }

                        # Check for an error, if we've found one, we don't even need to process any further
                        # Note: there is a potential to miss log entries this way
                        # However, since the script either stops at this point or the stress test program is restarted, we don't really need to worry about this
                        $errorResults = $newLogEntries | Where-Object {$_.Line -match '.*error.*'}

                        if ($errorResults) {
                            Write-Debug('           Found an error entry in the new log entries, proceed to the error check')
                            break LoopCheckForAutomaticRuntime
                        }


                        # Get only the passed FFTs lines
                        $lastPassedFFTSizeResults = $newLogEntries | Where-Object {$_.Line -match '.*passed.*'}


                        # No passed FFT sizes found
                        if (!$lastPassedFFTSizeResults) {
                            Write-Debug('           No passed FFT sizes found yet, assuming we''re at the very beginning of the test')
                            break LoopCheckForAutomaticRuntime
                        }


                        Write-Debug('           The last passed FFT result lines:')
                        $lastPassedFFTSizeResults | ForEach-Object {
                            Write-Debug('           - [Line ' + $_.LineNumber + '] ' + $_.Line)
                        }


                        # Check all the entries in the found FFT results
                        # There may have been some sort of hiccup in the result file generation or file check, where one FFT size is overlooked
                        # Start at the oldest line
                        foreach ($currentResultLineEntry in $lastPassedFFTSizeResults) {
                            # There's no previous entry, nothing to compare to
                            if (!$previousPassedFFTEntry) {
                                # Add it to the list whether it's a new FFT size or not, we're filtering later on for two threads
                                $foundFFTSizeLines += $currentResultLineEntry
                            }

                            # Not reached the line number of the last entry yet
                            elseif ($currentResultLineEntry.LineNumber -le $previousPassedFFTEntry.LineNumber) {
                                Write-Debug('           Line number of previous entry not reached yet, skipping (Line ' + $currentResultLineEntry.LineNumber + ' <= ' + $previousPassedFFTEntry.LineNumber + ')')
                                continue
                            }

                            # A new line number has been reached
                            elseif ($currentResultLineEntry.LineNumber -gt $previousPassedFFTEntry.LineNumber) {
                                # If it's the same FFT size on a new line 
                                # This could either be an expected double entry for 2 worker threads
                                # or a true back-to-back entry (or both)

                                # Add it to the list whether it's a new FFT size or not, we're filtering later on for two threads
                                $foundFFTSizeLines += $currentResultLineEntry
                            }
                        }


                        Write-Debug('           All found FFT size lines:')
                        $foundFFTSizeLines | ForEach-Object {
                            Write-Debug('           - [Line ' + $_.LineNumber + '] ' + $_.Line)
                        }
                        

                        for ($currentLineIndex = 0; $currentLineIndex -lt $foundFFTSizeLines.Length; $currentLineIndex++) {
                            $currentResultLineEntry = $foundFFTSizeLines[$currentLineIndex]
                            
                            # More recent Prime95 version add a "(thread x of y)" to the log output, which breaks the recognition
                            # Theoretically this would offer a new way to determine the failures, but it would require a larger rewrite
                            # So removing this is the lazy approach
                            $currentResultLineEntry.Line = $currentResultLineEntry.Line -replace ' \(thread \d+ of \d+\)', ''
                            
                            $insert = $false

                            Write-Debug('')
                            Write-Debug('Checking line ' + $currentResultLineEntry.LineNumber)

                            # One thread or two threads
                            if ($settings.General.numberOfThreads -eq 1) {
                                $insert = $true
                            }

                            # Two threads require a special treatment
                            elseif ($settings.General.numberOfThreads -gt 1) {
                                $numLinesWithSameFFTSize = 1

                                # Does this line also appear in the last line?
                                $curCheckIndex = $allFFTLogEntries.Count - 1

                                # For newer Prime95 versions, the lines do not match anymore
                                # Example:
                                # Self-test 4K (thread 2 of 2) passed!
                                # Self-test 4K (thread 1 of 2) passed!

                                while ($curCheckIndex -ge 0 -and $allFFTLogEntries[$curCheckIndex] -and $currentResultLineEntry.Line -eq $allFFTLogEntries[$curCheckIndex].Line) {
                                #while ($curCheckIndex -ge 0 -and $allFFTLogEntries[$curCheckIndex]) {
                                    #$curLineHasMatched       = $currentResultLineEntry.Line -match 'Self\-test (\d+)(K?) passed'
                                    #$curLineFFTSize          = if ($curLineHasMatched) { [Int] $Matches[1] }   # $Matches is a fixed variable name for -match
                                    
                                    #$previousLineHasMatched  = $allFFTLogEntries[$curCheckIndex].Line -match 'Self\-test (\d+)(K?) passed'
                                    #$previousLineFFTSize     = if ($previousLineHasMatched) { [Int] $Matches[1] }   # $Matches is a fixed variable name for -match

                                    #if ($curLineFFTSize -ne $previousLineFFTSize) {
                                    #    break
                                    #}

                                    Write-Debug('           curCheckIndex:      ' + $curCheckIndex)
                                    Write-Debug('           This line:          ' + $currentResultLineEntry.Line)
                                    Write-Debug('           curCheckIndex line: ' + $allFFTLogEntries[$curCheckIndex].Line)
                                    Write-Debug('           Increasing the numLinesWithSameFFTSize counter')

                                    $curCheckIndex--
                                    $numLinesWithSameFFTSize++
                                }

                                Write-Debug('           The number of lines with the same FFT size: ' + $numLinesWithSameFFTSize)

                                # If the number of same lines is uneven, we found the beginning of a pair
                                if ($numLinesWithSameFFTSize % 2 -ne 0) {
                                    # We're ignoring this line
                                    Write-Debug('           Found the beginning of a pair')
                                    Write-Debug('           - Ignoring this line')
                                    #$numLinesWithSameFFTSize++
                                }

                                # We've found a pair, insert this FFT size
                                else {
                                    Write-Debug('           Found a pair')
                                    Write-Debug('           - Inserting this FFT size')
                                    $insert = $true
                                }
                            }


                            # Store the entry itself
                            Write-Debug('           Line number of this entry:         ' + $currentResultLineEntry.LineNumber)
                            Write-Debug('           Line number of the previous entry: ' + $allFFTLogEntries[$allFFTLogEntries.Count-1].LineNumber)

                            if (
                                $allFFTLogEntries.Count -eq 0 -or `
                                ($allFFTLogEntries.Count -gt 0 -and $currentResultLineEntry.LineNumber -ne $allFFTLogEntries[$allFFTLogEntries.Count-1].LineNumber)`
                            ) {
                                Write-Debug('           + Adding this line to the allFFTLogEntries array')
                                $null = $allFFTLogEntries.Add($currentResultLineEntry)
                            }


                            # Process and insert the FFT size
                            # FFT sizes that are not divisible by 1024 will not have a "K" appended!
                            if ($insert) {
                                $hasMatched = $currentResultLineEntry.Line -match 'Self\-test (\d+)(K?) passed'

                                if ($hasMatched) {
                                    if ($Matches[2] -eq 'K') {
                                        $currentPassedFFTSize = [Int] $Matches[1] * 1024
                                    }
                                    else {
                                        $currentPassedFFTSize = [Int] $Matches[1]
                                    }
                                }
                                
                                Write-Debug('')
                                Write-Debug('           Checking Line ' + $currentResultLineEntry.LineNumber)
                                Write-Debug('           - The previous passed FFT size - old: ' + ($previousPassedFFTSize/1024) + 'K')
                                Write-Debug('           - The current passed FFT size  - new: ' + ($currentPassedFFTSize/1024) + 'K')

                                # Enter the last passed FFT sizes arrays, both all and unique
                                $null = $allPassedFFTs.Add($currentPassedFFTSize)

                                if (!($uniquePassedFFTs -contains $currentPassedFFTSize)) {
                                    $null = $uniquePassedFFTs.Add($currentPassedFFTSize)
                                }

                                
                                Write-Debug('           - All passed FFTs:')
                                Write-Debug('           - ' + ($allPassedFFTs -Join ', '))
                                Write-Debug('           - All unique passed FFTs:')
                                Write-Debug('           - ' + ($uniquePassedFFTs -Join ', '))

                                Write-Verbose($timestamp + ' - The last passed FFT size: ' + ($currentPassedFFTSize/1024) + 'K')
                                Write-Verbose('           The number of FFT sizes to test:        ' + $fftSubarray.Count)
                                Write-Verbose('           The number of FFT sizes already tested: ' + $uniquePassedFFTs.Count)

                                # Store the entries to be able to compare to the previous value
                                $previousPassedFFTEntry = $currentResultLineEntry
                                $previousPassedFFTSize  = $currentPassedFFTSize


                                if ($proceedToNextCore -and !$fftSizeOverflow) {
                                    Write-Debug('')
                                    Write-Debug('           We didn''t check the log file in time to switch to the next core before another FFT size was tested.')
                                    Write-Debug('           That''s nothing to worry about, it''s just a bit unfortunate, because the order of FFT sizes for the')
                                    Write-Debug('           next core is now slightly shifted.')

                                    $fftSizeOverflow = $true
                                }

                                # This check might come too late, and so we're testing more FFT sizes than necessary
                                # Unfortunate, but no way around this if we want to correctly test all FFT sizes on each core
                                if ($uniquePassedFFTs.Count -eq $fftSubarray.Count) {
                                    $proceedToNextCore = $true
                                }
                            }
                        }


                        # Continue to the next core if the flag was set
                        if ($proceedToNextCore) {
                            Write-Verbose('')
                            Write-Verbose('           The number of unique FFT sizes matches the number of FFT sizes for the preset!')
                            Write-Text('           All FFT sizes have been tested for this core, proceeding to the next one')

                            continue LoopCoreRunner
                        }

                        Write-Debug('')


                        # Break out of the while ($true) loop, we only want one iteration
                        break

                    }   # End :LoopCheckForAutomaticRuntime while ($true)
                }   # End if ($useAutomaticRuntimePerCore -and $isPrime95)

                # If the runtime per core is set to auto and we're running y-Cruncher with the logging functionality enabled
                # We need to check if all the selected tests have run
                # Note that the iterations in y-Cruncher may not reflect the iterations in CoreCycler if there has been an error in-between
                elseif ($useAutomaticRuntimePerCore -and $isYCruncherWithLogging) {
                    :LoopCheckForAutomaticRuntime while ($true) {
                        $timestamp = Get-Date -format HH:mm:ss
                        # deletevar? $proceed = $false
                        $foundPassedTestLines = @()

                        Write-Debug($timestamp + ' - Automatic runtime per core selected')
                        
                        # Only perform the check if the file size has increased
                        # The size has increased, so something must have changed
                        # It's either a new passed test entry, a new iteration, an error, or a restarted program
                        if ($newLogEntries.Length -le 0) {
                            Write-Debug('           No new log file entries found')
                            break LoopCheckForAutomaticRuntime
                        }


                        # Check for an error, if we've found one, we don't even need to process any further
                        # Note: there is a potential to miss log entries this way
                        # However, since the script either stops at this point or the stress test program is restarted, we don't really need to worry about this
                        $errorResults = $newLogEntries | Where-Object {$_.Line -match '.*error\(s\).*'} | Select-Object -Last 1

                        if ($errorResults) {
                            Write-Debug('           Found an error entry in the new log entries, proceed to the error check')
                            break LoopCheckForAutomaticRuntime
                        }


                        # Get only the passed test lines
                        # Note: the new entries do not have the "Running XYZ:" part, so the test itself does not even appear
                        # We need to get the "line" directly before to get the actual test
                        $lastPassedTestResults = $newLogEntries | Where-Object {$_.Line -match '.*Passed.*'}


                        # No passed tests found
                        if (!$lastPassedTestResults) {
                            Write-Debug('           No passed tests found yet, assuming we''re at the very beginning of the run')
                            break LoopCheckForAutomaticRuntime
                        }


                        Write-Debug('           The last passed test lines:')
                        $lastPassedTestResults | ForEach-Object {
                            Write-Debug('           - [Line ' + $_.LineNumber + '] ' + $_.Line)
                        }


                        # Check all the entries in the found test results
                        # There may have been some sort of hiccup in the result file generation or file check, where one test is overlooked
                        # Start at the oldest line
                        foreach ($currentResultLineEntry in $lastPassedTestResults) {
                            # There's no previous entry, nothing to compare to
                            if (!$previousPassedTestEntry) {
                                # Add it to the list whether it's a new test or not
                                $foundPassedTestLines += $currentResultLineEntry
                            }

                            # Not reached the line number of the last entry yet
                            elseif ($currentResultLineEntry.LineNumber -le $previousPassedTestEntry.LineNumber) {
                                Write-Debug('           Line number of previous entry not reached yet, skipping (Line ' + $currentResultLineEntry.LineNumber + ' <= ' + $previousPassedTestEntry.LineNumber + ')')
                                continue
                            }

                            # A new line number has been reached
                            elseif ($currentResultLineEntry.LineNumber -gt $previousPassedTestEntry.LineNumber) {
                                $foundPassedTestLines += $currentResultLineEntry
                            }
                        }


                        Write-Debug('           All found passed test lines:')
                        $foundPassedTestLines | ForEach-Object {
                            Write-Debug('           - [Line ' + $_.LineNumber + '] ' + $_.Line)
                        }
                        

                        for ($currentLineIndex = 0; $currentLineIndex -lt $foundPassedTestLines.Length; $currentLineIndex++) {
                            $currentResultLineEntry = $foundPassedTestLines[$currentLineIndex]
                            
                            Write-Debug('')
                            Write-Debug('           Checking line ' + $currentResultLineEntry.LineNumber)
                            Write-Debug('           ' + $currentResultLineEntry.Line)

                            # Store the entry itself
                            Write-Debug('           Line number of this entry:         ' + $currentResultLineEntry.LineNumber)
                            Write-Debug('           Line number of the previous entry: ' + $allTestLogEntries[$allTestLogEntries.Count-1].LineNumber)

                            if (
                                $allTestLogEntries.Count -eq 0 -or `
                                ($allTestLogEntries.Count -gt 0 -and $currentResultLineEntry.LineNumber -ne $allTestLogEntries[$allTestLogEntries.Count-1].LineNumber)`
                            ) {
                                Write-Debug('           + Adding this line to the allTestLogEntries array')
                                $null = $allTestLogEntries.Add($currentResultLineEntry)
                            }


                            # Process and insert the test
                            # Note: the new entries do not have the "Running XYZ:" part, so the test itself does not even appear
                            # We need to get the "line" directly before to get the actual test
                            # So this line looks like this:
                            # Passed  Test Time:  65.252 seconds  ( 1.088 minutes )
                            $foundTestLine = $null
                            $currentPassedTest = $null

                            # $hasMatched = $currentResultLineEntry.Line -match '(.*Passed.*)'
                            # 
                            # if ($hasMatched) {
                                # $currentPassedTestPartialLine = $Matches[1]
                            # }
                            # 
                            # Write-Debug('currentPassedTestPartialLine:')
                            # Write-Debug($currentPassedTestPartialLine)


                            Write-Debug('           Trying to get the passed test')
                            Write-Debug('           Looking for ->')
                            Write-Debug('           ' + $currentResultLineEntry.Line)

                            $hasMatched = $currentResultLineEntry.Line -match 'Running ([a-z0-9]+):.*'

                            if ($hasMatched) {
                                $currentPassedTest = $Matches[1]
                            }

                            # If the line itself doesn't include the test name, we now try to get the passed test from the last entry up
                            else {
                                Write-Debug('           Test not showing up in current line, searching the log entries for the passed test')

                                for ($x = $allLogEntries.Count-1; $x -ge 0; $x--) {
                                    Write-Debug('           >>> [' + $x + '] ' + $allLogEntries[$x])

                                    if ($allLogEntries[$x] -eq $currentResultLineEntry.Line) {
                                        if ($x -gt 0) {
                                            $foundTestLine = $allLogEntries[$x-1]
                                            break
                                        }
                                    }
                                }

                                Write-Debug('           Found line with test:')
                                Write-Debug('           ' + $foundTestLine)

                                $hasMatched = $foundTestLine -match 'Running ([a-z0-9]+):.*'
                                
                                if ($hasMatched) {
                                    $currentPassedTest = $Matches[1]
                                }
                            }


                            if (!$currentPassedTest) {
                                Write-Debug('           Couldn''t find the currently passed test, possible detection error?')
                                break LoopCheckForAutomaticRuntime
                            }

                           
                            Write-Debug('')
                            Write-Debug('           Checked Line ' + $currentResultLineEntry.LineNumber)
                            Write-Debug('           - The previous passed test - old: ' + $previousPassedTest)
                            Write-Debug('           - The current passed test  - new: ' + $currentPassedTest)

                            # Enter the last passed test arrays, both all and unique
                            $null = $allPassedTests.Add($currentPassedTest)

                            if (!($uniquePassedTests -contains $currentPassedTest)) {
                                $null = $uniquePassedTests.Add($currentPassedTest)
                            }

                            
                            Write-Debug('           - All passed tests:')
                            Write-Debug('           - ' + ($allPassedTests -Join ', '))
                            Write-Debug('           - All unique passed tests:')
                            Write-Debug('           - ' + ($uniquePassedTests -Join ', '))

                            Write-Verbose($timestamp + ' - The last passed test: ' + $currentPassedTest)
                            Write-Verbose('           The number of tests to run:      ' + $settings.yCruncher.tests.Count)
                            Write-Verbose('           The number of tests already run: ' + $uniquePassedTests.Count)

                            # Store the entries to be able to compare to the previous value
                            $previousPassedTestEntry = $currentResultLineEntry
                            $previousPassedTest      = $currentPassedTest


                            # This check might come too late, and so we're testing more tests than necessary
                            # Unfortunate, but no way around this if we want to correctly test all test sizes on each core
                            if ($uniquePassedTests.Count -eq $settings.yCruncher.tests.Count) {
                                $proceedToNextCore = $true
                            }
                        }


                        # Continue to the next core if the flag was set
                        if ($proceedToNextCore) {
                            Write-Verbose('')
                            Write-Verbose('           The number of unique test names matches the number of the selected test names!')
                            Write-Text('           All tests have been run for this core, proceeding to the next one')

                            continue LoopCoreRunner
                        }

                        Write-Debug('')


                        # Break out of the while ($true) loop, we only want one iteration
                        break
                    }   # End :LoopCheckForAutomaticRuntime while ($true)
                }   # End if ($useAutomaticRuntimePerCore -and $isYCruncherWithLogging)


                # Check if the process is still using enough CPU process power
                try {
                    Test-StressTestProgrammIsRunning $actualCoreNumber
                }
                
                # On error, the Prime95 process is not running anymore, so skip this core
                catch {
                    Write-Verbose('There has been some error in Test-StressTestProgrammIsRunning, checking (#1)')

                    # There is an error message
                    if ($_.Exception -and $_.Exception.Message -eq 'StressTestError') {
                        # If the stopOnError flag is set, stop at this point
                        # But leave the stress test program open if possible
                        if ($settings.General.stopOnError) {
                            Write-Text('')
                            Write-ColorText('Stopping the testing process because the "stopOnError" flag was set.') Yellow

                            # Display the path to the log file
                            if ($isPrime95) {
                                Write-Text('')
                                Write-ColorText('Prime95''s results log file can be found at:') Cyan
                                Write-ColorText($stressTestLogFilePath) Cyan
                            }
                            elseif ($isYCruncherWithLogging) {
                                Write-Text('')
                                Write-ColorText('y-Cruncher''s log file can be found at:') Cyan
                                Write-ColorText($stressTestLogFilePath) Cyan
                            }

                            # And the path to the CoreCycler the log file for this run
                            Write-Text('')
                            Write-ColorText('The path of the CoreCycler log file for this run is:') Cyan
                            Write-ColorText($logfileFullPath) Cyan
                            Write-Text('')
                            
                            Exit-Script
                        }

                        # y-Cruncher can keep on running if the log wrapper is enabled and restartTestProgramForEachCore is not set
                        # And the process is still running of course
                        elseif ($isYCruncherWithLogging -and !$settings.General.restartTestProgramForEachCore -and $_.Exception.InnerException.Message -ne 'PROCESSMISSING') {
                            Write-Verbose('Running y-Cruncher with the log wrapper and restartTestProgramForEachCore disabled')
                            Write-Verbose('Continue to the next core')
                        }

                        # Otherwise for Prime95 (and others), try to close and restart the stress test program process if it is still running
                        else {
                            Write-Verbose('Trying to close the stress test program to re-start it')
                            
                            # Set the flag to only stop the stress test program if possible
                            Close-StressTestProgram $true


                            # Try to restart the stress test program and continue with the next core
                            # Don't try to restart at this point if $settings.General.restartTestProgramForEachCore is set to 1
                            # This will be taken care of in another routine
                            if (!$settings.General.restartTestProgramForEachCore) {
                                Write-Verbose('restartTestProgramForEachCore is not set, restarting the test program right away')

                                $timestamp = Get-Date -format HH:mm:ss
                                Write-Text($timestamp + ' - Trying to restart ' + $selectedStressTestProgram)

                                # Start the stress test program again
                                # Set the flag to only start the stress test program if possible
                                Start-StressTestProgram $true
                            }
                        }
                    }   # End: if ($_.Exception -and $_.Exception.Message -eq 'StressTestError')

                    # Unknown error
                    else {
                        Write-ColorText('FATAL ERROR:') Red
                        Write-ErrorText $Error
                        Exit-WithFatalError
                    }


                    # Continue to the next core
                    continue LoopCoreRunner
                }   # End: catch
            }   # End: for ($checkNumber = 1; $checkNumber -le $cpuCheckIterations; $checkNumber++)
            



            # Wait for the remaining runtime
            Start-Sleep -Seconds $runtimeRemaining
            
            # One last check
            try {
                Write-Verbose('One last error check before finishing this core')

                # Give it half a second
                Start-Sleep -Milliseconds 500
                Test-StressTestProgrammIsRunning $actualCoreNumber
            }
            
            # On error, the Prime95 process is not running anymore, so skip this core
            catch {
                Write-Verbose('There has been some error in Test-StressTestProgrammIsRunning, checking (#2)')


                # There is an error message
                if ($_.Exception -and $_.Exception.Message -eq 'StressTestError') {
                    # Try to close the stress test program process if it is still running
                    Write-Verbose('Trying to close the stress test program to re-start it')
                    
                    # Set the flag to only stop the stress test program if possible
                    Close-StressTestProgram $true
                    

                    # If the stopOnError flag is set, stop at this point
                    if ($settings.General.stopOnError) {
                        Write-Text('')
                        Write-ColorText('Stopping the testing process because the "stopOnError" flag was set.') Yellow

                        if ($isPrime95) {
                            # Display the results.txt file name for Prime95 for this run
                            Write-Text('')
                            Write-ColorText('Prime95''s results log file can be found at:') Cyan
                            Write-ColorText($stressTestLogFilePath) Cyan
                        }

                        # And the name of the log file for this run
                        Write-Text('')
                        Write-ColorText('The path of the CoreCycler log file for this run is:') Cyan
                        Write-ColorText($logfileFullPath) Cyan
                        Write-Text('')
                        
                        Exit-Script
                    }


                    # Try to restart the stress test program and continue with the next core
                    # Don't try to restart at this point if $settings.General.restartTestProgramForEachCore is set to 1
                    # This will be taken care of in another routine
                    if (!$settings.General.restartTestProgramForEachCore) {
                        Write-Verbose('restartTestProgramForEachCore is not set, restarting the test program right away')

                        $timestamp = Get-Date -format HH:mm:ss
                        Write-Text($timestamp + ' - Trying to restart ' + $selectedStressTestProgram)

                        # Start the stress test program again
                        # Set the flag to only start the stress test program if possible
                        Start-StressTestProgram $true
                    }
                }

                # Unknown error
                else {
                    Write-ColorText('FATAL ERROR:') Red
                    Write-ErrorText $Error
                    Exit-WithFatalError
                }
            }   # End: catch

            $timestamp = (Get-Date).ToString('HH:mm:ss')
            Write-Text($timestamp + ' - Completed the test on Core ' + $actualCoreNumber + ' (CPU ' + $cpuNumberString + ')')
        }   # End: :LoopCoreRunner for ($coreIndex = 0; $coreIndex -lt $numAvailableCores; $coreIndex++)
        
        
        # Print out the cores that have thrown an error so far
        if ($coresWithError.Length -gt 0) {
            if ($settings.General.skipCoreOnError) {
                Write-ColorText('The following cores have thrown an error: ' + (($coresWithError | Sort-Object) -Join ', ')) Cyan
            }
            else {
                Write-ColorText('The following cores have thrown an error:') Cyan

                $coreWithTwoDigitsHasError = $false

                foreach ($entry in $coresWithErrorsCounter.GetEnumerator()) {
                    if ( $entry.Name -gt 9 -and $entry.Value -gt 0) {
                        $coreWithTwoDigitsHasError = $true
                        break
                    }
                }
                
                foreach ($entry in ($coresWithErrorsCounter.GetEnumerator() | Sort-Object Name)) {
                    # No error, skip
                    if ($entry.Value -lt 1) {
                        continue
                    }

                    $corePadding = $(if ($coreWithTwoDigitsHasError) {' '} else {''})
                    $coreText  = $(if ($entry.Name -lt 10) {$corePadding})
                    $coreText += $entry.Name.ToString()

                    $textErrors      = 'error'
                    $textIterations  = 'iteration'

                    $textErrors     += $(if ($entry.Value -gt 1) {'s'})
                    $textIterations += $(if ($iteration -gt 1) {'s'})

                    Write-ColorText('    - Core ' + $coreText + ': ' + $entry.Value.ToString() + ' ' + $textErrors + ' in ' + $iteration + ' ' + $textIterations) Cyan
                }
            }
        }

        Write-Verbose('----------------------------------')
        Write-Verbose('Iteration complete')
        Write-Verbose('----------------------------------')
    }   # End for ($iteration = 1; $iteration -le $settings.General.maxIterations; $iteration++)


    # The CoreCycler has finished
    $timestamp = Get-Date -format HH:mm:ss
    Write-ColorText($timestamp + ' - CoreCycler finished!') Green
    Close-StressTestProgram
    Exit-Script
}

# This should execute even if CTRL+C is pressed
# Although probably no output is generated for it anymore
# Maybe the user wants to check the stress test program output after terminating the script
finally {
    # Re-enable sleep
    [Windows.PowerUtil]::StayAwake($false)


    # Don't do anything after a fatal error
    if ($fatalError) {
        exit
    }

    # Exit-Script has been called (no CTRL+C)
    if ($scriptExit) {
        # Show the final summary
        Show-FinalSummary
        exit
    }


    # Below this point should be a regular end of the script or CTRL+C was pressed


    # Set the window title
    $host.UI.RawUI.WindowTitle = ('CoreCycler ' + $version + ' terminating')

    $timestamp = Get-Date -format HH:mm:ss
    $processCPUPercentage = 0
    
    Write-ColorText($timestamp + ' - Terminating the script...') Red

    # If the stress test program is still running and using enough CPU power, close it
    if ($processCounterPathTime) {
        $processCPUPercentage = [Math]::Round(((Get-Counter $processCounterPathTime -ErrorAction Ignore).CounterSamples.CookedValue) / $numLogicalCores, 2)
    }


    Write-Verbose('Checking CPU usage: ' + $processCPUPercentage + '%')

    # Close only if we're using still enough CPU power
    if ($processCPUPercentage -ge $minProcessUsage) {
        Write-Verbose('The stress test program is still using enough CPU power, so we can try to close it')
        Write-Text('           Trying to close the stress test program...')
        Close-StressTestProgram

        Write-ColorText('Please check if the selected stress test program "' + $selectedStressTestProgram + '" is still running!') Yellow
    }
    else {
        Write-ColorText('The stress test program seems to have stopped.') Yellow
        Write-ColorText('Not killing the process so you can check if there was some error.') Yellow

        Write-ColorText('Please make sure to close "' + $selectedStressTestProgram + '" after you checked it!') Yellow
    }

    Write-ColorText('Check for these processes:') Yellow
    Write-ColorText(' - ' + $stressTestPrograms[$settings.General.stressTestProgram]['processName'] + '.' + $stressTestPrograms[$settings.General.stressTestProgram]['processNameExt']) Cyan
    
    if ($stressTestPrograms[$settings.General.stressTestProgram]['processName'] -ne $stressTestPrograms[$settings.General.stressTestProgram]['processNameForLoad']) {
        Write-ColorText(' - ' + $stressTestPrograms[$settings.General.stressTestProgram]['processNameForLoad']) Cyan
    }


    # Show the final summary
    Show-FinalSummary
}


