<#
.SYNOPSIS
The script allows to run any application under active user session 
no matter under which session script runs itself.

.DESCRIPTION
Resilio Connect Agent runs as LOCAL SYSTEM or LOCAL SERVICE account
by default. While running as service grants Agent many advantages
there's one great disadvantage: all UI apps started by Agent are not
visible by end user. This happens due to fact that all services 
start under different user session.

This script allows to push desired application to user session which
is active at the moment (i.e. usually - visible to end user). If 
no active users are found, the script ends with error. If multiple
active sessions are available (Windows server platforms allow
multiple sessions), the script picks the first logged in session.

.PARAMETER AppPath
Full path to the app executable. The AppPath cannot be relative.

.PARAMETER AppCmd
Parameters to be passed to the executable

.PARAMETER WorkDir
Current working directory for the executable

.PARAMETER Wait
Set to force script to wait while required application exits. If
not set, the script starts application and exits immediately no
matter if app is still running or not

.EXAMPLE
start-process-under-logged-on-user.ps1 -AppPath C:\Windows\notepad.exe -Wait
Will start the notepad.exe and prevent script from exiting until end user closes notepad.exe
#>


Param(
	[Parameter(Mandatory=$true)]
	[string]$AppPath,
	[string]$AppCmd,
	[string]$WorkDir,
	[switch]$Wait
)


Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class ProcessExtensions
{
	private const int CREATE_UNICODE_ENVIRONMENT = 0x00000400;
	private const int CREATE_NO_WINDOW = 0x08000000;
	private const int CREATE_NEW_CONSOLE = 0x00000010;
	private const uint INVALID_SESSION_ID = 0xFFFFFFFF;
	private static readonly IntPtr WTS_CURRENT_SERVER_HANDLE = IntPtr.Zero;

	[DllImport("advapi32.dll", EntryPoint = "CreateProcessAsUser", SetLastError = true, CharSet = CharSet.Ansi, CallingConvention = CallingConvention.StdCall)]
	private static extern bool CreateProcessAsUser(IntPtr hToken, String lpApplicationName, String lpCommandLine, IntPtr lpProcessAttributes, IntPtr lpThreadAttributes,
		bool bInheritHandle, uint dwCreationFlags, IntPtr lpEnvironment, String lpCurrentDirectory, ref STARTUPINFO lpStartupInfo, out PROCESS_INFORMATION lpProcessInformation);
	[DllImport("advapi32.dll", EntryPoint = "DuplicateTokenEx")]
	private static extern bool DuplicateTokenEx( IntPtr ExistingTokenHandle, uint dwDesiredAccess, IntPtr lpThreadAttributes, int TokenType, int ImpersonationLevel, ref IntPtr DuplicateTokenHandle);
	[DllImport("userenv.dll", SetLastError = true)]
	private static extern bool CreateEnvironmentBlock(ref IntPtr lpEnvironment, IntPtr hToken, bool bInherit);
	[DllImport("userenv.dll", SetLastError = true)]
	[return: MarshalAs(UnmanagedType.Bool)]
	private static extern bool DestroyEnvironmentBlock(IntPtr lpEnvironment);
	[DllImport("kernel32.dll", SetLastError = true)]
	private static extern bool CloseHandle(IntPtr hSnapshot);
	[DllImport("kernel32.dll")]
	private static extern uint WTSGetActiveConsoleSessionId();
	[DllImport("Wtsapi32.dll")]
	private static extern uint WTSQueryUserToken(uint SessionId, ref IntPtr phToken);
	[DllImport("wtsapi32.dll", SetLastError = true)]
	private static extern int WTSEnumerateSessions(IntPtr hServer, int Reserved, int Version, ref IntPtr ppSessionInfo, ref int pCount);
	[DllImport("kernel32.dll", SetLastError = true)]
	private static extern bool GetExitCodeProcess(IntPtr hProcess, out uint lpExitCode);
	[DllImport("kernel32.dll", SetLastError=true)]
	private static extern UInt32 WaitForSingleObject(IntPtr hHandle, UInt32 dwMilliseconds);

	private enum WTS_CONNECTSTATE_CLASS
	{
		WTSActive,
		WTSConnected,
		WTSConnectQuery,
		WTSShadow,
		WTSDisconnected,
		WTSIdle,
		WTSListen,
		WTSReset,
		WTSDown,
		WTSInit
	}

	[StructLayout(LayoutKind.Sequential)]
	private struct PROCESS_INFORMATION
	{
		public IntPtr hProcess;
		public IntPtr hThread;
		public uint dwProcessId;
		public uint dwThreadId;
	}

	private enum SECURITY_IMPERSONATION_LEVEL
	{
		SecurityAnonymous = 0,
		SecurityIdentification = 1,
		SecurityImpersonation = 2,
		SecurityDelegation = 3,
	}

	[StructLayout(LayoutKind.Sequential)]
	private struct STARTUPINFO
	{
		public int cb;
		public String lpReserved;
		public String lpDesktop;
		public String lpTitle;
		public uint dwX;
		public uint dwY;
		public uint dwXSize;
		public uint dwYSize;
		public uint dwXCountChars;
		public uint dwYCountChars;
		public uint dwFillAttribute;
		public uint dwFlags;
		public short wShowWindow;
		public short cbReserved2;
		public IntPtr lpReserved2;
		public IntPtr hStdInput;
		public IntPtr hStdOutput;
		public IntPtr hStdError;
	}

	private enum TOKEN_TYPE
	{
		TokenPrimary = 1,
		TokenImpersonation = 2
	}

	[StructLayout(LayoutKind.Sequential)]
	private struct WTS_SESSION_INFO
	{
		public readonly UInt32 SessionID;
		[MarshalAs(UnmanagedType.LPStr)]
		public readonly String pWinStationName;
		public readonly WTS_CONNECTSTATE_CLASS State;
	}

	private static int GetSessionUserToken(ref IntPtr phUserToken)
	{
		IntPtr hImpersonationToken = IntPtr.Zero;
		UInt32 activeSessionId = INVALID_SESSION_ID;
		IntPtr pSessionInfo = IntPtr.Zero;
		int sessionCount = 0;

		if (WTSEnumerateSessions(IntPtr.Zero, 0, 1, ref pSessionInfo, ref sessionCount) != 0)
		{
			long arrayElementSize = Marshal.SizeOf(typeof(WTS_SESSION_INFO));
			IntPtr current = pSessionInfo;

			for (int i = 0; i < sessionCount; i++)
			{
				WTS_SESSION_INFO si = (WTS_SESSION_INFO)Marshal.PtrToStructure((IntPtr)current, typeof(WTS_SESSION_INFO));
				current = new IntPtr((long)current + arrayElementSize);

				if (si.State == WTS_CONNECTSTATE_CLASS.WTSActive)
				{
					activeSessionId = si.SessionID;
					break;
				}
			}
		}
		else
		{
			return Marshal.GetLastWin32Error();
		}

		if (activeSessionId == INVALID_SESSION_ID)
		{
			activeSessionId = WTSGetActiveConsoleSessionId();
		}

		if (WTSQueryUserToken(activeSessionId, ref hImpersonationToken) != 0)
		{
			try
			{
				if (!DuplicateTokenEx(hImpersonationToken, 0, IntPtr.Zero, (int)SECURITY_IMPERSONATION_LEVEL.SecurityImpersonation, (int)TOKEN_TYPE.TokenPrimary, ref phUserToken))
				{
					return Marshal.GetLastWin32Error();
				}
			}
			finally
			{
				CloseHandle(hImpersonationToken);
			}
		}
		else
		{
			return Marshal.GetLastWin32Error();
		}

		return 0;
	}

	public static void StartProcessAsCurrentUser(string appPath, string cmdLine, bool wait, ref uint exitCode, string workDir)
	{
		IntPtr hUserToken = IntPtr.Zero;
		STARTUPINFO startInfo = new STARTUPINFO();
		PROCESS_INFORMATION procInfo = new PROCESS_INFORMATION();
		IntPtr pEnv = IntPtr.Zero;

		startInfo.cb = Marshal.SizeOf(typeof(STARTUPINFO));

		try
		{
			exitCode = (uint)GetSessionUserToken(ref hUserToken);
			if (exitCode != 0)
			{
				throw new Exception(String.Format("StartProcessAsCurrentUser: GetSessionUserToken failed ({0})", exitCode));
			}

			uint dwCreationFlags = CREATE_UNICODE_ENVIRONMENT | CREATE_NEW_CONSOLE | CREATE_NO_WINDOW;
			startInfo.dwFlags = 0x00000001;
			startInfo.wShowWindow = 0;
			startInfo.lpDesktop = "winsta0\\default";

			if (!CreateEnvironmentBlock(ref pEnv, hUserToken, false))
			{
				exitCode = (uint)Marshal.GetLastWin32Error();
				throw new Exception("StartProcessAsCurrentUser: CreateEnvironmentBlock failed.");
			}

			if ((workDir != null) && (workDir.Length == 0))
			{
				workDir = null;
			}

			if (!CreateProcessAsUser(hUserToken, appPath, cmdLine, IntPtr.Zero, IntPtr.Zero, false, dwCreationFlags, pEnv, workDir, ref startInfo, out procInfo))
			{
				exitCode = (uint)Marshal.GetLastWin32Error();
				throw new Exception("StartProcessAsCurrentUser: CreateProcessAsUser failed.  Error Code -" + exitCode);
			}

			if (wait)
			{
				WaitForSingleObject(procInfo.hProcess, 0xFFFFFFFF);
				GetExitCodeProcess(procInfo.hProcess, out exitCode);
			}
		}
		finally
		{
			CloseHandle(hUserToken);
			if (pEnv != IntPtr.Zero)
			{
				DestroyEnvironmentBlock(pEnv);
			}
			CloseHandle(procInfo.hThread);
			CloseHandle(procInfo.hProcess);
		}
	}

}
"@

$powershellPath = "$([System.Environment]::SystemDirectory)\WindowsPowerShell\v1.0\powershell.exe"
$powershellCmd = "Start-Process '$AppPath' $(if($AppCmd){"-ArgumentList '$($AppCmd -replace "'", "''")'"}) $(if($Wait){"-Wait"})"
$powershellCmd = "-NoProfile -ExecutionPolicy bypass -EncodedCommand $([Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($powershellCmd)))"

$exitCode = 0
[ProcessExtensions]::StartProcessAsCurrentUser($powershellPath, $powershellCmd, $Wait, [ref]$exitCode, $WorkDir)
exit $exitCode
