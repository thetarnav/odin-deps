package import_grep

import "core:fmt"
import "core:io"
import "core:odin/ast"
import "core:odin/parser"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"


Graph :: struct {
	collections: map[string]string,
	packages:    map[string]^Package,
}

Package :: struct {
	name:     string,
	fullpath: string,
	imports:  [dynamic]^Package,
}

main :: proc() {
    package_path := os.args[1] if len(os.args) > 1 else os.get_current_directory()

	graph: Graph

	graph.collections["base"]   = ODIN_ROOT + "base"
	graph.collections["core"]   = ODIN_ROOT + "core"
	graph.collections["vendor"] = ODIN_ROOT + "vendor"
	graph.collections["shared"] = ODIN_ROOT + "shared"

	base_packages := []string{"runtime", "builtin", "intrinsics"}
	
	for pkg_name in base_packages {
		pkg := new(Package)
		pkg.name     = pkg_name
		pkg.fullpath = filepath.join({ODIN_ROOT + "base", pkg_name})
		graph.packages[pkg.fullpath] = pkg
	}

	root_pkg := new(Package)
	root_pkg.fullpath = package_path
	walk_package(root_pkg, &graph, package_path)

	stdout_s := os.stream_from_handle(os.stdout)
	write_graph(stdout_s, graph)
}

write_graph :: proc(s: io.Stream, g: Graph) {
	for _, pkg in g.packages {
		write_package(s, pkg^)
	}
}

write_package :: proc(s: io.Stream, pkg: Package) {
	ws :: io.write_string

	for dep in pkg.imports {
		ws(s, "\t")
		ws(s, pkg.name)
		ws(s, " -> ")
		ws(s, dep.name)
		ws(s, "\n")
	}
}

walk_package :: proc(pkg: ^Package, graph: ^Graph, import_path: string)
{
	ast_pkg := parser.parse_package_from_path(import_path) or_else error("Parsing package %q failed", import_path)
	pkg.name = ast_pkg.name

	for _, file in ast_pkg.files {
		for import_node in file.imports {
			import_path := import_node.fullpath[1:len(import_node.fullpath)-1] // Remove quotes

			colon_idx := strings.index_byte(import_path, ':')
			
			if colon_idx == 0 || colon_idx == len(import_path)-1 {
				error("Invalid import path %q", import_path)
			}

			if colon_idx >= 0 {

				collection := import_path[:colon_idx]
				pkg        := import_path[colon_idx+1:]
	
				col_path := graph.collections[collection] or_else error("Unknown collection %q", collection)
				
				import_path = filepath.join({col_path, pkg})
			} else {
				import_path = filepath.join({pkg.fullpath, import_path})
			}

			import_pkg, has_pkg := graph.packages[import_path]

			if has_pkg {
				if !slice.contains(pkg.imports[:], import_pkg) {
					append(&pkg.imports, import_pkg)
				}
			} else {
				import_pkg = new(Package)
				import_pkg.fullpath = import_path
	
				append(&pkg.imports, import_pkg)
				graph.packages[import_path] = import_pkg
				
				walk_package(import_pkg, graph, import_path)
			}
		}
	}
} 

node_string :: proc (node: ast.Node, src: string) -> string {
    return src[node.pos.offset:node.end.offset]
}

ptr :: #force_inline proc (p: ^$T) -> (r: ^T) {
    if p == nil {
        v: T
        r = &v
    } else {
        r = p
    }
    return
}

error :: proc(msg: string, args: ..any) -> ! {
	fmt.eprint("ERROR: ")
	fmt.eprintf(msg, ..args)
	fmt.eprintln()
	os.exit(1)
}
