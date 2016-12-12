# 4d-plugin-file
Convert file/folder path to volume/file number and back

###Platform

| carbon | cocoa | win32 | win64 |
|:------:|:-----:|:---------:|:---------:|
|🆗|🆗|🆗|🆗|

###Version

<img src="https://cloud.githubusercontent.com/assets/1725068/18940649/21945000-8645-11e6-86ed-4a0f800e5a73.png" width="32" height="32" /> <img src="https://cloud.githubusercontent.com/assets/1725068/18940648/2192ddba-8645-11e6-864d-6d5692d55717.png" width="32" height="32" />

###Syntax

```
error:=FILE Get id (pathIn;volumeNumberOut;fileNumberOut)
```

param|type|description
------------|------|----
pathIn|TEXT|
volumeNumberOut|TEXT|``FSCatalogInfo.volume (FSVolumeRefNum)`` on Mac; ``FILE_ID_INFO.VolumeSerialNumber (ULONGLONG)`` on Windows
fileNumberOut|TEXT|``FSCatalogInfo.nodeID (UInt32)`` on Mac; ``FILE_ID_INFO.VolumeSerialNumber (FILE_ID_128)`` on Windows 

```
error:=FILE Get path (pathOut;volumeNumberIn;fileNumberIn)
```

param|type|description
------------|------|----
pathOut|TEXT|
volumeNumberIn|TEXT|
fileNumberIn|TEXT|
