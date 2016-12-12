# 4d-plugin-file
Convert file or folder path to volume/file number and back

###Platform

| carbon | cocoa | win32 | win64 |
|:------:|:-----:|:---------:|:---------:|
|🆗|🆗|🆗|🆗|

###Version

<img src="https://cloud.githubusercontent.com/assets/1725068/18940649/21945000-8645-11e6-86ed-4a0f800e5a73.png" width="32" height="32" /> <img src="https://cloud.githubusercontent.com/assets/1725068/18940648/2192ddba-8645-11e6-864d-6d5692d55717.png" width="32" height="32" />

###Remarks

In general, the file (folder) number is unchanged __even if the item is moved or renamed__, as long as the file stays in the same volume. It can be a useful way to keep track of file system items in some cases.

However, the file number will change, if the file is physically recreated on the file system. For example, __restoration from backup will create a replica of the file__, so the file number will not be the same as before. 

Some applications such as Microsoft Office __create a new file after every save operation__. The file number will be changed as a result.

###Syntax

```
error:=FILE Get id (pathIn;volumeNumberOut;fileNumberOut)
```

param|type|description
------------|------|----
pathIn|TEXT|full path
volumeNumberOut|TEXT|``FSCatalogInfo.volume (FSVolumeRefNum)`` on Mac, ``FILE_ID_INFO.VolumeSerialNumber (ULONGLONG)`` on Windows
fileNumberOut|TEXT|``FSCatalogInfo.nodeID (UInt32)`` on Mac, ``FILE_ID_INFO.FileId (FILE_ID_128)`` on Windows 

```
error:=FILE Get path (pathOut;volumeNumberIn;fileNumberIn)
```

param|type|description
------------|------|----
pathOut|TEXT|full path (folder path always ends with a separator)
volumeNumberIn|TEXT|see above
fileNumberIn|TEXT|see above
