# Note: argument order does not matter when setting argv; all arguments are optional
# Usage (No Defaults):
#   set argv "-r <repo_path> -x <xpr_path> -v <vivado_version>
#   source vivado-checkin.tcl
# Usage (All Defaults):
#   set argv ""
#   source vivado-checkin.tcl

foreach arg $argv {
    puts $arg
}

# Collect local sources, move them to ../src/<category>
# Collect sdk project & BSP & dummy hardware platform, and move them to ../sdk

# Handle repo_path argument
set idx [lsearch ${argv} "-r"]
if {${idx} != -1} {
    set repo_path [glob -nocomplain [file normalize [lindex ${argv} [expr {${idx}+1}]]]]
} else {
    # Default
    set repo_path [file normalize [file join [file dirname [info script]] ..]]
}

# Handle xpr_path argument
set idx [lsearch ${argv} "-x"]
if {${idx} != -1} {
    set xpr_path [glob -nocomplain [file normalize [lindex ${argv} [expr {${idx}+1}]]]]
} else {
    # Default
    set xpr_path [glob -nocomplain "${repo_path}/proj/*.xpr"]
}
if {[llength ${xpr_path}] != 1} {
    puts "ERROR: XPR not found"
} else {
    set xpr_path [lindex ${xpr_path} 0]
}

# Handle vivado_version argument
set idx [lsearch ${argv} "-v"]
if {${idx} != -1} {
    set vivado_version [lindex ${argv}]
} else {
    set vivado_version [version -short]
}

set vivado_version [lindex $argv 2]; # unused

# Other variables
set force_overwrite_info_script 0; # included for possible argument support in future
set proj_file [file tail $xpr_path]
set proj_dir [file dirname $proj_file]
set proj_name [file rootname [file tail $proj_file]]

puts "INFO: Checking project \"$proj_file\" into version control."
set already_opened [get_projects -filter "DIRECTORY==$proj_dir && NAME==$proj_name"]
if {[llength $already_opened] == 0} {
    open_project $xpr_path
} else {
    current_project [lindex $already_opened 0]
}

# Create directories that are written to. These might not get used, and if
# they are empty they will not be tracked by git.
set required_dirs [list        \
    $repo_path/proj            \
    $repo_path/src             \
    $repo_path/src/bd          \
    $repo_path/src/constraints \
    $repo_path/src/ip          \
    $repo_path/src/hdl         \
    $repo_path/src/sim         \
    $repo_path/repo            \
    $repo_path/repo/local      \
    $repo_path/repo/cache      \
    $repo_path/sdk             \
]
foreach d $required_dirs {
    if {[file exists $d] == 0} {
        file mkdir $d
    }
}

# Save block design Tcl script
set bd_files [get_files -of_objects [get_filesets sources_1] -filter "NAME=~*.bd"]
if {[llength $bd_files] > 1} {
    puts "ERROR: This script cannot handle projects containing more than one block design!"
} elseif {[llength $bd_files] == 1} {
    set bd_file [lindex $bd_files 0]
    open_bd_design $bd_file
    set bd_name [file tail [file rootname [get_property NAME $bd_file]]]
    set script_name "$repo_path/src/bd/${bd_name}.tcl"
    puts "INFO: Checking in ${script_name} to version control."
    write_bd_tcl -force -make_local $script_name
}

# Save HDL sources
foreach source_file [get_files -of_objects [get_filesets sources_1]] {
    set origin [get_property name $source_file]
    set skip 0

    if {[regexp "^$repo_path/src/.*" $origin]} {
        set skip 1
    } elseif {[regexp "^.*/sources_1/new/.*\.vhd$" $origin]} {
        set subdir hdl
    } elseif {[regexp "^.*/sources_1/new/.*\.v$" $origin]} {
        set subdir hdl
    } elseif {[regexp "^.*/sources_1/new/.*\.sv$" $origin]} {
        set subdir hdl
    } elseif {[regexp "^.*/sources_1/new/.*\.svh$" $origin]} {
        set subdir hdl
    } else {
        set skip 1
    }

    if {$skip == 1} {
        continue
    }

    # Make sure this file is not part of an IP
    foreach ip [get_ips] {
        set ip_dir [get_property IP_DIR $ip]
        set source_length [string length $source_file]
        set dir_length [string length $ip_dir]
        if {$source_length >= $dir_length && [string range $source_file 0 $dir_length-1] == $ip_dir} {
            set skip 1
            break
        }
    }

    if {$skip == 1} {
        continue
    }

    puts "INFO: Checking in [file tail $origin] to version control."
    set target $repo_path/src/$subdir/[file tail $origin]
    if {[file exists $target] == 0} {
        file copy -force $origin $target
    }
}

