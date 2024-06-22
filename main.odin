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
	root:        ^Package,
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
	
	{
		pkg := new(Package)
		pkg.name     = "base/runtime"
		pkg.fullpath = filepath.join({ODIN_ROOT + "base", "runtime"})
		graph.packages[pkg.fullpath] = pkg
	}
	{
		pkg := new(Package)
		pkg.name     = "base/builtin"
		pkg.fullpath = filepath.join({ODIN_ROOT + "base", "builtin"})
		graph.packages[pkg.fullpath] = pkg
	}
	{
		pkg := new(Package)
		pkg.name     = "base/intrinsics"
		pkg.fullpath = filepath.join({ODIN_ROOT + "base", "intrinsics"})
		graph.packages[pkg.fullpath] = pkg
	}

	root_pkg := new(Package)
	root_pkg.fullpath = package_path

	graph.root = root_pkg
	graph.packages[package_path] = root_pkg

	ast_pkg := parser.parse_package_from_path(package_path) or_else error("Parsing package %q failed", package_path)

	root_pkg.name = ast_pkg.name

	walk_package(root_pkg, &graph, ast_pkg)

	stdout_s := os.stream_from_handle(os.stdout)
	write_graph(stdout_s, graph)
}

write_graph :: proc(s: io.Stream, g: Graph) {
	ws :: io.write_string

	for _, pkg in g.packages {
		if len(pkg.imports) == 0 do continue

		ws(s, pkg.name)
		ws(s, "\n")

		for dep in pkg.imports {
			ws(s, "\t<- ")
			ws(s, dep.name)
			ws(s, "\n")
		}
	}
}

walk_package :: proc(pkg: ^Package, g: ^Graph, ast_pkg: ^ast.Package)
{
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
	
				col_path := g.collections[collection] or_else error("Unknown collection %q", collection)
				
				import_path = filepath.join({col_path, pkg})
			} else {
				import_path = filepath.join({pkg.fullpath, import_path})
			}

			import_pkg, has_pkg := g.packages[import_path]

			if has_pkg {
				if !slice.contains(pkg.imports[:], import_pkg) {
					append(&pkg.imports, import_pkg)
				}
			} else {
				import_pkg = new(Package)
				import_pkg.fullpath = import_path
	
				append(&pkg.imports, import_pkg)
				g.packages[import_path] = import_pkg

				import_pkg.name = import_pkg.fullpath
				if strings.has_prefix(import_pkg.fullpath, ODIN_ROOT) {
					import_pkg.name = import_pkg.name[len(ODIN_ROOT):]
				} else if strings.has_prefix(import_pkg.fullpath, g.root.fullpath){
					import_pkg.name = import_pkg.name[len(g.root.fullpath):]
				}

				ast_pkg := parser.parse_package_from_path(import_path) or_else error("Parsing package %q failed", import_path)
				
				walk_package(import_pkg, g, ast_pkg)
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
