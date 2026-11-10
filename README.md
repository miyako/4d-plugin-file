# 4d-plugin-file

The File plugin converts a file or folder path into a pair of file-system identifiers (a **volume number** and a **file number**) and resolves that pair back into the item's current path. As long as an item stays on the same volume, its file number normally survives moves and renames, so you can store the pair and find the item again after it has been moved or renamed. On macOS the plugin uses the Carbon File Manager catalog (`FSGetCatalogInfo` / `FSResolveNodeID`); on Windows it uses the NTFS file index (`GetFileInformationByHandle` / `OpenFileById`). Both commands return a Longint error code; the identifiers and the path are returned through `Text` parameters.

| Command | Returns | Purpose |
|---|---|---|
| [`FILE Get id`](#file-get-id) | Longint (error code) | Get the volume number and file number of a file or folder |
| [`FILE Get path`](#file-get-path) | Longint (error code) | Get the current path of the item identified by a volume number and file number |

**Platforms:** macOS, Windows

## Native ownership maintenance

The bounded audit baseline is `b5e93ddcf1fef1923f5d5c4e4e206a4629849291`.
Both native projects compile `4DPlugin.cpp`, the complete bundled
`4D Plugin API/4DPluginAPI.c`, and every wrapper implementation in
`4D Plugin API/Classes`. The actual SDK export is `FourDPackex`
(`4DPluginAPI.def` on Windows), which initializes the engine callback and calls
`PluginMain` / `CommandDispatcher`. Selectors 1 and 2 implement the two scalar
`&T;&T;&T):L` commands in `manifest.json`; the prebuilt bundle's manifest is
the same. Those signatures do not exclude defects in compiled dormant helpers.

| Inventoried native surface | Ownership result / reachability |
|---|---|
| `4DPlugin.cpp`, `4DPlugin.h` | Both command handlers and all platform helpers inspected, including dormant `pathGetFileSystemNumbers`, `pathGetReferenceUrl`, and `getFileSystemPath`. Text parameters copy into `C_TEXT`; native Create/Copy results are released after copying. |
| `C_TEXT.{cpp,h}`, `ARRAY_TEXT.{cpp,h}`, `C_TYPES.h` | Borrowed parameter/array buffers copy into independent C++ strings. Scalar outputs use the SDK content setter. Array outputs independently allocate each element and transfer without subsequent disposal. |
| `C_PICTURE.{cpp,h}` | Compiled but unused by the dispatcher. Fixed path-argument double disposal, overwritten initial string/picture owners, retained output/temporary leaks, and charset byte-count misuse. Borrowed input pictures detach before argument cleanup; returned pictures remain owning and must be disposed by their consumer. |
| `C_BLOB.{cpp,h}`, `C_POINTER.{cpp,h}` | Byte storage copies; pointer metadata conversion inspected. `C_POINTER::getVariable` cleanup is deferred because the metadata/value contract is ambiguous. |
| `C_DATE`, `C_INTEGER`, `C_LONGINT`, `C_REAL`, `C_TIME` (each `.cpp` and `.h`) | Scalar value wrappers, no native string owners. |
| `ARRAY_BOOLEAN`, `ARRAY_DATE`, `ARRAY_INTEGER`, `ARRAY_LONGINT`, `ARRAY_REAL`, `ARRAY_TIME` (each `.cpp` and `.h`) | Numeric/value arrays inspected, including conversion, resize and cleanup paths; no string transfers. |
| `4DPluginAPI.{c,h,def}`, `PublicTypes.h`, `PrivateTypes.h`, `EntryPoints.h`, `Flags.h`, `4D Plugin_Prefix.pch` | SDK, ABI, include closure and export boundary inspected, not edited. Xcode sources and Visual Studio compile/include lists include all wrappers; no alternate native SDK or third-party library source is tracked. |

The exact bundled engine's git blob is
`478081f0238f6bc5393222f574bc2656f010b67b`, SHA-256
`355ee208ad6c61dcc68e8432546fc42484888211dd07ed8fa3fdb4440f3edbd8`,
introduced by repository commit `9a7d193bf1eb2b36b9464d16bc288c751b081cf1`.
The v13/v14 header comments are not independently verified upstream SDK versions;
there is no SDK dependency lock identifying an upstream distribution.

In this implementation, `PA_SetStringInArray` disposes the old element and
shallow-transfers only for Unicode arrays with non-null data, index
`0 <= i <= fNbElements`, and a non-null input descriptor. Rejection retains
caller ownership; getters borrow. Scalar string/picture setters shallow-alias
and do not release an existing destination, so use Undefined before assigning
an existing owner. Typed picture output arguments still start with an owned
empty picture. `PA_SetUnistring` / `PA_ReturnString` instead invoke an
engine-backed content setter. `PA_ConvertCharsetToCharset` returns bytes,
not UTF-16 code units. The SDK command handle-allocation failure returns raw
kind zero, which `PA_GetVariableKind` misleadingly normalizes to Unistring;
do not adopt/clear it as a string. Method failure returns Undefined.
There are no first-party method callbacks, JSON Parse, object or collection
getter call sites in this repository.

Run `python3 tests/run_native_ownership.py --output <dedicated-temporary-directory>`
on macOS. This compiles **all actual production native sources plus the full,
unchanged SDK** with ASan/UBSan, using a tracking engine callback rather than
substitute API snippets. It does not build/sign/package the plugin. The same
harness accepts `--source <immutable-git-archive-directory>` for baseline
comparison. Cases check exact ASCII/BMP/supplementary/empty text, allocated/null
empty strings, bytes versus units/capacity/termination, transfers and rejection,
borrowed copies, replacement/shrink/clear, independent synchronous arguments,
owning returns, failed command handles/commands and explicit string/handle/picture
balances (macOS LSan is unavailable).

The identical final harness passes 8/28 baseline cases and fails the 20 named
path double-disposal, picture-balance and `createCopy` over-read regressions;
corrected sources pass 28/28. The shim models
the SDK's engine boundary, not a real 4D host. Windows/real-4D execution remains
unverified. Picture-data metadata string ownership and SDK-only app-path
outputs are deferred rather than guessed. Normal array tests do not certify
the SDK's unrelated resize-OOM count-corruption behavior. Manifests, native
projects, SDK files, prebuilt binaries and manual publication workflows remain
unchanged; the separate Native ownership CI only compiles and runs unsigned tests.

## Manual versioning and publication

**Bump version** and **Build** are independent manual Actions workflows.
Select the branch explicitly for Bump, then select patch/minor/major. Bump
checks out the immutable dispatch SHA, requires a clean checkout and an unchanged
remote branch, and commits only source display metadata to that branch. Its
mandatory executable pre-push guard checks exactly one advertised update: the
old SHA must equal the selected SHA, the literal new SHA must equal local HEAD,
and its direct parent and target must match the selection. Late advances,
ancestor rewinds, deletions and same-result races fail closed. It uses a
non-force push with both `push.followTags=false` and `--no-follow-tags`.
It creates no tags and does not trigger Build.

**Build** has no inputs and runs only via `workflow_dispatch`. Select the desired
source ref; every job checks out the same immutable `github.sha`, not a moving
branch or a typed tag. Build validates strict source `X.Y.Z` before native work.
Publication is serialized across all branches by a constant concurrency group,
without cancelling running builds. There is no new default-branch-only gate.

The release authority is the three project-level `MARKETING_VERSION` settings in
`File.xcodeproj/project.pbxproj`. The original Bump header explicitly promised
coordinating `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` and source
`CFBundleShortVersionString`/`CFBundleVersion`. Its marketing-first implementation
and commits `805eaf2`, `b0c4816` and `fc30ab4` left current at `1.0.0`; that was
implementation drift, not a separate build-version contract. This migration
repairs all three current settings and the localized `1.0` display values to the
existing marketing authority `1.0.3`, without a release-version increment.
Bump validates and co-bumps both project version keys, the existing applicable
source plist fields, and the two version-bearing localized strings in
`English.lproj/InfoPlist.strings`. Valid resolved Xcode references, absent
`CFBundleVersion`, BOMs, line endings and modes are preserved. Prebuilt
bundles, localization counters, manifest/schema revisions, 4D projects and
native dependencies are not version inputs.

Before building and again after Windows/macOS builds, universal verification,
merge, codesigning, packaging, both notarization submissions and DMG stapling,
Build checks the exact remote tag and **all authenticated paginated releases,
including drafts**. A conflict, malformed page/entry, authentication, 404,
network or later-page error stops publication; only a complete no-match passes.
It creates `vX.Y.Z` at the selected SHA using create-only `POST git/refs`, verifies
the remote SHA, then creates a new non-draft, non-prerelease release named
`vX.Y.Z` with explicit target SHA and an empty body (the original notes policy).
It separately uploads `File-X.Y.Z.zip` and `File-X.Y.Z.dmg` to that newly returned
release ID. Existing tags/releases/assets are never reused, updated or clobbered;
even a same-SHA tag race is rejected.

**Partial publication recovery:** there is no deletion, rollback or retry.
If tag creation, release creation or an asset upload fails or returns malformed
data, any tag, release and earlier assets remain. Inspect the workflow error,
exact remote tag SHA, release ID and assets manually before deciding recovery.
Do not rerun Build to overwrite partial state: its availability checks will
reject it. An authorized maintainer must decide how to resolve the retained
state outside this workflow, or use a separately approved source bump for a new
version.

### Existing native and signing caveats

Windows remains x64 with the existing hosted-runner v143/Windows SDK 10.0
overrides for the legacy v140 project. The solution's legacy library search
paths are retained; no new third-party native dependency is introduced.
macOS retains the Cocoa/AppKit/CoreGraphics frameworks, deprecated Carbon
File Manager APIs, universal arm64/x86_64 requirement, and the workflow's
deployment-target override (`10.13`) despite project settings (`11.5`).
Compatibility with future hosted Xcode/SDK versions is not asserted by this
workflow-only migration; native compilation may expose existing API/target
limitations. Certificate import, identity discovery, strict codesign verification,
both notary submissions and DMG stapling remain required. Existing secret names
are unchanged: `APPLE_DEVELOPER_ID_CERTIFICATE`,
`APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD`, `KEYCHAIN_PASSWORD`,
`NOTARYTOOL_APPLE_ID`, `NOTARYTOOL_TEAM_ID`, `NOTARYTOOL_PASSWORD`.
No signing or native gate is skipped to work around runner or credential failures.

Local lifecycle checks (no native build or signing):

```sh
actionlint .github/workflows/bump-version.yml .github/workflows/release.yml
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s .github/tests -p 'test_*.py'
```

---

## Requirements & platform notes

- **Treat the identifiers as opaque text.** Both numbers are exchanged as `Text`, and you should store and pass them back as `Text`. On Windows the file number is a 64-bit unsigned value; converting it to a Real (for example with `Num`) loses precision above 2^53 and can resolve the wrong item or nothing at all.
- **The identifiers are platform-specific.** A pair obtained on macOS is meaningless on Windows and vice versa, even for the same physical disk.
- **What the numbers are.** **On macOS**, the volume number is the volume reference number assigned when the volume is mounted (a small negative integer such as `-100`) and the file number is the catalog node ID (32-bit). **On Windows**, the volume number is the volume serial number (32-bit unsigned decimal) and the file number is the 64-bit file index.
- **Stability depends on the file system and on how the file is saved.** See [What keeps (or changes) a file number](#what-keeps-or-changes-a-file-number) below — read it before you rely on stored pairs.
- **Both commands take exactly three parameters.** There is no optional form. The first parameter is input for `FILE Get id` and output for `FILE Get path`; the other two are the reverse.
- **Paths use the platform's native format**, the same format returned by 4D commands such as `Get 4D folder`. **On macOS** that is the colon-separated (HFS-style) path, for example `Macintosh HD:Users:me:file.txt`. **On Windows** it is a backslash path, for example `C:\Users\me\file.txt`. Folder paths returned by `FILE Get path` always end with a separator.
- **Windows Vista or later.** The Windows implementation relies on `OpenFileById` and `GetFinalPathNameByHandle`, both introduced in Windows Vista.
- **macOS: deprecated system APIs.** The macOS implementation uses File Manager APIs (`FSRef`) that Apple has deprecated since macOS 10.8. They still work in current systems, but Apple could remove them in a future macOS release.
- **Check the error code, not just the path.** Failure is reported only through the Longint result. The commands do not raise a 4D error. See [Error handling & troubleshooting](#error-handling--troubleshooting).

### What keeps (or changes) a file number

A file number identifies a specific file-system entry, not a file's content or name:

- **Moving or renaming an item on the same volume keeps its file number.**
- **Moving an item to a different volume changes both numbers**, because it is physically copied to the new volume.
- **Recreating a file gives it a new file number.** Restoring from a backup creates a replica, so the restored file has a different number than the original.
- **Some applications replace a file on every save.** Microsoft Office, for example, writes a new file and deletes the old one, so a document's file number changes each time it is saved.
- **On macOS, the volume number can change across restarts or remounts.** The volume reference number is assigned when the volume is mounted. The startup volume usually keeps the same number, but external and network volumes can receive a different number after being unmounted and remounted or after a restart. A stored pair may then fail to resolve, or in rare cases point to an item on a different volume.
- **On macOS APFS volumes, file numbers are truncated to 32 bits.** APFS uses 64-bit object IDs, but the API this plugin uses exposes only 32 bits. Items whose ID exceeds that range may not resolve.
- **On Windows, FAT/exFAT volumes (typical USB sticks and SD cards) don't have stable file numbers.** On those file systems the number is derived from the entry's position in its parent folder, so moving an item changes it. NTFS volumes keep file numbers stable.
- **On Windows, two volumes can share a serial number** (for example a cloned disk or a mounted disk image). `FILE Get path` uses the first mounted volume whose serial matches.

---

## FILE Get id

### Syntax

```
error := FILE Get id ( pathIn ; volumeNumberOut ; fileNumberOut )
```

| Parameter | Type | Description |
|---|---|---|
| `pathIn` | Text | Full native path of an existing file or folder |
| `volumeNumberOut` | Text | Receives the volume number (see [Requirements](#requirements--platform-notes)) |
| `fileNumberOut` | Text | Receives the file number |
| Result | Longint | `0` on success, otherwise an error code (see [Error codes](#error-codes)) |

### Description

`FILE Get id` looks up the item at `pathIn` and returns its volume number and file number as decimal text.

It works for folders as well as documents. A folder path may be passed with or without a trailing separator.

If the item doesn't exist or can't be opened, the result is non-zero and `volumeNumberOut` and `fileNumberOut` are left empty.

**On Windows**, the command briefly opens the item to read its file information. It first tries a read open and, if that fails (for example because the item is a folder or is locked by another application), falls back to an attribute-only open. During the first attempt, the item is opened exclusively for a moment, so another application trying to open the same file at that exact instant can get a sharing error. This is only a concern if you call the command in a tight loop over files that other applications are actively using.

**On macOS**, the result is the File Manager error code when the catalog lookup fails, or `-1` if the path couldn't be converted or doesn't exist.

### Example

From the plugin's own test method (`Method1.4dm`):

```4d
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
```

In this test, `$path3` is passed to `FILE Get path` as the *output* parameter, so the command overwrites it with the path it resolves from the stored identifiers. The item was renamed by `MOVE DOCUMENT`, and the pair obtained before the rename still finds it.

Checking the result before using the identifiers:

```4d
var $error : Integer
var $volume; $file : Text

$error:=FILE Get id($docPath; $volume; $file)
If ($error=0)
	// store $volume and $file as Text, e.g. in two Text fields of a record
Else
	ALERT("Could not read the file id (error "+String($error)+")")
End if
```

---

## FILE Get path

### Syntax

```
error := FILE Get path ( pathOut ; volumeNumberIn ; fileNumberIn )
```

| Parameter | Type | Description |
|---|---|---|
| `pathOut` | Text | Receives the current full native path of the item. Folder paths always end with a separator |
| `volumeNumberIn` | Text | Volume number previously returned by [`FILE Get id`](#file-get-id) |
| `fileNumberIn` | Text | File number previously returned by [`FILE Get id`](#file-get-id) |
| Result | Longint | `0` on success, otherwise an error code (see [Error codes](#error-codes)) |

### Description

`FILE Get path` finds the item identified by `volumeNumberIn` and `fileNumberIn` and returns its current path, wherever it has been moved to or renamed on that volume. Any value previously in `pathOut` is replaced; on failure `pathOut` is empty.

**On macOS**, the path is returned in HFS (colon-separated) format with a trailing `:` for folders. Any failure (volume not mounted, item deleted, number out of range) returns `-1`.

**On Windows**, the plugin looks through the mounted local volumes for one whose serial number matches `volumeNumberIn`, then opens the item by file number on that volume. The path is returned in normal form (for example `C:\Data\report.xlsx`) with a trailing `\` for folders. This lookup can be slow the first time a sleeping external disk or an optical drive is queried, because Windows may have to spin it up.

**On Windows, the item must not be open exclusively elsewhere.** The plugin opens the target for reading without sharing, so the command fails with a sharing error (`32`) if another application currently holds the file open in a conflicting mode. Resolving **folders** on Windows has not been confirmed in this release; test it on your target systems before relying on it (on macOS, folders resolve normally).

### Example

From the plugin's own test method (`Method2.4dm`):

```4d
//%attributes = {}
//works for folders too
$pathIn:=Get 4D folder:C485

$error:=FILE Get id($pathIn; $volumeNumber; $fileNumber)

ALERT:C41("file id is:"+String:C10($fileNumber))

$error:=FILE Get path($pathOut; $volumeNumber; $fileNumber)

ALERT:C41("file path is:"+$pathOut)
```

Finding a stored document again and checking that it is still there:

```4d
var $error : Integer
var $path : Text

$error:=FILE Get path($path; $storedVolume; $storedFile)
Case of
	: ($error#0)
		ALERT("The document could not be found (error "+String($error)+")")
	: (Test path name($path)=Is a document)
		// $path is the document's current location
	Else
		ALERT("The stored reference now points to a folder")
End case
```

Resolving a list of stored references and collecting the ones that are gone:

```4d
var $refs; $missing : Collection
var $ref : Object
var $error : Integer
var $path : Text

// $refs contains objects like {volume: "...", file: "..."}
$missing:=New collection
For each ($ref; $refs)
	$error:=FILE Get path($path; $ref.volume; $ref.file)
	If ($error=0)
		$ref.path:=$path
	Else
		$ref.error:=$error
		$missing.push($ref)
	End if
End for each
```

---

## Error handling & troubleshooting

### Error codes

| Code | Platform | Meaning |
|---|---|---|
| `0` | both | Success |
| `-1` | both | Generic failure. **On macOS**: the path couldn't be converted, the item doesn't exist, or (`FILE Get path`) the identifiers didn't resolve. **On Windows**: the item was opened but its file information or final path couldn't be read |
| `-2` | Windows | `FILE Get path`: no mounted volume has this volume number (see note below) |
| `-3` | both | An internal error was caught inside the plugin; the output parameters may be empty (see note below) |
| other negative values | macOS | File Manager (`OSErr`) error code from the catalog lookup in `FILE Get id` |
| positive values | Windows | Windows system error code (for example `2` file not found, `3` path not found, `5` access denied, `32` sharing violation) |

Codes `-2` and `-3` exist only in plugin builds made from the corrected source released with this document. Older builds return `0` with an empty `pathOut` when no volume matches on Windows, and may not return a valid result at all (the calling process can appear stuck) in the rare case where `-3` is now returned.

- **Check the result code before using the output.** An empty `pathOut` or empty identifiers always come with a non-zero result in current builds. Older builds could return `0` with an empty path on Windows, so if you must support them, also test for an empty result.
- **`FILE Get path` returns `-2` on Windows although the volume is mounted.** Older builds could not match volumes whose serial number is `2147483648` or higher (about half of all volumes), and returned `0` with an empty path instead. Rebuild or update the plugin.
- **`FILE Get path` fails with `32` on Windows.** Another application has the file open in a mode that denies sharing. Retry later, or close the file in that application.
- **A stored pair no longer resolves.** The item may have been deleted, replaced by a save-as-new (Office documents), restored from backup, moved to another volume, or (Windows FAT/exFAT) moved within its volume. On macOS, the volume may have been remounted with a different volume number. Keep the last known path alongside the identifiers so you have a fallback.
- **The resolved path points to an unexpected item.** On macOS, a remounted external volume can receive a volume number previously used by another volume; on Windows, cloned disks can share a serial number. Validate the resolved item (name, size, or content) when correctness matters.
- **Paths returned by older Windows builds contain extra characters.** Builds made before this release could append invisible characters after the path returned by `FILE Get path`. Rebuild or update the plugin.
- **Don't convert the numbers to Real.** Keep them as `Text`. Windows file numbers are 64-bit and lose precision as Reals.
- **Network paths on Windows.** `FILE Get id` is not expected to work with UNC paths (`\\server\share\...`); map a drive letter or test on your configuration first. `FILE Get path` only searches local volumes.

---

## Quick reference

```4d
// path → identifiers
$error:=FILE Get id($path; $volume; $file)  // $volume, $file : Text

// identifiers → current path
$error:=FILE Get path($path; $volume; $file)  // folders end with a separator

If ($error#0)
	// 0 = OK; Windows > 0 = system error; macOS < 0 = OSErr; -1/-2/-3 = plugin
End if
```