# Save simulation sources
foreach sim_file [get_files -of_objects [get_filesets sim_1]] {
    set origin [get_property name $sim_file]
    set skip 0

    if {[regexp "^$repo_path/src/.*" $origin]} {
        set skip 1
    } elseif {[regexp "^.*/sim_1/new/.*\.vhd$" $origin]} {
        set subdir sim
    } elseif {[regexp "^.*/sim_1/new/.*\.v$" $origin]} {
        set subdir sim
    } elseif {[regexp "^.*/sim_1/new/.*\.sv$" $origin]} {
        set subdir sim
    } elseif {[regexp "^.*/sim_1/new/.*\.svh$" $origin]} {
        set subdir sim
    } else {
        set skip 1
    }

    if {$skip == 1} {
        continue
    }

    puts "INFO: Checking in [file tail $origin] to version control."
    set target $repo_path/src/$subdir/[file tail $origin]
    if {[file exists $target] == 0} {
        file copy -force $origin $target
    }
}


# Save IP sources
foreach ip [get_ips] {
    set origin [get_property ip_file $ip]
    # Skip IP that are generated as part of a block design
    if {[regexp "^.*/sources_1/bd/.*$" $origin]} {
        continue
    }
    set ipname [get_property name $ip]
    set dir "$repo_path/src/ip/$ipname"
    if {[file exists $dir] == 0} {
        file mkdir $dir
    }
    set target $dir/[file tail $origin]
    puts "INFO: Checking in [file tail $origin] to version control."
    if {[file exists $target] == 0} {
        file copy -force $origin $target
    }
}

# Save constraint files
foreach constraint_file [get_files -of_objects [get_filesets constrs_1]] {
    set origin [get_property name $constraint_file]
    set target $repo_path/src/constraints/[file tail $origin]
    puts "INFO: Checking in [file tail $origin] to version control."
    if {[file exists $target] == 0} {
        file copy -force $origin $target
    }
}

# Save project-specific settings into project_info.tcl. project_info.tcl will
# only be created if it doesn't exist - if it has been manually deleted by the
# user, or if this is the first time this repo is checked in
if {[file exists $repo_path/project_info.tcl] == 0 || $force_overwrite_info_script != 0} {
    set proj_obj [get_projects [file rootname $proj_file]]
    set board_part [current_board_part -quiet]
    set part [get_property part $proj_obj]
    set default_lib [get_property default_lib $proj_obj]
    set simulator_language [get_property simulator_language $proj_obj]
    set target_language [get_property target_language $proj_obj]
    puts "INFO: Checking in project_info.tcl to version control."
    set file_name $repo_path/project_info.tcl
    set file_obj [open $file_name "w"]
    puts $file_obj "# This is an automatically generated file used by vivado-checkout.tcl to set project options"
    puts $file_obj "proc set_project_properties_post_create_project {proj_name} {"
    puts $file_obj "    set project_obj \[get_projects \$proj_name\]"
    puts $file_obj "    set_property \"part\" \"$part\" \$project_obj"
    if {$board_part ne ""} {
        puts $file_obj "    set_property \"board_part\" \"$board_part\" \$project_obj"
    }
    puts $file_obj "    set_property \"default_lib\" \"$default_lib\" \$project_obj"
    puts $file_obj "    set_property \"simulator_language\" \"$simulator_language\" \$project_obj"
    puts $file_obj "    set_property \"target_language\" \"$target_language\" \$project_obj"
    puts $file_obj "}"
    puts $file_obj ""
    puts $file_obj "proc set_project_properties_pre_add_repo {proj_name} {"
    puts $file_obj "    set project_obj \[get_projects \$proj_name\]"
    puts $file_obj "    # default nothing"
    puts $file_obj "}"
    puts $file_obj ""
    puts $file_obj "proc set_project_properties_post_create_runs {proj_name} {"
    puts $file_obj "    set project_obj \[get_projects \$proj_name\]"
    puts $file_obj "    # set_property \"top\" \"top_module_name\" \[current_fileset\]"
    puts $file_obj "    # default nothing"
    puts $file_obj "}"

    close $file_obj
}

set script_dir [file normalize [file dirname [info script]]]
# If .gitignore does not exist, create it
set master_gitignore [file join $repo_path .gitignore]
if {[file exists $master_gitignore] == 0} {
    puts "INFO: This repository does not contain a master gitignore. Creating one now."
    set target $master_gitignore
    set origin [file join $script_dir template-master.gitignore]
    file copy -force $origin $target
}
# If sdk/.gitignore does not exist, create it
set sdk_gitignore [file join $repo_path sdk .gitignore]
if {[file exists $sdk_gitignore] == 0} {
    puts "INFO: This repository does not contain an sdk gitignore. Creating one now."
    set target $sdk_gitignore
    set origin [file join $script_dir template-sdk.gitignore]
    file copy -force $origin $target
}

# Remove empty required directories. Do these in reverse so the children are
# deleted first.
foreach d [lreverse $required_dirs] {
    set file_list [glob -nocomplain "$d/*"]
    if {[llength $file_list] == 0} {
        file delete -force "$d"
    }
}

puts "INFO: Project $proj_file has been checked into version control"
