"""Typed, key-scoped Dock preferences and native bookmark helpers (Darwin only)."""
import ctypes
import os
import plistlib
import sys
from pathlib import Path


class DockCoreFoundation:
    DOMAIN = "com.apple.dock"
    KEY = "persistent-apps"
    UTF8 = 0x08000100
    BINARY_PLIST = 200

    def __init__(self):
        if sys.platform != "darwin" or ctypes.sizeof(ctypes.c_void_p) != 8:
            raise RuntimeError("This helper requires a 64-bit Mac.")
        self.cf = ctypes.CDLL(
            "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")
        p = ctypes.c_void_p
        index = ctypes.c_long
        flags = ctypes.c_ulong
        boolean = ctypes.c_ubyte
        signatures = {
            "CFRelease": (None, [p]),
            "CFStringCreateWithCString": (p, [p, ctypes.c_char_p, ctypes.c_uint32]),
            "CFStringGetLength": (index, [p]),
            "CFStringGetMaximumSizeForEncoding": (index, [index, ctypes.c_uint32]),
            "CFStringGetCString": (boolean, [p, p, index, ctypes.c_uint32]),
            "CFDataCreate": (p, [p, p, index]),
            "CFDataGetLength": (index, [p]),
            "CFDataGetBytePtr": (p, [p]),
            "CFPropertyListCreateWithData": (p, [p, p, flags, p, ctypes.POINTER(p)]),
            "CFPropertyListCreateData": (p, [p, p, index, flags, ctypes.POINTER(p)]),
            "CFPreferencesCopyAppValue": (p, [p, p]),
            "CFPreferencesSetAppValue": (None, [p, p, p]),
            "CFPreferencesAppSynchronize": (boolean, [p]),
            "CFURLCreateWithFileSystemPath": (p, [p, p, index, boolean]),
            "CFURLCopyFileSystemPath": (p, [p, index]),
            "CFURLCreateBookmarkData": (p, [p, p, flags, p, p, ctypes.POINTER(p)]),
            "CFURLCreateByResolvingBookmarkData": (
                p, [p, p, flags, p, p, ctypes.POINTER(boolean), ctypes.POINTER(p)]),
            "CFErrorGetCode": (index, [p]),
            "CFErrorCopyDescription": (p, [p]),
        }
        for name, (result, arguments) in signatures.items():
            function = getattr(self.cf, name)
            function.restype = result
            function.argtypes = arguments

    def _release(self, *refs):
        for ref in refs:
            if ref:
                self.cf.CFRelease(ref)

    def _text(self, ref):
        if not ref:
            raise RuntimeError("Missing CoreFoundation string.")
        count = self.cf.CFStringGetLength(ref)
        size = self.cf.CFStringGetMaximumSizeForEncoding(count, self.UTF8) + 1
        if size <= 0:
            raise RuntimeError("Invalid CoreFoundation string size.")
        buffer = ctypes.create_string_buffer(size)
        if not self.cf.CFStringGetCString(ref, buffer, size, self.UTF8):
            raise RuntimeError("Could not decode CoreFoundation UTF-8 string.")
        return buffer.value.decode("utf-8")

    def _raise_error(self, operation, error):
        description = None
        try:
            if error.value:
                description = self.cf.CFErrorCopyDescription(error.value)
                detail = self._text(description) if description else "no description"
                code = self.cf.CFErrorGetCode(error.value)
                raise RuntimeError(f"{operation} failed (CFError {code}): {detail}")
            raise RuntimeError(f"{operation} returned NULL.")
        finally:
            self._release(description, error.value)

    def _string(self, value):
        ref = self.cf.CFStringCreateWithCString(None, value.encode("utf-8"), self.UTF8)
        if not ref:
            raise RuntimeError("Could not allocate CoreFoundation string.")
        return ref

    def _data(self, value):
        buffer = ctypes.create_string_buffer(value)
        ref = self.cf.CFDataCreate(None, buffer, len(value))
        if not ref:
            raise RuntimeError("Could not allocate CoreFoundation data.")
        return ref

    def _bytes(self, ref):
        return ctypes.string_at(self.cf.CFDataGetBytePtr(ref), self.cf.CFDataGetLength(ref))

    def _plist(self, value):
        data = self._data(plistlib.dumps(value, fmt=plistlib.FMT_BINARY, sort_keys=False))
        error = ctypes.c_void_p()
        try:
            ref = self.cf.CFPropertyListCreateWithData(None, data, 0, None,
                                                     ctypes.byref(error))
            if not ref:
                self._raise_error("Reading typed plist", error)
            self._release(error.value)
            return ref
        finally:
            self._release(data)

    def _python(self, ref):
        error = ctypes.c_void_p()
        data = self.cf.CFPropertyListCreateData(None, ref, self.BINARY_PLIST, 0,
                                              ctypes.byref(error))
        if not data:
            self._raise_error("Serializing typed plist", error)
        try:
            self._release(error.value)
            return plistlib.loads(self._bytes(data))
        finally:
            self._release(data)

    def roundtrip(self, value):
        """Read-only type preservation check; does not access preferences."""
        ref = self._plist(value)
        try:
            return self._python(ref)
        finally:
            self._release(ref)

    def bookmark(self, app):
        app = Path(app).resolve(strict=True)
        if app.suffix != ".app" or not (app / "Contents/Info.plist").is_file():
            raise RuntimeError("Bookmark target is not an existing application bundle.")
        text = url = book = None
        error = ctypes.c_void_p()
        try:
            text = self._string(str(app))
            url = self.cf.CFURLCreateWithFileSystemPath(None, text, 0, 1)
            if not url:
                raise RuntimeError("Could not create native application URL.")
            book = self.cf.CFURLCreateBookmarkData(None, url, 0, None, None,
                                                 ctypes.byref(error))
            if not book:
                self._raise_error("Creating application bookmark", error)
            self._release(error.value)
            data = self._bytes(book)
        finally:
            self._release(book, url, text)
        resolved, stale = self.resolve_bookmark(data)
        if stale or resolved != app:
            raise RuntimeError("New application bookmark did not resolve to its target.")
        return data

    def resolve_bookmark(self, data):
        if not isinstance(data, bytes) or not data:
            raise TypeError("Bookmark must contain nonempty bytes.")
        ref = url = text = None
        error = ctypes.c_void_p()
        stale = ctypes.c_ubyte(0)
        try:
            ref = self._data(data)
            # No UI, no volume mounting, and no implicit ephemeral access.
            options = (1 << 8) | (1 << 9) | (1 << 15)
            url = self.cf.CFURLCreateByResolvingBookmarkData(
                None, ref, options, None, None, ctypes.byref(stale), ctypes.byref(error))
            if not url:
                self._raise_error("Resolving application bookmark", error)
            self._release(error.value)
            text = self.cf.CFURLCopyFileSystemPath(url, 0)
            if not text:
                raise RuntimeError("Resolved bookmark has no filesystem path.")
            return Path(self._text(text)).resolve(strict=True), bool(stale.value)
        finally:
            self._release(text, url, ref)

    def read_persistent_apps(self):
        key = domain = value = None
        try:
            key = self._string(self.KEY)
            domain = self._string(self.DOMAIN)
            value = self.cf.CFPreferencesCopyAppValue(key, domain)
            if not value:
                raise RuntimeError("The Dock persistent-apps preference is missing.")
            result = self._python(value)
            if not isinstance(result, list) or any(not isinstance(t, dict) for t in result):
                raise RuntimeError("The existing Dock application preference is invalid.")
            return result
        finally:
            self._release(value, domain, key)

    def write_persistent_apps(self, apps, expected_apps, changed_index):
        """Replace one tile or append one; all other tiles must remain identical."""
        if not isinstance(apps, list) or not isinstance(expected_apps, list):
            raise TypeError("Dock applications must be typed lists.")
        if type(changed_index) is not int or not 0 <= changed_index <= len(expected_apps):
            raise ValueError("Invalid changed Dock index.")
        appended = changed_index == len(expected_apps)
        if len(apps) != len(expected_apps) + int(appended):
            raise RuntimeError("Refusing to change the number of unrelated Dock tiles.")
        preserved = apps[:changed_index] + apps[changed_index + 1:]
        original = expected_apps if appended else (
            expected_apps[:changed_index] + expected_apps[changed_index + 1:])
        if preserved != original:
            raise RuntimeError("Refusing to change any unrelated Dock application tile.")
        if not isinstance(apps[changed_index], dict):
            raise TypeError("Replacement Dock tile must be a typed dictionary.")
        if self.read_persistent_apps() != expected_apps:
            raise RuntimeError("Dock changed since backup; preserving the current Dock.")
        key = domain = value = None
        try:
            key = self._string(self.KEY)
            domain = self._string(self.DOMAIN)
            value = self._plist(apps)
            self.cf.CFPreferencesSetAppValue(key, value, domain)
            if not self.cf.CFPreferencesAppSynchronize(domain):
                raise RuntimeError("Could not synchronize the Dock preference; backup is preserved.")
            if self.read_persistent_apps() != apps:
                raise RuntimeError("Typed Dock preference readback failed; backup is preserved.")
        finally:
            self._release(value, domain, key)
