#!/usr/bin/lua

--[[
-- Based on CCS API docs: https://software-dl.ti.com/ccs/esd/documents/users_guide_ccs_20.1.0/ccs_project-command-line-full-api-guide.html#
--]]

local argparse = require("argparse")
local json = require("dkjson")

-- ANSI shadow from https://patorjk.com/software/taag/
-- All parser arguments specified at bottom of file 
-- after API
local parser = argparse()
                :name("ccs-admin")
                :add_complete()
                :description(
[[
 ██████╗ ██████╗███████╗               █████╗ ██████╗ ███╗   ███╗██╗███╗   ██╗
██╔════╝██╔════╝██╔════╝              ██╔══██╗██╔══██╗████╗ ████║██║████╗  ██║
██║     ██║     ███████╗    █████╗    ███████║██║  ██║██╔████╔██║██║██╔██╗ ██║
██║     ██║     ╚════██║    ╚════╝    ██╔══██║██║  ██║██║╚██╔╝██║██║██║╚██╗██║
╚██████╗╚██████╗███████║              ██║  ██║██████╔╝██║ ╚═╝ ██║██║██║ ╚████║
 ╚═════╝ ╚═════╝╚══════╝              ╚═╝  ╚═╝╚═════╝ ╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝
Garrett Wells
Nov. 2025

- run from inside project working directory 
- specify project metadata(version, command strings, etc) inside "metadata.json"

Order of Operations:
1. increment version string     (flag)
2. execute pre-build commands   (flag)
3. execute ccs action           create/build(default)/inspect
4. execute post-build commands  (flag)
]])

-- default globals
local actions = {"create", "build", "inspect", "util"}
local json_meta_fn = "metadata.json"
local json_meta = nil

local ccs_ver = nil
local ccs_wkspc_dir = "."
local project_name = nil
local project_path = nil
local project_config_profile = nil
local verbose = false -- enable/disable verbose debug msgs

local json_template = {
    ["version_cmd"] = {
        ["major"] = "<cmd that increments major version>",
        ["minor"] = "<cmd that increments minor version>",
        ["patch"] = "<cmd increment patch>",
    },
    ["project"] = {
        ["name"] = "<project-name>",
        ["path"] = "<path/to/project/directory>",
        ["workspace"] = "<path/to/workspace/file.theia-workspace>",
        ["configuration"] = "<default-build-profile-like-Debug>",
        ["ccs_version"] = 20,
    },
    ["pre_build_cmds"] = {"list", "of", "cmds","executed in shell before build"},
    ["post_build_cmds"] =  {"list", "of", "cmds","executed in shell after build"},
}

--[[
-- API Definition
--]]
local function configure_globals_from_json(jsonobj)
    if jsonobj then
        if jsonobj.project then
            if jsonobj.project.ccs_version then 
                ccs_ver = jsonobj.project.ccs_version
                if verbose then print("CCS VERSION: v"..ccs_ver) end
            end
            -- check for name
            if jsonobj.project.name then 
                project_name = jsonobj.project.name 
                if verbose then print("NAME       : "..project_name) end
            end

            if jsonobj.project.path then 
                project_path = jsonobj.project.path
                if verbose then print("PATH       : "..project_path) end
            end
            -- check for workspace
            if jsonobj.project.workspace then 
                ccs_wkspc_dir = jsonobj.project.workspace 
                if verbose then print("WORKSPACE  : "..ccs_wkspc_dir) end
            end
            -- check for project configuration
            if jsonobj.project.configuration then 
                project_config_profile = jsonobj.project.configuration 
                if verbose then print("PROFILE    : "..project_config_profile) end
            end
        end
    elseif verbose then
        print("[ ERROR ] no json object found")
    end

end

local function json_load_meta_file(fn)
    local file = io.open(fn, "rb")
    if file == nil then
        if verbose then 
            print("[ ERROR ] could not find file: ", fn)
        end
        return nil
    end

    local content = file:read "*a" -- read whole file
    file:close()

    local obj, pos, err = json.decode(content, 1, nil)
    if err then print("[ ERROR ] json parse: ", err) end

    return obj
end

local function print_expected_json_structure()
    local str = json.encode(json_template, {indent=true})
    print(str)
end

