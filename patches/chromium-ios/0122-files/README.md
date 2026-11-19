iOS Views audio: start AVAudioSession as Playback, upgrade for input

Apply after 0121. This does not go into the device IPA; keep
enable_ios_desktop_views off for device builds. The 0026 look-alike
shell is not BrowserView and is not built on.

What this patch does
--------------------
YouTube playback aborted in AUHALStream::ConfigureAUHAL -> AudioUnitInitialize -> AURemoteIO::Initialize with CoreAudio 'Initialize: RPC timeout. Apparently deadlocked. Aborting now.' The stream is already the iOS path (AudioManagerIOS, RemoteIO unit, kAudioObjectUnknown device), but AudioSessionManagerIOS set AVAudioSessionCategoryPlayAndRecord up front, which enables the input route (sim log: PrimarySessionActiveWithInputEnabled 0 -> 1) and made output-only RemoteIO init hang. Under ENABLE_IOS_DESKTOP_VIEWS the session now starts as Playback + MixWithOthers; AudioManagerIOS::MakeLowLatencyInputStream calls the new AudioSessionManagerIOS::EnsureRecordingCategory() to switch to PlayAndRecord when a page actually records. Non-desktop iOS builds are unchanged. media/audio BUILD.gn adds //build:ios_buildflags. Verified: youtube.com/watch?v=aqz-KE-bpKQ plays 1280x720 unmuted, currentTime advancing, captured audio peak 0.237 / RMS 0.056, AURemoteIO started on the simulator audio device, no crash.

Status (19 Nov 2026, 11:58 AM ET)
--------------------------------
Real BrowserView (tab strip, toolbar, omnibox, Blink contents) runs on
the iOS 27 Simulator TVOut scene; phone trackpad input in progress.

Replace the listed files with the copies in this directory.
