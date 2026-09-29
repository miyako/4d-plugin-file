//%attributes = {}
//works for folders too
$pathIn:=Get 4D folder:C485

$error:=FILE Get id($pathIn; $volumeNumber; $fileNumber)

ALERT:C41("file id is:"+String:C10($fileNumber))

$error:=FILE Get path($pathOut; $volumeNumber; $fileNumber)

ALERT:C41("file path is:"+$pathOut)
