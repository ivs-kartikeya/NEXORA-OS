# Nexora Core API — V1

Session bus service: `org.nexora.Core`

Object: `/Core`

Interface: `org.nexora.Core`

Core owns small deterministic controls that should survive shell restarts.

## Methods

- `Ping() -> string`
- `GetStatus() -> a{sv}`
- `ListProjects() -> as`
- `CreateProject(name) -> string`
- `SetVolume(percent)`
- `SetMuted(muted)`
- `SetBrightness(percent)`
- `SetWifiEnabled(enabled)`
- `PowerAction(action)`

## Status fields

- `cpuUsage`
- `memoryUsage`
- `memoryUsedGiB`
- `memoryTotalGiB`
- `uptimeText`
- `networkConnected`
- `batteryPresent`
- `batteryPercent`
- `batteryCharging`
- `volumeLevel`
- `muted`
- `audioAvailable`
- `wifiAvailable`
- `wifiEnabled`
- `brightnessAvailable`
- `brightnessLevel`
- `version`

## Signals

- `StatusChanged(a{sv})`
- `AudioChanged(volume, muted, available)`
- `ProjectsChanged()`

The shell retains recovery fallbacks for a subset of controls during the V0.x development series.
