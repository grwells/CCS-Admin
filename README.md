# CCS-Admin

Script for creating/building/inspecting CCStudio projects from the command line using Lua. 

Provides workflow automation by:

1. Allowing CCS project variables to be stored in `metadata.json`.
2. Providing the ability to execute pre/post build steps including:
    1. Semantic Version Control - the user can specify commands to be run to increment the semantic version to be used in a build (see [grwells/CSemantic-Version](github.com/grwells/CSemantic-Version) as an example).
    2. Pre-build Commands - ability to specify a list of string commands to be executed on the command line _before_ building (_ex._ generate headers, metadata, _etc._).
    3. Post-build Commands - the ability to specify list of commands to be executed _after_ building (_ex._ package/rename binaries).

3. Generally making everything **less verbose**.