local function execute_pre_build_scripts()
    if json_meta.pre_build_cmds then 
        -- iterate over pre-build cmds and execute them
        for i=0, #json_meta.pre_build_cmds, 1 do 
            if verbose then
                print(json_meta.pre_build_cmds[i])
            end
            os.execute(json_meta.pre_build_cmds[i])
        end
    end
end

local function execute_post_build_scripts()
    if json_meta.post_build_cmds then 
        -- iterate over post-build cmds and execute them
        for i=0, #json_meta.post_build_cmds, 1 do 
            if verbose then
                print(json_meta.post_build_cmds[i])
            end
            os.execute(json_meta.post_build_cmds[i])
        end
    end
end

local function execute_version_increment_script(segment)
    if json_meta.version_cmd then 
        cmd_str = nil
        if segment == "M" then 
            cmd_str = json_meta.version_cmd.major
        elseif segment == "m" then 
            cmd_str = json_meta.version_cmd.minor
        elseif segment == "p" then 
            cmd_str = json_meta.version_cmd.patch
        else 
            print("[ERROR] bad input segment", segment, "should be one of [M,m,p]")
            return
        end
        
        if verbose then
            print(cmd_str)
        end
        os.execute(cmd_str)
    else 
        print("[ERROR] no version command specified in", json_meta_fn, ", skipping.")
        return
    end
end

local ccs_vers = {12,20}
local ccs_cmd_strs = {
    [12] = "eclipse -noSplash -data %s -application com.ti.ccstudio.apps.projectBuild -ccs.projects %s",
    [20] = "ccs-server-cli.sh -noSplash -ccs.autoOpen -ccs.autoImport -workspace %s -application com.ti.ccs.apps.buildProject -ccs.projects %s"
}

