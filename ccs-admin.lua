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

Execution Order
1. increment version string (optional)
2. execute pre-build commands (optional)
3. execute ccs command
4. execute post-build commands (optional)
]])

-- default globals
local json_meta_fn = "metadata.json"
local json_meta = nil

local ccs_eclipse_dir = "~/ti/ccs2020/ccs/eclipse/"
local ccs_wkspc_dir = "."
local project_name = nil
local project_path = nil
local project_config_profile = "Debug"

--[[
-- API Definition
--]]

local function configure_globals_from_json()
    if json_meta then
        if json_meta.project then
            --local json_str = json.encode(json_meta.project, {indent = true})
            --print(json_str)
            -- check for name
            if json_meta.project.name then 
                project_name = json_meta.project.name 
            end

            if json_meta.project.path then 
                project_path = json_meta.project.path
            end
            -- check for workspace
            if json_meta.project.workspace then 
                ccs_wkspc_dir = json_meta.project.workspace 
            end
            -- check for project configuration
            if json_meta.project.configuration then 
                project_config_profile = json_meta.project.configuration 
            end
            print("[DEBUG] configured globals:", "\nNAME:      "..project_name, "\nPROFILE:   "..project_config_profile, "\nPATH:      "..project_path,
            "\nWORKSPACE: "..ccs_wkspc_dir)
        else 
            print("[ERROR] no project field")
        end
    else
        print("[ERROR] no json obj")
    end

end

local function json_load_meta_file(fn)
    local file = io.open(fn, "rb")
    if not file then return nil end

    local content = file:read "*a" -- read whole file
    file:close()

    local obj, pos, err = json.decode(content, 1, nil)

    if err then print("[ERROR]", err) end

    json_meta = obj
    return obj
end

local function print_expected_json_structure()
    local str = 
[[
Notes:
    - none of this is required to use ccs-admin, it is to help
        automate workflows on CCS projects
    - default file name is "metadata.json"
    - all cmds need to be accessible via path/have full path specified
{
    version_cmd: {
        major: str cmd for incrementing major ver
        minor: str cmd for incrementing minor ver
        patch: str cmd for incrementing patch ver
    },
    project: {
        name: "default project name"
        workspace: "default workspace file path"
    }
    pre_build_cmds: ["list", "of", "cmd","strings"]
    pre_build_cmds: ["list", "of", "cmd","strings"]
}
]]
    print(str)
end

local function execute_pre_build_scripts()
    if json_meta.pre_build_cmds then 
        -- iterate over pre-build cmds and execute them
        for i=0, #json_meta.pre_build_cmds, 1 do 
            print(">", json_meta.pre_build_cmds[i])
            os.execute(json_meta.pre_build_cmds[i])
        end
    end
end

local function execute_post_build_scripts()
    if json_meta.post_build_cmds then 
        -- iterate over post-build cmds and execute them
        for i=0, #json_meta.post_build_cmds, 1 do 
            print(">", json_meta.post_build_cmds[i])
            os.execute(json_meta.post_build_cmds[i])
        end
    end
end

local function execute_version_increment_script(segment)
    if json_meta.version_cmd then 
        if segment == "M" then 
            os.execute(json_meta.version_cmd.major)
        elseif segment == "m" then 
            os.execute(json_meta.version_cmd.minor)
        elseif segment == "p" then 
            os.execute(json_meta.version_cmd.patch)
        else 
            print("[ERROR] bad input segment", segment, "should be one of [M,m,p]")
        end
    else 
        print("[ERROR] no version command specified in", json_meta_fn, ", skipping.")
    end
end

local function create_project(proj_path, workspace, 
                            proj_spec, name, device)
    local ccs_format_str =
            "ccs-server-cli.sh -noSplash -workspace %s \z
            -application com.ti.ccs.apps.createProject \z
            (-ccs.projectSpec %s | -ccs.name %s -ccs.device %s)"
    local cmd_str = string.format(ccs_eclipse_dir .. ccs_format_str, 
                                workspace, 
                                proj_spec, 
                                name, 
                                device)
    os.execute(cmd_str)
end

local function import_project(workspace, path)
    local ccs_format_str =
            "ccs-server-cli.sh -noSplash -workspace %s \z
            -application com.ti.ccs.apps.importProject \z
            -ccs.location %s"
    local cmd_str = string.format(ccs_eclipse_dir .. ccs_format_str, 
                                workspace, 
                                path)
    os.execute(cmd_str)

