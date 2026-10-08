param([uint32[]]$ProcessIds)
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class TestSessionAudio {
 [ComImport,Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class Enumerator {}
 [ComImport,Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface IDevices {
  [PreserveSig] int EnumAudioEndpoints(int flow,uint state,out IntPtr devices);
  [PreserveSig] int GetDefaultAudioEndpoint(int flow,int role,out IDevice device);
 }
 [ComImport,Guid("D666063F-1587-4E43-81F1-B948E807363F"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface IDevice {
  [PreserveSig] int Activate(ref Guid iid,uint context,IntPtr parameters,[MarshalAs(UnmanagedType.IUnknown)] out object instance);
 }
 [ComImport,Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface IManager {
  [PreserveSig] int GetAudioSessionControl(IntPtr session,uint flags,out IntPtr control);
  [PreserveSig] int GetSimpleAudioVolume(IntPtr session,uint flags,out IntPtr volume);
  [PreserveSig] int GetSessionEnumerator(out ISessions sessions);
 }
 [ComImport,Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface ISessions {
  [PreserveSig] int GetCount(out int count);
  [PreserveSig] int GetSession(int index,[MarshalAs(UnmanagedType.IUnknown)] out object control);
 }
 [ComImport,Guid("BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface IControl {
  [PreserveSig] int GetState(out int state);
  [PreserveSig] int GetDisplayName([MarshalAs(UnmanagedType.LPWStr)] out string name);
  [PreserveSig] int SetDisplayName([MarshalAs(UnmanagedType.LPWStr)] string name,ref Guid context);
  [PreserveSig] int GetIconPath([MarshalAs(UnmanagedType.LPWStr)] out string path);
  [PreserveSig] int SetIconPath([MarshalAs(UnmanagedType.LPWStr)] string path,ref Guid context);
  [PreserveSig] int GetGroupingParam(out Guid group);
  [PreserveSig] int SetGroupingParam(ref Guid group,ref Guid context);
  [PreserveSig] int RegisterAudioSessionNotification(IntPtr client);
  [PreserveSig] int UnregisterAudioSessionNotification(IntPtr client);
  [PreserveSig] int GetSessionIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string id);
  [PreserveSig] int GetSessionInstanceIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string id);
  [PreserveSig] int GetProcessId(out uint id);
 }
 [ComImport,Guid("87CE5498-68D6-44E5-9215-6DA47EF883D8"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)] interface IVolume {
  [PreserveSig] int SetMasterVolume(float volume,ref Guid context);
  [PreserveSig] int GetMasterVolume(out float volume);
  [PreserveSig] int SetMute([MarshalAs(UnmanagedType.Bool)] bool mute,ref Guid context);
  [PreserveSig] int GetMute([MarshalAs(UnmanagedType.Bool)] out bool mute);
 }
 public static string[] Silence(uint[] ids) {
  var results = new List<string>(); var wanted = new HashSet<uint>(ids);
  var enumerator = (IDevices)new Enumerator();
  for (int role=0;role<3;role++) {
   IDevice device; if(enumerator.GetDefaultAudioEndpoint(0,role,out device)<0) continue;
   var iid = new Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"); object instance;
   Marshal.ThrowExceptionForHR(device.Activate(ref iid,23,IntPtr.Zero,out instance));
   var manager=(IManager)instance; ISessions sessions; Marshal.ThrowExceptionForHR(manager.GetSessionEnumerator(out sessions));
   int count; Marshal.ThrowExceptionForHR(sessions.GetCount(out count));
   for(int i=0;i<count;i++) {
    object session; Marshal.ThrowExceptionForHR(sessions.GetSession(i,out session));
    uint pid; var control=(IControl)session; Marshal.ThrowExceptionForHR(control.GetProcessId(out pid));
    if(!wanted.Contains(pid)) continue;
    var volume=(IVolume)session; var context=Guid.Empty;
    Marshal.ThrowExceptionForHR(volume.SetMute(true,ref context));
    Marshal.ThrowExceptionForHR(volume.SetMasterVolume(0f,ref context));
    float level; bool muted; Marshal.ThrowExceptionForHR(volume.GetMasterVolume(out level)); Marshal.ThrowExceptionForHR(volume.GetMute(out muted));
    results.Add("pid="+pid+" role="+role+" volume="+level+" muted="+muted);
   }
  }
  return results.ToArray();
 }
}
'@
[TestSessionAudio]::Silence($ProcessIds)