-- format a string that can be executed
local function get_build_cmd(ver, workspace, name, clean, configuration)

    local ccs_format_str = nil
    if ccs_cmd_strs[ver] == nil then 
        ver = ccs_vers[#ccs_vers]
        ccs_format_str = ccs_cmd_strs[ver] -- default to latest supported
    else
        ccs_format_str = ccs_cmd_strs[ver]
    end

    if clean then -- clean before build
        ccs_format_str = ccs_format_str .. " -ccs.clean"
    end

    if configuration then -- build specified configuration profile
        ccs_format_str = ccs_format_str ..
                        " -ccs.configuration ".. 
                        configuration
    end

    local cmd_str = string.format(ccs_format_str,
                                  workspace, 
                                  name)

    if verbose then
        print(cmd_str)
    end
    return cmd_str
end

local function create_project(proj_path, workspace, 
                            proj_spec, name, device)
    local ccs_format_str =
            [[ccs-server-cli.sh -noSplash -workspace %s -application com.ti.ccs.apps.createProject (-ccs.projectSpec %s | -ccs.name %s -ccs.device %s)]]
    local cmd_str = string.format(ccs_format_str, 
                                workspace, 
                                proj_spec, 
                                name, 
                                device)
    if verbose then
        print(cmd_str)
    end
    ois.execute(cmd_str)
end

local function import_project(workspace, path)
    local ccs_format_str =
            [[ccs-server-cli.sh -noSplash -workspace %s -application com.ti.ccs.apps.importProject -ccs.location %s]]
    local cmd_str = string.format(ccs_format_str, 
                                workspace, 
                                path)
    if verbose then
        print(cmd_str)
    end
    os.execute(cmd_str)

end

local function build_project(ccs_ver, workspace, name, clean, configuration)
    clean = clean or false

    if ccs_ver == nil then 
        ccs_ver = ccs_vers[#ccs_vers]
        if verbose then
            print('[WARNING] Defaulting to CCSv' .. ccs_ver)
        end
    end

    -- if version 12 import manually first
    if ccs_ver <= 12 then
        if verbose then
            print("[ DEBUG ] importing project...")
        end
        cmd = "eclipse -noSplash -data %s -application com.ti.ccstudio.apps.projectImport -ccs.location %s"
        cmd = string.format(cmd, workspace, project_path)
        if verbose then
            print(cmd)
        end
        os.execute()
    end

    cmd_str = get_build_cmd(ccs_ver, workspace, name, clean, configuration)
    if verbose then
        print(cmd_str)
    end
    os.execute(cmd_str)
end

local function inspect_project(workspace, name, errors, problems, variables, build_opts)
    errors = errors or true
    problems = problems or true
    variables = variables or true
    build_opts = build_opts or true

    local ccs_format_str = "ccs-server-cli.sh -noSplash -ccs.format:json -workspace %s -application com.ti.ccs.apps.inspect -ccs.projects %s"

    if errors then ccs_format_str = ccs_format_str .. "-ccs.projects:listErrors " end
    if problems then ccs_format_str = ccs_format_str .. "-ccs.projects:listProblems " end
    if variables then ccs_format_str = ccs_format_str .. "-ccs.projects:listVariables" end
    if build_opts then ccs_format_str = ccs_format_str .. "-ccs.projects:showBuildOptions " end

    local cmd_str = string.format(ccs_format_str, workspace, name)
    if verbose then
       print(cmd_str)
    end
    os.execute(cmd_str)
end

parser
    :argument("action")
    :description("select what action to take such as create new project or build/inspect existing project")
    :choices(actions)
    :default("util")
    
parser
    :argument("project")
    :args("?")
    :description("specify name of project to build, must be inside workspace")

parser
    :option("--config")
    :description("specify which project configuration profile to build")
    :args(1)

parser
    :flag("--pre")
    :description("set to run pre build commands")

parser
    :flag("--post")
    :description("set to run post build commands")

parser
    :flag("-c --clean")
    :description("set to clean before build(rebuild)")

parser
    :flag("-l --list")
    :description("list/print contents of the metadata file")
    :action(
        function()
            json_meta = json_load_meta_file(json_meta_fn)
            local json_str = json.encode(json_meta, {indent = true})
            if verbose then
                print("[ DEBUG ] list of metadata contents\n",json_str)
            end
        end
    )

parser
    :flag("-v --verbose")
    :description("enable debug messages")
    :action(function(res_tbl,ndx,arg,flag) verbose = true end)

parser
    :option("-w --workspace")
    :description("optionally specify the workspace profile file(>=v20)/directory(<=v12) location")
    :action(function(res_tbl, ndx, arg, flag) ccs_wkspc_dir = arg end)

parser
    :flag("-p --increment-patch")
    :description("increments the SW version string header(always before build) using the script command in metadata.json")
    :action(function() execute_version_increment_script("p") end)

parser
    :flag("-m --increment-minor")
    :description("increments the SW version string header(always before build) using the script command in metadata.json")
    :action(function() execute_version_increment_script("m") end)

parser
    :flag("-M --increment-major")
    :description("increments the SW version string header(always before build) using the script command in metadata.json")
    :action(function() execute_version_increment_script("M") end)

parser
    :flag("--json-template")
    :description("print expected structure and fields of json file(or write to file)")
    :action(function() print_expected_json_structure() end)


--[[
-- Step 3/3: Execute!
--]]
local args = parser:parse()
    
-- attempt to load metadata
-- no errors printed if not found unless in verbose mode
json_meta = json_load_meta_file(json_meta_fn)
if json_meta ~= nil then
    configure_globals_from_json(json_meta)
end

-- [[
-- Flags defining information for needed for build
-- supersede/override metadata file content(if present).
-- ]]
if args.project then 
    project_name = args.project
end

if args.config then
    project_config_profile = args.config
end

-- 1/3 Execute Pre-Build Commands
if args.pre then 
    if verbose then
        print("[ DEBUG ] executing pre-build commands")
    end
    execute_pre_build_scripts()
end

-- check that project name is defined - required for builds
if project_name == nil then 
    print("[ ERROR ] no project name provided, aborting")
    os.exit()
end

-- 2/3 Execute Primary Action (Build/Inspect/Etc.)
if args.action == "build" then
    build_project(
        ccs_ver,
        ccs_wkspc_dir,
        project_name,
        args.clean,
        project_config_profile)

elseif args.action == "create" then 
    create_project("./", args.workspace, nil, args.project, nil)

elseif args.action == "inspect" then
    inspect_project(
    ccs_wkspc_dir,
    project_name)
elseif args.action == "util" then 
    -- do something
else
    if verbose then
        print("[ DEBUG ] unrecognized CCS action", args.action)
    end
end

-- 3/3 Execute Post-Build Commands
if args.post then 
    if verbose then
        print("[ DEBUG ] executing post-build commands")
    end
    execute_post_build_scripts() 
end
