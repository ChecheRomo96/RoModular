#!/usr/bin/env python3
"""Report which RoModular libraries and modules a project uses.

Usage: scan-project.py <project-path> [--libraries <path>]

The scan reads the project's own sources (.ino, .cpp, .h, .hpp) and finds
the modules it needs from
  - fine-grained includes such as <MCC/Scale/Scales.h>, followed through the
    library sources, including the .cpp files compiled next to each header,
  - qualified names such as MCC::Scales::Make or MIDILAR::Protocol::Packet.

Umbrella headers such as <MCC.h> pull every module, so they are not
expanded. Instead the scan suggests the smallest set of root headers
(<MCC_Scale.h>, <MIDILAR_Devices.h>, ...) that covers the modules used.
Every library in the result keeps at least one root header, because the
Arduino builder only discovers a library through a header at the root of its
src folder; <Library_BuildSettings.h> is used when nothing else is needed.

The libraries are looked up in --libraries: a RoModular workspace or an
Arduino libraries folder. It defaults to the folder that contains this
RoModular checkout. The scan is a static text analysis and does not run the
preprocessor; check the result by building the project.
"""

import argparse
import pathlib
import re
import sys

INCLUDE = re.compile(r'^\s*#\s*include\s*([<"])([^>"]+)[>"]', re.M)
DECLARATION = re.compile(
    r'\b(?:class|struct|enum\s+class|enum|namespace|using)\s+([A-Z]\w*)')
QUALIFIED = re.compile(r'\b(\w+)((?:::\w+)+)')
COMMENT = re.compile(r'//[^\n]*|/\*.*?\*/', re.S)
SOURCE_SUFFIXES = (".ino", ".cpp", ".h", ".hpp")
SKIPPED_DIRECTORIES = {".git", "build", "out"}
SETTINGS = "BuildSettings"


def read(path):
    return path.read_text(encoding="utf-8", errors="ignore")


class Library:
    """A RoModular library: src/<Name>.h, src/<Name>/ and src/<Name>_<Module>.h."""

    def __init__(self, src, name):
        self.src = src
        self.name = name
        self.umbrella = name + ".h"
        prefix = name + "_"
        self.root_headers = {}
        for header in sorted(src.glob(prefix + "*.h")):
            self.root_headers[header.stem[len(prefix):]] = header.name
        self.modules = set(self.root_headers)
        self.symbols = {}
        for header in sorted((src / name).rglob("*.h")):
            module = self.module_of(header)
            if module:
                for symbol in DECLARATION.findall(COMMENT.sub("", read(header))):
                    self.symbols.setdefault(symbol, module)

    @staticmethod
    def find(folder):
        src = folder / "src"
        for header in sorted(src.glob("*.h")):
            if "_" not in header.stem and (src / header.stem).is_dir():
                return Library(src, header.stem)
        return None

    def module_of(self, path):
        parts = path.relative_to(self.src).parts
        if parts == (self.name + "_" + SETTINGS + ".h",):
            return SETTINGS
        if len(parts) >= 2 and parts[0] == self.name:
            module = parts[1][:-2] if parts[1].endswith(".h") else parts[1]
            return module if module in self.modules else None
        return None

    def owns(self, path):
        return self.src in path.parents


def project_sources(project):
    for path in sorted(project.rglob("*")):
        relative = path.relative_to(project).parts
        if path.suffix in SOURCE_SUFFIXES and path.is_file() \
                and not SKIPPED_DIRECTORIES.intersection(relative[:-1]):
            yield path