end

local function build_project(workspace, name, clean, configuration)
    clean = clean or false

    local ccs_format_str = "ccs-server-cli.sh \z
                -noSplash \z
                -ccs.autoOpen \z
                -ccs.autoImport \z
                -workspace %s \z
                -application com.ti.ccs.apps.buildProject \z
                -ccs.projects %s"

    if clean then
        ccs_format_str = ccs_format_str .. " -ccs.clean"
    end

    if configuration then
        ccs_format_str = ccs_format_str ..
                        " -ccs.configuration ".. 
                        configuration
    end

    -- [[
    --local cmd_str = string.format(ccs_eclipse_dir .. ccs_format_str ..
     --                           " | grep -E --color=always \'error|warning|$\'", 
      --                          workspace, 
       --                         name)
    -- ]]
    local cmd_str = string.format(ccs_eclipse_dir .. ccs_format_str,
                                workspace, 
                                name)
    print(">", cmd_str)

    os.execute(cmd_str)
end

local function inspect_project(workspace, name, errors, problems, variables, build_opts)
    errors = errors or true
    problems = problems or true
    variables = variables or true
    build_opts = build_opts or true

    local ccs_format_str = ccs_eclipse_dir .. "ccs-server-cli.sh \z
                    -noSplash \z
                    -ccs.format:json \z
                    -workspace %s \z
                    -application com.ti.ccs.apps.inspect \z
                    -ccs.projects %s "

    if errors then ccs_format_str = ccs_format_str .. "-ccs.projects:listErrors " end
    if problems then ccs_format_str = ccs_format_str .. "-ccs.projects:listProblems " end
    if variables then ccs_format_str = ccs_format_str .. "-ccs.projects:listVariables" end
    if build_opts then ccs_format_str = ccs_format_str .. "-ccs.projects:showBuildOptions " end

    local cmd_str = string.format(ccs_format_str, workspace, name)
    os.execute(cmd_str)
end

parser
    :argument("action")
    :description("select what action to take such as create new project or build/inspect existing project")
    :choices {"create", "build", "inspect"}
    :default("build")
    
parser
    :argument("project")
    :args("?")
    :description("specify name of project to build, must be inside workspace")
    :action(
        function(res_tbl, ndx, arg, flag) 
            if project_name == nil then 
                project_name = arg 
            end
        end)

parser
    :option("-c --configuration")
    :description("specify which project configuration profile to build")
    :action(
        function(res_tbl, ndx, arg, flag) 
            project_config_profile = arg 
        end)

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
    :flag("--list")
    :description("list/print contents of the metadata file")
    :action(
        function()
            local json_str = json.encode(json_meta, {indent = true})
            print("[DEBUG] list of metadata contents\n",json_str)
        end
    )

parser
    :option("-w --workspace-profile")
    :description("optionally specify the workspace profile file location")
    :action(function(res_tbl, ndx, arg, flag) ccs_wkspc_dir = arg end)

parser
    :flag("--increment-patch")
    :description("increments the SW version string header(always before build) using the script command in metadata.json")
    :action(function() execute_version_increment_script("p") end)

parser
    :flag("--increment-minor")
    :description("increments the SW version string header(always before build) using the script command in metadata.json")
    :action(function() execute_version_increment_script("m") end)

parser
    :flag("--increment-major")
    :description("increments the SW version string header(always before build) using the script command in metadata.json")
    :action(function() execute_version_increment_script("M") end)

parser
    :flag("--print-json-docs")
    :description("print expected structure and fields of json file(note json not req'd to CLI use)")
    :action(function() print_expected_json_structure() end)


--[[
-- Step 3/3: Execute!
--]]
json_load_meta_file(json_meta_fn)
configure_globals_from_json()

local args = parser:parse()

if args.pre then 
    print("[DEBUG] executing pre-build commands")
    execute_pre_build_scripts()
end

if project_name == nil then 
    print("[ERROR] no project name provided, aborting")
    os.exit()
end

if args.action == "build" then
    build_project(
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
else 
    print("[DEBUG] unrecognized CCS action", args.action)
end

if args.post then 
    print("[DEBUG] executing post-build commands")
    execute_post_build_scripts() 
end
