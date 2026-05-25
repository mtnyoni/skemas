package main

import "core:strings"
import im "vendor/odin-imgui"

UIWorkspace :: proc(state: ^App_State) {
	@(static) loaded_dbs: []string
	@(static) dbs_loaded: bool
	@(static) selected_db: string
	@(static) prev_selected_db: string

	@(static) loaded_schemas: []string
	@(static) schemas_loaded: bool
	@(static) selected_schema: string
	@(static) prev_selected_schema: string

	@(static) loaded_tables: []string
	@(static) tables_loaded: bool
	@(static) selected_table: string

	pg_conn := state.conn.(PQ_Conn)

	if !dbs_loaded || state.needs_db_reload {
		dbs, err := pg_get_dbs(pg_conn)
		if err != nil {
			panic(err.(DB_Open_Failed).message)
		}

		loaded_dbs = dbs
		dbs_loaded = true
		state.needs_db_reload = false

		current_db := pg_current_db(pg_conn)
		selected_db =
			current_db if current_db != "" else (loaded_dbs[0] if len(loaded_dbs) > 0 else "")
		prev_selected_db = selected_db
		schemas_loaded = false
		selected_schema = ""
		prev_selected_schema = ""
		loaded_tables = {}
		tables_loaded = false
		selected_table = ""
	}

	if selected_db != prev_selected_db {
		new_conn, err := pg_connect_to_db(pg_conn, selected_db)
		if err == nil {
			state.conn = new_conn
			pg_conn = new_conn
			schemas_loaded = false
		} else {
			// database doesn't allow connections (e.g. template0) — show empty state
			// without this, schemas_loaded = false would reload from the old connection
			loaded_schemas = {}
			schemas_loaded = true
		}
		selected_schema = ""
		prev_selected_schema = ""
		loaded_tables = {}
		tables_loaded = false
		selected_table = ""
		prev_selected_db = selected_db
	}

	if !schemas_loaded {
		schemas, err := pg_get_schemas(pg_conn)
		if err == nil {
			loaded_schemas = schemas
			schemas_loaded = true
			selected_schema = loaded_schemas[0] if len(loaded_schemas) > 0 else ""
			// prev_selected_schema stays "" so the table-reload block below fires this frame
		}
	}

	if selected_schema != prev_selected_schema {
		loaded_tables = {}
		tables_loaded = false
		selected_table = ""
		if selected_schema != "" {
			tables, err := pg_get_tables(pg_conn, selected_schema)
			if err == nil {
				loaded_tables = tables
				tables_loaded = true
			}
		}
		prev_selected_schema = selected_schema
	}

	display := im.GetIO().DisplaySize
	sidebar_w: f32 = 260

	im.SetNextWindowPos({0, 0}, .Always)
	im.SetNextWindowSize({sidebar_w, display.y}, .Always)
	im.Begin("DBs", nil, {.NoMove, .NoResize, .NoCollapse, .NoScrollbar})
	defer im.End()

	// Database combo
	im.Text("Database")
	im.SetNextItemWidth(-1)
	db_label := strings.clone_to_cstring(
		selected_db if selected_db != "" else "Select database...",
	)
	defer delete(db_label)
	if im.BeginCombo("##db_select", db_label) {
		for db in loaded_dbs {
			cname := strings.clone_to_cstring(db)
			defer delete(cname)
			if im.Selectable(cname, selected_db == db) {
				selected_db = db
				loaded_schemas = nil
				schemas_loaded = false
				tables_loaded = false
				loaded_tables = nil
			}
		}
		im.EndCombo()
	}

	im.Spacing()

	// Schema combo
	im.Text("Schema")
	im.SetNextItemWidth(-1)
	schema_label := strings.clone_to_cstring(
		selected_schema if selected_schema != "" else "Select schema...",
	)
	defer delete(schema_label)
	if im.BeginCombo("##schema_select", schema_label) {
		for s in loaded_schemas {
			cname := strings.clone_to_cstring(s)
			defer delete(cname)
			if im.Selectable(cname, selected_schema == s) {
				selected_schema = s
			}
		}
		im.EndCombo()
	}

	im.Spacing()

	// Tables list
	im.Text("Tables")
	im.BeginChild("##tables_list", {-1, -1}, {.Borders})
	for tbl in loaded_tables {
		cname := strings.clone_to_cstring(tbl)
		defer delete(cname)
		if im.Selectable(cname, selected_table == tbl) {
			selected_table = tbl
		}
	}
	im.EndChild()

	im.SetNextWindowPos({0 + sidebar_w, 0}, .Always)
	im.SetNextWindowSize({display.x - sidebar_w, display.y}, .Always)
	im.Begin("Workspace", nil, {.NoMove, .NoResize, .NoCollapse, .NoScrollbar})
	defer im.End()


	
	im.BeginTable("Table", len())

}