class Scanner:
    def __init__(self, libraries):
        self.libraries = libraries
        self.by_name = {library.name: library for library in libraries}
        self.headers = {}
        self.top_level = set()
        for library in libraries:
            for header in library.src.rglob("*.h"):
                self.headers[header.relative_to(library.src).as_posix()] = header
            self.top_level.add(library.umbrella)
            self.top_level.update(library.root_headers.values())

    def resolve(self, include, quote, current):
        if quote == '"':
            local = (current.parent / include).resolve()
            if local.is_file():
                return local
        return self.headers.get(include)

    def closure(self, start, expand_top_level):
        """Modules reached by following includes from the start files."""
        found, seen, pending = set(), set(), list(start)
        while pending:
            path = pending.pop()
            if path in seen:
                continue
            seen.add(path)
            for library in self.libraries:
                if not library.owns(path):
                    continue
                module = library.module_of(path)
                if module:
                    found.add((library.name, module))
                # The library's own .cpp files are compiled too.
                if path.suffix == ".h" and (library.src / library.name) in path.parents:
                    pending.extend(path.parent.glob("*.cpp"))
                    pending.extend(path.with_suffix("").glob("*.cpp"))
            for quote, include in INCLUDE.findall(read(path)):
                if include in self.top_level and not expand_top_level:
                    continue
                target = self.resolve(include, quote, path)
                if target:
                    pending.append(target)
        return found

    def qualified_names(self, sources):
        found = set()
        for path in sources:
            for root, rest in QUALIFIED.findall(COMMENT.sub("", read(path))):
                library = self.by_name.get(root)
                if not library:
                    continue
                names = rest.strip(":").split("::")
                module = names[0] if names[0] in library.modules else next(
                    (library.symbols[name] for name in names if name in library.symbols), None)
                if module:
                    found.add((library.name, module))
        return found

    def scan(self, project):
        sources = list(project_sources(project))
        needed = self.closure(sources, False) | self.qualified_names(sources)

        pulls = {}
        for library in self.libraries:
            for module, header in library.root_headers.items():
                pulls[(library.name, module)] = \
                    self.closure([library.src / header], True) | {(library.name, module)}

        # Keep a module header only when no other kept header already pulls it.
        keep = set(needed)
        for module in sorted(needed, key=lambda m: (-len(pulls.get(m, ())), m)):
            if any(module in pulls.get(other, ()) for other in keep if other != module):
                keep.discard(module)
        used = set()
        for module in keep:
            used |= pulls.get(module, {module})

        # One root header per library in use, for Arduino library discovery.
        for name in sorted({n for n, _ in used} - {n for n, _ in keep}):
            candidates = sorted((m for n, m in used if n == name),
                                key=lambda m: (len(pulls[(name, m)]), m))
            keep.add((name, candidates[0]))

        umbrellas = sorted({include for path in sources
                            for _, include in INCLUDE.findall(read(path))
                            if include in (library.umbrella for library in self.libraries)})
        return used, keep, umbrellas


def find_libraries(folder):
    libraries = []
    for child in sorted(folder.iterdir()):
        if child.is_dir():
            library = Library.find(child)
            if library:
                libraries.append(library)
    return libraries


def main(argv):
    default_libraries = pathlib.Path(__file__).resolve().parent.parent.parent
    parser = argparse.ArgumentParser(
        description="Report which RoModular libraries and modules a project uses "
                    "and suggest root headers to replace umbrella headers.")
    parser.add_argument("project", type=pathlib.Path,
                        help="project folder or sketch folder to scan")
    parser.add_argument("--libraries", type=pathlib.Path, default=default_libraries,
                        help="RoModular workspace or Arduino libraries folder "
                             "(default: the folder that contains this RoModular checkout)")
    arguments = parser.parse_args(argv)

    project = arguments.project.resolve()
    if not project.is_dir():
        parser.error("project folder not found: {}".format(arguments.project))
    if not arguments.libraries.is_dir():
        parser.error("libraries folder not found: {}".format(arguments.libraries))
    libraries = find_libraries(arguments.libraries.resolve())
    if not libraries:
        parser.error("no RoModular libraries found in {}".format(arguments.libraries))

    scanner = Scanner(libraries)
    # Dependencies first: order libraries by how many others they pull in.
    libraries.sort(key=lambda library: (len({n for n, _ in scanner.closure(
        [library.src / library.umbrella], True)} - {library.name}), library.name))
    used, keep, umbrellas = scanner.scan(project)

    print("Modules used:")
    for library in libraries:
        modules = sorted(m for n, m in used if n == library.name and m != SETTINGS)
        if modules:
            text = ", ".join(modules)
        elif any(n == library.name for n, _ in used):
            text = "version and settings only"
        else:
            text = "not used"
        print("  {}: {}".format(library.name, text))

    print("")
    print("Umbrella headers included: {}".format(", ".join(umbrellas) or "none"))
    print("Suggested root headers:")
    for library in libraries:
        for name, module in sorted(keep):
            if name == library.name:
                print("  #include <{}>".format(library.root_headers.get(module, library.umbrella)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
