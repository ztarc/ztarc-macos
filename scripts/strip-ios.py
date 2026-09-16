#!/usr/bin/env python3
"""Remove the iOS targets from a staged Pangolin.xcodeproj.

ZTARC ships a macOS client. Upstream's project carries four targets, two of them
iOS, and leaving them in means the forbidden-word audit has to allowlist their
names, `xcodebuild -list` advertises schemes nobody can build, and every reader
has to know which half of the project is live.

This is done structurally rather than as a patch on purpose. project.pbxproj is
1145 lines of generated text; a diff against it conflicts on every upstream bump,
for changes that have nothing to do with us. Walking the object graph instead
stays correct as long as the two targets are still called what they are called.

The algorithm is mark-and-sweep, not enumeration:

  1. drop the named targets, their product references and their membership
     exception sets, everywhere they are *referenced* — including the
     TargetAttributes dict, where ids are keys rather than array members and an
     array-only pass misses them;
  2. keep only what is still reachable from rootObject.

Step 2 is what collects their build-configuration lists, build configurations,
build phases, the PBXBuildFiles those phases owned, and the dependency/proxy pair
wiring PacketTunneliOS into PangoliniOS — without this script having to know that
any of those object types exist. That is the property worth having: when upstream
restructures, the sweep still does the right thing.

plutil parses the OpenStep pbxproj and Python's plistlib does not, so the read
goes through `plutil -convert xml1`. Nothing can convert *back* — plutil emits
only xml1/binary1/json — so the write is our own OpenStep emitter. That matters:
the file Xcode gets is the format Xcode writes, so no question of whether an XML
pbxproj is accepted ever arises. Comments are dropped, which costs nothing
because they are cosmetic and this file is never diffed against upstream.
"""

import plistlib
import re
import subprocess
import sys

TARGETS_TO_REMOVE = ("PangoliniOS", "PacketTunneliOS")

ID_RE = re.compile(r"^[0-9A-F]{24}$")
# Xcode leaves a token unquoted when it is this shape, and quotes it otherwise.
# Reproducing that exactly keeps brand/rules.sed rules written against upstream's
# text matching the text we emit.
BARE_RE = re.compile(r"^[A-Za-z0-9_$./]+$")


def read_pbxproj(path):
    xml = subprocess.run(
        ["plutil", "-convert", "xml1", "-o", "-", path],
        check=True, capture_output=True,
    ).stdout
    return plistlib.loads(xml)


def quote(s):
    if s == "" or not BARE_RE.match(s):
        escaped = (
            s.replace("\\", "\\\\")
            .replace('"', '\\"')
            .replace("\n", "\\n")
            .replace("\t", "\\t")
        )
        return '"%s"' % escaped
    return s


def emit(node, indent=1):
    pad = "\t" * indent
    close = "\t" * (indent - 1)
    if isinstance(node, dict):
        if not node:
            return "{\n%s}" % close
        body = "".join(
            "%s%s = %s;\n" % (pad, quote(k), emit(node[k], indent + 1))
            for k in sorted(node)
        )
        return "{\n%s%s}" % (body, close)
    if isinstance(node, list):
        if not node:
            return "(\n%s)" % close
        body = "".join("%s%s,\n" % (pad, emit(v, indent + 1)) for v in node)
        return "(\n%s%s)" % (body, close)
    return quote(str(node))


def purge(node, doomed):
    """Strip references to doomed ids, wherever they appear."""
    if isinstance(node, dict):
        for key in [k for k in node if k in doomed]:
            del node[key]
        for value in node.values():
            purge(value, doomed)
    elif isinstance(node, list):
        node[:] = [v for v in node if not (isinstance(v, str) and v in doomed)]
        for value in node:
            purge(value, doomed)


def referenced_ids(node, objects, out):
    if isinstance(node, dict):
        for key, value in node.items():
            if key in objects:
                out.add(key)
            referenced_ids(value, objects, out)
    elif isinstance(node, list):
        for value in node:
            referenced_ids(value, objects, out)
    elif isinstance(node, str) and ID_RE.match(node) and node in objects:
        out.add(node)


def reachable_from(root_id, objects):
    seen, queue = set(), [root_id]
    while queue:
        current = queue.pop()
        if current in seen or current not in objects:
            continue
        seen.add(current)
        found = set()
        referenced_ids(objects[current], objects, found)
        queue.extend(found - seen)
    return seen


def main(path):
    plist = read_pbxproj(path)
    objects = plist["objects"]
    root = objects[plist["rootObject"]]

    doomed = set()
    for target_id in list(root["targets"]):
        target = objects.get(target_id)
        if target and target.get("name") in TARGETS_TO_REMOVE:
            doomed.add(target_id)
            if "productReference" in target:
                doomed.add(target["productReference"])

    if len(doomed) == 0:
        sys.exit(
            "strip-ios: found none of %s in this project. Upstream renamed or "
            "removed them; check before assuming this is a no-op." % (TARGETS_TO_REMOVE,)
        )

    # Exception sets belong to a target. Once the target is gone so is the set;
    # keeping it would leave a reference to an id that no longer resolves.
    for obj_id, obj in objects.items():
        if obj.get("isa") == "PBXFileSystemSynchronizedBuildFileExceptionSet":
            if obj.get("target") in doomed:
                doomed.add(obj_id)

    purge(plist, doomed)
    for obj_id in doomed:
        objects.pop(obj_id, None)

    # The surviving macOS targets exclude the iOS sources by listing them. Those
    # files are about to be deleted from the staging tree, so the exclusions name
    # nothing. Note this is an *exclude* list for these targets — macOS/Info.plist
    # is in it too and must stay, or the Info.plist would be copied in as a
    # bundle resource on top of being consumed via INFOPLIST_FILE.
    for obj in objects.values():
        if obj.get("isa") == "PBXFileSystemSynchronizedBuildFileExceptionSet":
            obj["membershipExceptions"] = [
                m for m in obj.get("membershipExceptions", [])
                if not m.startswith("iOS/")
            ]

    live = reachable_from(plist["rootObject"], objects)
    swept = set(objects) - live
    for obj_id in swept:
        del objects[obj_id]

    # Integrity: every id mentioned anywhere still resolves, and nothing is left
    # floating. Cheap, and it is the check that would catch an upstream change
    # this script did not anticipate.
    mentioned = set()
    referenced_ids(plist, objects, mentioned)
    dangling = {
        m for m in re.findall(r"\b[0-9A-F]{24}\b", emit(plist))
        if m not in objects and m != plist["rootObject"]
    }
    if dangling:
        sys.exit("strip-ios: dangling references after strip: %s" % sorted(dangling))

    names = sorted(
        o["name"] for o in objects.values() if o.get("isa") == "PBXNativeTarget"
    )
    if len(names) != 2:
        sys.exit("strip-ios: expected 2 targets after strip, got %s" % names)

    with open(path, "w") as handle:
        handle.write("// !$*UTF8*$!\n" + emit(plist) + "\n")

    print("strip-ios: removed %d objects, %d remain; targets now %s"
          % (len(doomed) + len(swept), len(objects), names))


if __name__ == "__main__":
    main(sys.argv[1])
