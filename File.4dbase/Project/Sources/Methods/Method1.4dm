//%attributes = {}
$path:=Get 4D folder:C485(Current resources folder:K5:16)+"4D-main-64.jpg"
$path2:=Get 4D folder:C485(Current resources folder:K5:16)+Generate UUID:C1066+".jpg"
$path3:=Get 4D folder:C485(Current resources folder:K5:16)+Generate UUID:C1066+".jpg"

COPY DOCUMENT:C541($path; $path2)
$error:=FILE Get id($path2; $volumeNumber; $fileNumber)
ALERT:C41("file id is:"+String:C10($fileNumber))

MOVE DOCUMENT:C540($path2; $path3)

$error:=FILE Get path($path3; $volumeNumber; $fileNumber)
ALERT:C41("file path is:"+$path3)
DELETE DOCUMENT:C159($path3)
