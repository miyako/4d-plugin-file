#include "4DPluginAPI.h"
#include "PrivateTypes.h"
#include "EntryPoints.h"
#include <algorithm>
#include <codecvt>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <locale>
#include <stdexcept>

namespace {
void require(bool condition, const char* message)
{
    if (!condition) throw std::runtime_error(message);
}

std::map<PA_Unichar*, size_t> strings;
std::map<PA_Handle, size_t> handles;
struct Picture { unsigned references; std::vector<uint8_t> bytes; };
std::map<PA_Picture, Picture*> pictures;
bool allocatedEmpty = true;
bool failHandle = false;
bool failCommand = false;
CUTF16String expectedText;
unsigned commandCalls = 0;

CUTF16String text(const PA_Unistring& value)
{
    require(value.fLength >= 0, "negative text length");
    if (!value.fString) {
        require(value.fLength == 0, "null nonempty string");
        return CUTF16String();
    }
    PA_Unichar* buffer = value.fString;
    require(strings.count(buffer) != 0, "read of released string");
    require(strings.at(buffer) == static_cast<size_t>(value.fLength),
            "exact UTF16 length");
    require(value.fString[value.fLength] == 0, "UTF16 terminator");
    return CUTF16String(value.fString, value.fLength);
}

PA_Unistring makeString(const CUTF16String& value)
{
    PA_Unistring result = {};
    result.fLength = static_cast<PA_long32>(value.size());
    if (!value.empty() || allocatedEmpty) {
        result.fString = new PA_Unichar[value.size() + 1];
        std::copy(value.begin(), value.end(), result.fString);
        result.fString[value.size()] = 0;
        PA_Unichar* buffer = result.fString;
        strings[buffer] = value.size();
    }
    return result;
}

void releaseString(PA_Unistring value)
{
    if (!value.fString) return;
    PA_Unichar* buffer = value.fString;
    require(strings.erase(buffer) == 1, "double string disposal");
    delete[] value.fString;
}

PA_Picture makePicture(const void* bytes, size_t size)
{
    Picture* picture = new Picture{1, {}};
    if (size) {
        require(bytes != NULL, "nonempty picture bytes");
        const uint8_t* start = static_cast<const uint8_t*>(bytes);
        picture->bytes.assign(start, start + size);
    }
    pictures[picture] = picture;
    return picture;
}

Picture* picture(PA_Picture value)
{
    require(pictures.count(value) == 1, "released picture");
    return pictures.at(value);
}

void releasePicture(PA_Picture value)
{
    if (!value) return;
    Picture* p = picture(value);
    require(p->references > 0, "picture reference underflow");
    if (--p->references == 0) {
        pictures.erase(value);
        delete p;
    }
}

void clear(PA_Variable* variable)
{
    switch (variable->fType) {
        case eVK_Unistring: releaseString(variable->uValue.fString); break;
        case eVK_Picture: releasePicture(variable->uValue.fPicture); break;
        case eVK_ArrayUnicode: {
            PA_Handle h = variable->uValue.fArray.fData;
            if (h) {
                require(handles.count(h) == 1, "array handle alive");
                require(handles.at(h) >= (variable->uValue.fArray.fNbElements + 1)
                        * sizeof(PA_Unistring), "array physical capacity");
                PA_Unistring* data = reinterpret_cast<PA_Unistring*>(*h);
                for (PA_long32 i = 0; i <= variable->uValue.fArray.fNbElements; ++i)
                    releaseString(data[i]);
                PA_DisposeHandle(h);
            }
            break;
        }
        case eVK_Undefined:
        case eVK_Longint: break;
        default: throw std::runtime_error("unexpected variable cleanup (raw sentinel?)");
    }
    *variable = PA_CreateVariable(eVK_Undefined);
}

pascal void engine(short selector, EngineBlock* eb)
{
    switch (selector) {
        case EX_CREATE_UNISTRING: {
            const PA_Unichar* source = reinterpret_cast<PA_Unichar*>(eb->fHandle);
            eb->fUniString1 = makeString(source ? CUTF16String(source) : CUTF16String());
            break;
        }
        case EX_DISPOSE_UNISTRING: releaseString(eb->fUniString1); break;
        case EX_SET_UNISTRING: {
            const PA_Unichar* source = reinterpret_cast<PA_Unichar*>(eb->fHandle);
            CUTF16String copy = source ? CUTF16String(source) : CUTF16String();
            releaseString(eb->fUniString1);
            eb->fUniString1 = makeString(copy);
            break;
        }
        case EX_CLEAR_VARIABLE: clear(static_cast<PA_Variable*>(eb->fPtr1)); break;
        case EX_CREATE_PICTURE:
            eb->fPicture = makePicture(eb->fPtr1, eb->fParam1);
            eb->fError = 0;
            break;
        case EX_DISPOSE_PICTURE: releasePicture(eb->fPicture); break;
        case EX_DUPLICATE_PICTURE:
            require(eb->fParam1 == 0, "retainOnly forwarded as zero");
            if (eb->fPicture) ++picture(eb->fPicture)->references;
            break;
        case EX_GET_PICTURE_DATA:
            picture(eb->fPicture);
            // No representations. Failure output deliberately unusable: no adoption/cleanup.
            eb->fUniString1.fString = reinterpret_cast<PA_Unichar*>(1);
            eb->fUniString1.fLength = -1;
            eb->fError = -1;
            break;
        case EX_HANDLE_MANAGER: {
            PA_Handle h;
            switch (eb->fParam1) {
                case 1: {
                    if (failHandle) { eb->fHandle = NULL; eb->fError = -1; break; }
                    size_t size = eb->fParam2;
                    h = new char*;
                    *h = static_cast<char*>(std::calloc(std::max<size_t>(1, size), 1));
                    require(*h != NULL, "test handle allocation");
                    handles[h] = eb->fParam2;
                    eb->fHandle = h;
                    break;
                }
                case 2:
                    h = eb->fHandle;
                    require(handles.erase(h) == 1, "double handle disposal");
                    std::free(*h);
                    delete h;
                    break;
                case 3: {
                    h = eb->fHandle;
                    size_t size = eb->fParam2;
                    require(handles.count(h) == 1, "resize live handle");
                    *h = static_cast<char*>(std::realloc(*h, std::max<size_t>(1, size)));
                    require(*h != NULL, "test handle resize");
                    handles[h] = eb->fParam2;
                    break;
                }
                case 4:
                    h = eb->fHandle;
                    require(handles.count(h) == 1, "size live handle");
                    eb->fParam2 = handles.at(h);
                    break;
                case 5:
                    h = eb->fHandle;
                    require(handles.count(h) == 1, "lock live handle");
                    eb->fParam3 = reinterpret_cast<sLONG_PTR>(*h);
                    break;
                case 6:
                    h = eb->fHandle;
                    require(handles.count(h) == 1, "unlock live handle");
                    break;
                default: throw std::runtime_error("unexpected handle operation");
            }
            break;
        }
        case EX_CONVERT_CHARSET_TO_CHARSET: {
            require(eb->fParam2 == eVTC_UTF_8 && eb->fParam4 == eVTC_UTF_16,
                    "conversion direction");
            std::string input(static_cast<char*>(eb->fPtr1), eb->fParam1);
            std::wstring_convert<std::codecvt_utf8_utf16<char16_t>, char16_t> converter;
            std::u16string converted = converter.from_bytes(input);
            size_t bytes = converted.size() * sizeof(PA_Unichar);
            require(static_cast<size_t>(eb->fParam3) >= bytes + sizeof(PA_Unichar),
                    "conversion capacity in bytes including terminator");
            std::memcpy(eb->fPtr2, converted.data(), bytes);
            static_cast<PA_Unichar*>(eb->fPtr2)[converted.size()] = 0;
            eb->fParam3 = bytes; // Returned bytes exclude terminator, not UTF16 units.
            eb->fError = 0;
            break;
        }
        case EX_CALL_BY_PROCID: {
            PA_Variable* values = reinterpret_cast<PA_Variable*>(*eb->fHandle);
            require(eb->fParam2 == 1, "one synchronous callback argument");
            require(text(values[1].uValue.fString) == expectedText, "callback input alive");
            PA_Unistring output = makeString(expectedText);
            PA_SetStringVariable(&values[0], &output);
            eb->fError = 0;
            break;
        }
        case EX_EXECUTE_COMMAND_BY_ID: {
            ++commandCalls;
            PA_Variable** args = static_cast<PA_Variable**>(eb->fPtr1);
            PA_Variable* result = static_cast<PA_Variable*>(eb->fPtr2);
            require(result->fType == eVK_Undefined, "command result initially Undefined");
            if (failCommand) { eb->fError = -1; break; }
            switch (eb->fParam1) {
                case 678:
                    require(text(args[0]->uValue.fString) == expectedText, "exact path text");
                    require(args[1]->fType == eVK_Picture, "typed picture output");
                    clear(args[1]);
                    PA_SetPictureVariable(args[1], makePicture("read", 4));
                    break;
                case 1002:
                    require(text(args[1]->uValue.fString) == expectedText, "exact codec text/length");
                    picture(args[0]->uValue.fPicture);
                    clear(args[0]);
                    PA_SetPictureVariable(args[0], makePicture("copy", 4));
                    break;
                case 988:
                    picture(args[0]->uValue.fPicture);
                    clear(args[0]);
                    PA_SetPictureVariable(args[0], makePicture("gray", 4));
                    break;
                case 457:
                    picture(args[0]->uValue.fPicture);
                    PA_SetLongintVariable(args[1], 12);
                    PA_SetLongintVariable(args[2], 34);
                    break;
                case 679:
                    picture(args[0]->uValue.fPicture);
                    clear(args[1]);
                    PA_SetPictureVariable(args[1], makePicture("thumb", 5));
                    break;
                default: throw std::runtime_error("unexpected 4D command");
            }
            eb->fError = 0;
            break;
        }
        default: throw std::runtime_error("unexpected engine selector");
    }
}

void balanced()
{
    require(strings.empty(), "string allocation balance");
    require(handles.empty(), "handle allocation balance");
    require(pictures.empty(), "picture reference balance");
}

void arrayContracts()
{
    PA_Variable array = PA_CreateVariable(eVK_ArrayUnicode);
    PA_ResizeArray(&array, 4);
    const PA_Unichar* fixtures[] = {
        reinterpret_cast<const PA_Unichar*>(u""),
        reinterpret_cast<const PA_Unichar*>(u"ASCII"),
        reinterpret_cast<const PA_Unichar*>(u"\u65e5\u672c"),
        reinterpret_cast<const PA_Unichar*>(u"\U0001f600"),
        reinterpret_cast<const PA_Unichar*>(u"ASCII")
    };
    for (PA_long32 i = 0; i <= 4; ++i) {
        PA_Unistring owned = PA_CreateUnistring(const_cast<PA_Unichar*>(fixtures[i]));
        PA_SetStringInArray(array, i, &owned);
    }
    require(PA_GetStringInArray(array, 1).fString != PA_GetStringInArray(array, 4).fString,
            "independent repeated text allocations");
    ARRAY_TEXT copy;
    BytePtr params[] = {reinterpret_cast<BytePtr>(&array)};
    copy.fromParamAtIndex(params, 1);
    PA_ResizeArray(&array, 0);
    copy.toParamAtIndex(params, 1);
    for (PA_long32 i = 0; i <= 4; ++i)
        require(text(PA_GetStringInArray(array, i)) == CUTF16String(fixtures[i]),
                "borrowed input copied before mutation");
    copy.toParamAtIndex(params, 1); // replacement disposes previous elements
    copy.setSize(2);
    copy.toParamAtIndex(params, 1); // shrink releases removed elements
    PA_ClearVariable(&array);
    PA_Variable wrong = PA_CreateVariable(eVK_Longint);
    PA_Variable missing = {};
    missing.fType = eVK_ArrayUnicode;
    PA_Unistring owned = PA_CreateUnistring(const_cast<PA_Unichar*>(fixtures[1]));
    PA_SetStringInArray(wrong, 0, &owned);
    PA_SetStringInArray(missing, 0, &owned);
    require(text(owned) == CUTF16String(fixtures[1]), "rejections retain caller ownership");
    PA_Variable valid = PA_CreateVariable(eVK_ArrayUnicode);
    PA_SetStringInArray(valid, -1, &owned);
    PA_SetStringInArray(valid, 100, &owned);
    require(text(owned) == CUTF16String(fixtures[1]), "rejected indices retain ownership");
    PA_DisposeUnistring(&owned);
    PA_SetStringInArray(valid, 0, NULL);
    PA_ClearVariable(&valid);
    balanced();
}

void scalarContracts()
{
    for (const char16_t* fixture : {u"", u"ASCII", u"\u65e5", u"\U0001f600"}) {
        PA_Unistring input = PA_CreateUnistring(
            const_cast<PA_Unichar*>(reinterpret_cast<const PA_Unichar*>(fixture)));
        C_TEXT wrapper;
        BytePtr params[] = {reinterpret_cast<BytePtr>(&input)};
        wrapper.fromParamAtIndex(params, 1);
        PA_DisposeUnistring(&input);
        wrapper.toParamAtIndex(params, 1);
        require(text(input) == CUTF16String(reinterpret_cast<const PA_Unichar*>(fixture)),
                "scalar copied input/content output");
        PA_Unistring returned = {};
        PA_Unistring* destination = &returned;
        wrapper.setReturn(reinterpret_cast<sLONG_PTR*>(&destination));
        require(text(returned) == text(input), "return content setter");
        if (input.fString) require(returned.fString != input.fString, "independent scalar outputs");
        PA_DisposeUnistring(&input);
        PA_DisposeUnistring(&returned);
    }
    // The full SDK returns raw kind 0, not normalized Unistring, if its handle fails.
    failHandle = true;
    PA_Variable result = PA_ExecuteCommandByID(678, NULL, 0);
    failHandle = false;
    require(result.fType == 0, "raw command failure sentinel");
    require(PA_GetVariableKind(result) == eVK_Unistring, "normalization is not ownership evidence");
    failHandle = true;
    result = PA_ExecuteMethodByID(1, NULL, 0);
    failHandle = false;
    require(result.fType == eVK_Undefined, "method failure Undefined");
    PA_ClearVariable(&result);
    balanced(); // Do not clear the raw sentinel.
}

void callbackContracts()
{
    expectedText = reinterpret_cast<const PA_Unichar*>(u"\u65e5\U0001f600");
    PA_Variable array = PA_CreateVariable(eVK_ArrayUnicode);
    PA_Unistring element = PA_CreateUnistring(const_cast<PA_Unichar*>(expectedText.c_str()));
    PA_SetStringInArray(array, 0, &element);
    PA_Unistring argument = PA_CreateUnistring(const_cast<PA_Unichar*>(expectedText.c_str()));
    PA_Variable arg = PA_CreateVariable(eVK_Undefined);
    PA_SetStringVariable(&arg, &argument);
    PA_Variable returned = PA_ExecuteMethodByID(1, &arg, 1);
    PA_ClearVariable(&arg); // Independent synchronous argument, not array-owned.
    require(text(returned.uValue.fString) == expectedText, "owning method return survives argument cleanup");
    require(text(PA_GetStringInArray(array, 0)) == expectedText, "callback independent of array");
    PA_ClearVariable(&returned);
    PA_ClearVariable(&array);
    balanced();
}

void pictureCase(const std::string& name)
{
    PA_Picture survivor = NULL;
    {
        CPicture p;
        if (name == "set-bytes") {
            p.setBytes(reinterpret_cast<const uint8_t*>("pixels"), 6);
            require(picture(p.getPicture())->bytes.size() == 6, "picture bytes retained");
        } else if (name == "path" || name == "path-failure" || name == "path-empty"
                   || name == "path-handle-failure") {
            for (const char* fixture : {"", "ASCII", "\xe6\x97\xa5", "\xf0\x9f\x98\x80"}) {
                CUTF8String path(reinterpret_cast<const uint8_t*>(fixture));
                std::wstring_convert<std::codecvt_utf8_utf16<char16_t>, char16_t> converter;
                std::u16string converted = converter.from_bytes(fixture);
                expectedText.assign(reinterpret_cast<const PA_Unichar*>(converted.data()), converted.size());
                failCommand = name == "path-failure";
                failHandle = name == "path-handle-failure";
                p.fromFileAtPath(&path);
                picture(p.getPicture());
                failCommand = false;
                failHandle = false;
                if (name == "path-empty") break;
            }
        } else if (name == "copy" || name == "copy-empty") {
            for (const char* fixture : {"", ".png", "\xe6\x97\xa5", "\xf0\x9f\x98\x80"}) {
                std::wstring_convert<std::codecvt_utf8_utf16<char16_t>, char16_t> converter;
                std::u16string converted = converter.from_bytes(fixture);
                expectedText.assign(reinterpret_cast<const PA_Unichar*>(converted.data()), converted.size());
                PA_Picture result = p.createCopy(fixture);
                require(picture(result)->bytes.size() == 4, "owning conversion result survives cleanup");
                PA_DisposePicture(result);
                if (name == "copy-empty") break;
            }
        } else if (name == "gray") {
            PA_Picture result = p.createGrayScale();
            require(picture(result)->bytes.size() == 4, "owning grayscale result");
            survivor = result;
        } else if (name == "size") {
            unsigned width = 0, height = 0;
            p.getSize(&width, &height);
            require(width == 12 && height == 34, "scalar picture outputs");
            picture(p.getPicture());
        } else if (name == "thumbnail") {
            PA_Picture result = p.createThumbnail(10, 20);
            require(picture(result)->bytes.size() == 5, "owning thumbnail handoff");
            survivor = result;
            picture(p.getPicture());
        } else if (name == "picture-params") {
            PA_Picture input = PA_CreatePicture(NULL, 0);
            BytePtr params[] = {reinterpret_cast<BytePtr>(&input)};
            p.fromParamAtIndex(params, 1);
            p.toParamAtIndex(params, 1);
            PA_DisposePicture(input);
            PA_Picture result = NULL;
            p.setReturn(reinterpret_cast<sLONG_PTR*>(&result));
            picture(result);
            survivor = result;
        } else throw std::runtime_error("unknown test");
    }
    if (survivor) {
        picture(survivor); // Owning handoff outlives the source wrapper.
        PA_DisposePicture(survivor);
    }
    balanced();
}
}

int main(int argc, char** argv)
{
    try {
        require(argc == 3, "test name and empty mode required");
        allocatedEmpty = std::string(argv[2]) == "allocated";
        PackInitBlock init = {};
        init.fCall4Dex = engine;
        FourDPackex(kInitPlugin, &init, NULL, NULL);
        require(gCall4D == engine && init.fSupportedVersion == 0x00001400, "actual SDK initialization");
        const std::string name(argv[1]);
        if (name == "arrays") arrayContracts();
        else if (name == "scalars") scalarContracts();
        else if (name == "callbacks") callbackContracts();
        else pictureCase(name);
        std::cout << "PASS " << name << " " << argv[2] << "\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "FAIL " << argv[1] << ": " << error.what() << "\n";
        return 1;
    }
}
